## Summary

<!-- What does this change do, and why? -->

## Related issue

Closes #

## Type of change

- [ ] fix — bug fix
- [ ] feat — new feature
- [ ] docs — documentation only
- [ ] refactor — no behavior change
- [ ] perf — performance improvement
- [ ] test — adding or fixing tests
- [ ] build — build system or dependencies
- [ ] ci — CI/CD configuration
- [ ] chore — other changes that don't modify src or test files

## How was this tested?

<!-- e.g. `uv run pytest tests/test_main.py --no-cov`, manual run, etc. -->

## Checklist

- [ ] PR title follows [Conventional Commits](https://www.conventionalcommits.org/) (`type(scope): subject`, 10-50 chars)
- [ ] `make check` passes locally (lint, format, typecheck, tests ≥80% coverage, `uv audit`, `deptry`, `vulture`, `pip-licenses`)
- [ ] New/changed runtime config goes through `Settings` in `src/main.py` (no direct `os.environ` reads or hardcoded values)
- [ ] Outbound HTTP changes use the existing `tenacity` retry pattern, not ad-hoc retry loops
- [ ] Tests mock HTTP with `respx`; no real network calls
- [ ] Public functions/classes have Google-style docstrings
- [ ] `pyproject.toml` version and `uv.lock` were not hand-edited

## Additional notes

<!-- Anything reviewers should know: trade-offs, follow-ups, screenshots, etc. -->
