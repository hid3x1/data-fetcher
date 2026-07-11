from hypothesis import HealthCheck, settings

# mutmut re-runs the suite from a copied `mutants/` tree per mutant, which
# hypothesis' example database treats as a different "executor" than a plain
# `tests/` run and flags via HealthCheck.differing_executors — even though
# each mutant run is fully isolated. Safe to suppress here.
settings.register_profile(
    "default", suppress_health_check=[HealthCheck.differing_executors]
)
settings.load_profile("default")
