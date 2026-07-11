FROM mcr.microsoft.com/devcontainers/base:ubuntu26.04

ARG USERNAME=vscode
ARG CLAUDE_CODE_VERSION=latest

RUN apt-get update && apt-get install -y --no-install-recommends \
    iptables \
    ipset \
    iproute2 \
    dnsutils \
    aggregate \
    curl \
    jq \
    nano \
    vim \
    dnsmasq \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Set `DEVCONTAINER` environment variable to help with orientation
ENV DEVCONTAINER=true

USER vscode

# Install Claude
RUN if [ "$CLAUDE_CODE_VERSION" = "latest" ]; then \
    curl -fsSL https://claude.ai/install.sh | bash; \
    else \
    curl -fsSL https://claude.ai/install.sh | sh -s "$CLAUDE_CODE_VERSION" ; \
    fi
ENV PNPM_HOME="/home/vscode/.local/share/pnpm"
ENV PATH="/home/vscode/.local/bin:/home/vscode/.claude/bin:${PNPM_HOME}:${PATH}"

# Copy and set up firewall script
USER root
COPY init-firewall.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/init-firewall.sh && \
    echo "vscode ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/vscode-firewall && \
    chmod 0440 /etc/sudoers.d/vscode-firewall && \
    mkdir -p /home/vscode/.claude && \
    chown vscode:vscode /home/vscode/.claude

USER vscode
