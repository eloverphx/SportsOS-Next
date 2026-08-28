# Milestone 29.10.1 Runner Function Order Repair

Milestone 29.10 added the `observability-refresh` dispatcher mode.

The initial patch exposed an ordering defect where the runner could reach the case dispatcher before the `run_step()` function definition had been executed by Bash.

Observed failure:

```text
run-production-operations.sh: line 38: run_step: command not found
```

29.10.1 moves the existing `run_step()` definition before the case dispatcher.

It preserves:

- Milestone 29.7.3 child exit-code propagation
- `PIPESTATUS[0]` operation-history handling
- the `observability-refresh` mode
- the daily observability refresh integration

No production operation semantics are changed beyond correcting Bash function availability.
