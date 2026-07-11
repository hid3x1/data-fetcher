#!/bin/bash
set -euo pipefail  # Exit on error, undefined vars, and pipeline failures
IFS=$'\n\t'       # Stricter word splitting

# 1. Extract Docker DNS info BEFORE any flushing
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

# Reset default policies to ACCEPT before flushing. `iptables -F` only clears
# rules, not chain policies, so a re-run after a previous invocation already
# set the default policy to DROP would otherwise block the outbound requests
# below (e.g. fetching GitHub's IP ranges) needed to rebuild the allowlist.
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# Flush existing rules and delete existing ipsets
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

# 2. Selectively restore ONLY internal Docker DNS resolution
if [ -n "$DOCKER_DNS_RULES" ]; then
    echo "Restoring Docker DNS rules..."
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
else
    echo "No Docker DNS rules to restore"
fi

# IPv6 is disabled via `--sysctl net.ipv6.conf.*.disable_ipv6=1` in
# devcontainer.json's runArgs (set by the Docker daemon at container
# creation, since /proc/sys is mounted read-only inside the running
# container). That alone isn't enough though: some allowed domains (e.g.
# go.dev) publish AAAA records, this container has no IPv6 route at all,
# and glibc's getaddrinfo() still hands out those AAAA candidates anyway
# (AI_ADDRCONFIG doesn't reliably detect the disabled stack in this
# environment). A client that tries the IPv6 candidate first (e.g. prek
# downloading the Go toolchain) fails outright — ENETUNREACH, or
# EADDRNOTAVAIL once IPv6 is disabled at the interface level — instead of
# falling back to IPv4. So strip AAAA answers at the DNS layer instead: run
# a local resolver that filters them out, and point /etc/resolv.conf at it.
echo "Starting local AAAA-filtering DNS resolver..."
UPSTREAM_DNS_FILE=/etc/resolv.conf.upstream-dns
if [ ! -s "$UPSTREAM_DNS_FILE" ]; then
    awk '/^nameserver/{print $2; exit}' /etc/resolv.conf > "$UPSTREAM_DNS_FILE"
fi
UPSTREAM_DNS=$(cat "$UPSTREAM_DNS_FILE")
if [ -z "$UPSTREAM_DNS" ]; then
    echo "ERROR: Failed to determine upstream DNS server"
    exit 1
fi

if [ -f /run/dnsmasq-firewall.pid ] && kill -0 "$(cat /run/dnsmasq-firewall.pid)" 2>/dev/null; then
    kill "$(cat /run/dnsmasq-firewall.pid)"
    sleep 1
fi
dnsmasq --user=root --pid-file=/run/dnsmasq-firewall.pid \
    --filter-AAAA --no-resolv --no-hosts \
    --server="$UPSTREAM_DNS" --listen-address=127.0.0.1 --bind-interfaces \
    --port=53

# /etc/resolv.conf is bind-mounted by Docker, so `sed -i` (which rewrites
# via temp-file-then-rename) fails with "Device or resource busy". Rewrite
# in place with a redirect instead, which only opens+truncates the
# existing inode rather than replacing it.
echo "nameserver 127.0.0.1" > /etc/resolv.conf

# First allow DNS and localhost before any restrictions
# Allow outbound DNS
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
# Allow inbound DNS responses
iptables -A INPUT -p udp --sport 53 -j ACCEPT
# Allow outbound SSH
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
# Allow inbound SSH responses
iptables -A INPUT -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT
# Allow localhost
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Create ipset with CIDR support
ipset create allowed-domains hash:net

# Fetch GitHub meta information and aggregate + add their IP ranges
echo "Fetching GitHub IP ranges..."
gh_ranges=$(curl -s https://api.github.com/meta)
if [ -z "$gh_ranges" ]; then
    echo "ERROR: Failed to fetch GitHub IP ranges"
    exit 1
fi

if ! echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null; then
    echo "ERROR: GitHub API response missing required fields"
    exit 1
fi

echo "Processing GitHub IPs..."
while read -r cidr; do
    if [[ ! "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo "ERROR: Invalid CIDR range from GitHub meta: $cidr"
        exit 1
    fi
    echo "Adding GitHub range $cidr"
    ipset add -exist allowed-domains "$cidr"
done < <(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | aggregate -q)

# Resolve and add other allowed domains
# (dl.google.com: go.dev/dl/*.tar.gz downloads 302-redirect here;
#  sum.golang.org: `go install` verifies module checksums against this,
#  e.g. when betterleaks builds itself. GOPROXY=direct (see
#  devcontainer.json) fetches module *source* straight from its VCS host
#  (already-allowlisted github.com) instead of proxy.golang.org, since
#  that proxy fronts modules with signed storage.googleapis.com redirects
#  whose backing IPs are too unstable to allowlist here.)
for domain in \
    "registry.npmjs.org" \
    "pypi.org" \
    "files.pythonhosted.org" \
    "api.anthropic.com" \
    "sentry.io" \
    "statsig.anthropic.com" \
    "statsig.com" \
    "marketplace.visualstudio.com" \
    "vscode.blob.core.windows.net" \
    "update.code.visualstudio.com" \
    "api.github.com" \
    "github.com" \
    "mcp.context7.com" \
    "jsonplaceholder.typicode.com" \
    "api.osv.dev" \
    "go.dev" \
    "dl.google.com" \
    "sum.golang.org"; do
    echo "Resolving $domain..."
    ips=$(dig +noall +answer A "$domain" | awk '$4 == "A" {print $5}')
    if [ -z "$ips" ]; then
        echo "WARN: Failed to resolve $domain — skipping"
        continue
    fi

    while read -r ip; do
        if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "ERROR: Invalid IP from DNS for $domain: $ip"
            exit 1
        fi
        echo "Adding $ip for $domain"
        ipset add -exist allowed-domains "$ip"
    done < <(echo "$ips")
done

# Get host IP from default route
HOST_IP=$(ip route | grep default | cut -d" " -f3)
if [ -z "$HOST_IP" ]; then
    echo "ERROR: Failed to detect host IP"
    exit 1
fi

HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
echo "Host network detected as: $HOST_NETWORK"

# Set up remaining iptables rules
iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT

# Set default policies to DROP first
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# First allow established connections for already approved traffic
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Then allow only specific outbound traffic to allowed domains
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# Explicitly REJECT all other outbound traffic for immediate feedback
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

echo "Firewall configuration complete"
echo "Verifying firewall rules..."
if curl --connect-timeout 5 https://example.com >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - was able to reach https://example.com"
    exit 1
else
    echo "Firewall verification passed - unable to reach https://example.com as expected"
fi

# Verify GitHub API access
if ! curl --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - unable to reach https://api.github.com"
    exit 1
else
    echo "Firewall verification passed - able to reach https://api.github.com as expected"
fi

# Verify the AAAA filter is actually stripping IPv6 answers for a domain
# known to publish them, so a regression here fails loudly instead of
# surfacing later as a confusing ENETUNREACH/EADDRNOTAVAIL from some
# unrelated tool.
if dig +short AAAA go.dev @127.0.0.1 | grep -q .; then
    echo "ERROR: AAAA filter verification failed - go.dev still resolves an IPv6 address"
    exit 1
else
    echo "AAAA filter verification passed - go.dev resolves no IPv6 address"
fi
