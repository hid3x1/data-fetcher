# data-fetcher

## 1. Project Overview & Stack

Small Python app that fetches posts from a public API (jsonplaceholder) with
retries, structured logging, and typed settings.

- Language: Python >=3.14
- Package manager: `uv`
- Runtime deps: `httpx` 0.28+, `loguru` 0.7+, `pydantic` 2.13+,
  `pydantic-settings` 2.14+, `tenacity` 9.1+
- Dev tools: `ruff` 0.15+ (lint/format), `ty` 0.0.57+ (types), `pytest` 9.1+
  (+ `pytest-cov`, `pytest-xdist`, `pytest-randomly`, `pytest-mock`, `respx`),
  `deptry` (unused/missing deps), `vulture` (dead code), `mutmut` 3.6+
  (mutation testing), `pip-licenses` (OSS license compatibility), `prek`
  (git hooks), `python-semantic-release` (versioning)

## 2. Setup / Build / Test / Lint

```bash
uv sync                                   # install all deps (incl. dev group)
uv run python src/main.py                 # run the app (no separate build step)

# Lint / format / typecheck — prefer file scope over whole-repo
uv run ruff check src/main.py             # lint one file
uv run ruff format src/main.py            # format one file
uv run ty check src                       # typecheck (ty only supports dir-level)

# Tests — prefer file/test scope over the full suite
uv run pytest tests/test_main.py --no-cov
uv run pytest tests/test_main.py::TestFetchPosts::test_returns_parsed_posts_on_success --no-cov

make pip-licenses                         # verify dependency OSS license compatibility
make mutation                             # mutation testing (mutmut) — slow, run on demand, not in `make check`

make check                                # full CI gate: lint+format+typecheck+test+audit+deptry+deadcode+licenses
make help                                 # list all Makefile targets
```

## 3. Project-Specific Conventions

- `ruff` runs with `lint.select = ["ALL"]` (see `pyproject.toml`) — write
  Google-style docstrings on public functions/classes; `tests/**` is exempt
  from `ANN`/`D`/`S101`/`SLF001`.
- All runtime config MUST go through `Settings(BaseSettings)` in
  `src/main.py`, prefixed `DATA_FETCHER_` (e.g. `DATA_FETCHER_BASE_URL`).
  Do NOT read `os.environ` directly or hardcode config values.
- Outbound HTTP calls MUST use the existing `tenacity`-retry pattern (see
  `_request_posts`), not ad-hoc `try`/`except` retry loops.
- Do NOT hand-edit the `version` field in `pyproject.toml` —
  `python-semantic-release` derives it from Conventional Commit history.
- Tests MUST mock HTTP with `respx` (`@respx.mock`) — no real network calls
  in tests, since `pytest-xdist`/`pytest-randomly` run tests in parallel and
  out of order, so tests must not share mutable state.
- Keep `src/main.py` fully type-hinted (`from __future__ import annotations`
  style); `ty check` treats missing/incorrect types as errors.

## 4. Git / PR Workflow & Definition of Done

- Commit messages MUST follow Conventional Commits, title length 10-50 chars
  (enforced by `gitlint` via the `prek` commit-msg hook).
- Direct pushes to `main` are blocked by a pre-push hook — work on a branch
  and open a PR.
- Before opening/updating a PR, run `make check` locally and treat it as the
  definition of done (lint, format, typecheck, tests at >=80% coverage,
  `uv audit`, `deptry`, `vulture`, `pip-licenses` must all pass).
- Git hooks are installed automatically by the devcontainer
  (`postStartCommand`); run `make hooks-install` manually if needed, and
  `make hooks-run` to run all hooks against all files.

## 5. Boundaries & Safety

- Do NOT edit `CLAUDE.md` directly — it is a symlink to `AGENTS.md`; edit
  `AGENTS.md`.
- Do NOT hand-edit `uv.lock` — let `uv sync` / `uv lock` (or the `uv-lock`
  pre-commit hook) regenerate it.
- Do NOT force-push, rewrite history, or bypass hooks (`--no-verify`) on any
  shared branch.
- Confirm with the user before: adding/upgrading dependencies in
  `pyproject.toml` (`make upgrade`), running `make firewall-refresh` (needs
  `sudo`, changes devcontainer network rules), or running `make clean` on a
  dirty tree.
- If a convention isn't covered here or in the code, ask rather than
  guessing.

## 6. Further Reading

- `make help` / `Makefile` — full list of available commands
- `prek.toml` — full git hook configuration (pre-commit/pre-push/commit-msg)
- `pyproject.toml` `[tool.ruff]` — full lint rule selection and ignores
- `pyproject.toml` `[tool.semantic_release]` — versioning/release config
