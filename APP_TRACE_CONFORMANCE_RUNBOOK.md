# Cockroach App Trace Logging for P Conformance

This repo now emits app-management trace JSON events for:

- `NodeInitCommand` / `NodeInitCommandReturn` (`cockroach init`)
- `DecommissionCommand` / `DecommissionCommandReturn` (`cockroach node decommission`)

## 1) Enable app trace output

Set environment variables before running CLI commands:

```bash
export COCKROACH_APP_TRACE_ENABLED=true
export COCKROACH_APP_TRACE_PATH="$PWD/traces/decommission-correct.json"
mkdir -p "$(dirname "$COCKROACH_APP_TRACE_PATH")"
rm -f "$COCKROACH_APP_TRACE_PATH"
```

Optional (if you want deterministic IDs):

```bash
export COCKROACH_APP_RECONCILE_ID="default/cockroachdb#31"
export COCKROACH_APP_TRACE_ID="default/cockroachdb-<your-id>"
```

If not set, IDs are auto-generated per command run.

## 2) Generate trace events

Example commands (adjust host/certs):

```bash
# init path
cockroach init --insecure --host=127.0.0.1:26257

# decommission path
cockroach node decommission 4 5 --insecure --host=127.0.0.1:26257 --wait=all
```

Each command appends events to `COCKROACH_APP_TRACE_PATH` in this format:

```json
{ "events": [ ... ] }
```

## 3) Validate with P app conformance

From `autokctrl/cockroach`:

```bash
../../P/Bld/Drops/Release/Binaries/net8.0/p check \
  PGenerated/PChecker/net8.0/CockroachDB.dll \
  -tc AppTraceInjectEntryTest \
  --tracevalidate /ABS/PATH/TO/decommission-correct.json \
  --traceinject-target CockroachAppModelTraceAdapter \
  --tracevalidate-target CockroachAppModelTraceAdapter \
  --traceguided \
  --seed 1 \
  --timeout 30 \
  --outdir PCheckerOutputAppConformance
```

## Notes

- `decomission-correct` style traces should include both decommission phases:
  - `start_drain`
  - `mark_decommissioned`
- The P app adapter is strict: result events must have a matching prior command in the same `(reconcileId, traceId)` context.
