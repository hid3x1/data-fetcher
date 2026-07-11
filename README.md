# data-fetcher

A small command-line tool that fetches posts from a public API
([jsonplaceholder](https://jsonplaceholder.typicode.com)), retrying
automatically on transient failures, and prints the results to your
terminal.

## Requirements

- Python 3.14 or newer
- [uv](https://docs.astral.sh/uv/) for dependency management

## Installation

```bash
uv sync
```

## Usage

```bash
uv run python src/main.py
```

By default, this fetches the 5 most recent posts from
`https://jsonplaceholder.typicode.com` and logs them to the console.

## Configuration

Configuration is provided via environment variables prefixed with
`DATA_FETCHER_`:

| Variable                       | Default                                  | Description                          |
| ------------------------------- | ----------------------------------------- | ------------------------------------- |
| `DATA_FETCHER_BASE_URL`         | `https://jsonplaceholder.typicode.com`    | Base URL of the API to fetch from     |
| `DATA_FETCHER_TIMEOUT_SECONDS`  | `10.0`                                    | Request timeout, in seconds           |
| `DATA_FETCHER_FETCH_LIMIT`      | `5`                                       | Number of posts to fetch (must be > 0)|

Example:

```bash
DATA_FETCHER_FETCH_LIMIT=10 uv run src/main.py
```

## Contributing

See [AGENTS.md](AGENTS.md) for development setup, commands, and
contribution guidelines.
