"""Known false positives for vulture (dynamically used attributes, e.g. Pydantic model fields).

Regenerate with: uv run vulture --make-whitelist src tests > vulture_whitelist.py
"""

# ruff: noqa: B018, F821

body  # unused variable (src/main.py:33)
