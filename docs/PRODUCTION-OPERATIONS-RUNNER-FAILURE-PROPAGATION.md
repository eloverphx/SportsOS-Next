# Production Operations Runner Failure Propagation

Milestone 29.7.3 repairs failure propagation in:

```text
scripts/run-production-operations.sh
```

The runner previously executed operation steps while the surrounding history pipeline used relaxed shell error handling. A child command could fail, the wrapper could still print `PASS`, and the resulting operation history could incorrectly record a successful run.

The repaired `run_step()`:

- explicitly evaluates the child command
- prints `PASS` only after a zero exit code
- prints `FAIL` with the original exit code after a failure
- returns the original child exit code

All production mode calls now use fail-fast propagation:

```text
run_step ... || exit $?
```

The existing `PIPESTATUS[0]` history capture is preserved, so the operation JSON record receives the true pipeline command result.

This repair is important because the following later observability layers depend on truthful operation exit codes:

- operations history
- reliability scorecard
- reliability alerting
- operations status snapshot
- protected operations status API
- authenticated operations dashboard
