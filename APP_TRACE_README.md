# Cockroach Application Trace README

This README explains how to, on Ubuntu:

1. build Cockroach from **your local source branch**,
2. start a local multi-node Cockroach cluster,
3. run application trace test cases (auto-generate JSON traces),
4. run application conformance against the P model in `autokctrl/cockroach`.

---

## 0) Scope and sufficiency

For the current Cockroach application model in `autokctrl/cockroach`, the required app events are:

- `NodeInitCommand` / `NodeInitCommandReturn`
- `DecommissionCommand` / `DecommissionCommandReturn`

These events are logged from this repo's CLI path:

- `pkg/cli/init.go` (init path)
- `pkg/cli/node.go` (decommission path)
- `pkg/cli/app_trace_logger.go` (JSON trace writer)

If the model adds new app events or fields, extend logging accordingly.

---

## 1) Build Cockroach from your local source (required)

Use your modified local source. Do **not** use a public prebuilt Cockroach binary for trace-conformance work, because your trace logging lives in your local code changes.

### 1.1 Install common build dependencies

```bash
sudo apt-get update
sudo apt-get install -y \
  build-essential git curl python3 zip unzip \
  clang lld openjdk-21-jre-headless
```

### 1.2 Build from this repo

From repo root:

```bash
cd /path/to/cockroach

# Optional but recommended.
./dev doctor || true

# Build local binary from your source branch.
./dev build short

# Verify local binary exists.
./cockroach version
```

The scripts in `scripts/app_trace/` default to this local binary: `./cockroach`.

---

## 2) Start a local 5-node cluster (for trace cases)

From the Cockroach repo root:

```bash
cd /path/to/cockroach
scripts/app_trace/start_local_cluster.sh
```

Default behavior:

- auto-stops previous app-trace cluster under the same cluster dir,
- starts 5 local nodes,
- if requested ports are busy, auto-selects the next free port block,
- runs `cockroach init` once,
- writes selected host/ports to `./_app_trace_cluster/cluster.env`.

Stop cluster:

```bash
scripts/app_trace/stop_local_cluster.sh
```

---

## 3) Run single trace cases

### 3.1 Init success

```bash
scripts/app_trace/run_app_trace_case.sh init-success
```

### 3.2 Init on already initialized cluster (expected failure path)

```bash
scripts/app_trace/run_app_trace_case.sh init-already-initialized
```

### 3.3 Decommission (single node)

```bash
DECOMMISSION_NODES="5" scripts/app_trace/run_app_trace_case.sh decommission-single
```

### 3.4 Decommission (custom node set)

```bash
DECOMMISSION_NODES="4" scripts/app_trace/run_app_trace_case.sh decommission-custom
```

`run_app_trace_case.sh` auto-loads host/port from `cluster.env` when available.

---

## 4) Run the full trace suite

```bash
scripts/app_trace/run_app_trace_suite.sh
```

By default it:

1. starts local cluster,
2. runs 4 cases (`init-success`, `init-already-initialized`, `decommission node5`, `decommission node4`),
3. stops cluster.

---

## 5) Trace output directory behavior

Scripts follow this rule:

- if `traces/` exists in current working directory, write traces there,
- if it does not exist, create it automatically.

Default output files (under current working directory):

- `traces/init-success.json`
- `traces/init-already-initialized.json`
- `traces/decommission-single.json`
- `traces/decommission-custom.json`

Override output dir:

```bash
TRACE_DIR=/your/path/traces scripts/app_trace/run_app_trace_case.sh init-success
```

---

## 6) Run application conformance with P model

From `autokctrl/cockroach` (use absolute trace path):

```bash
../../P/Bld/Drops/Release/Binaries/net8.0/p compile

../../P/Bld/Drops/Release/Binaries/net8.0/p check \
  PGenerated/PChecker/net8.0/CockroachDB.dll \
  -tc AppTraceInjectEntryTest \
  --tracevalidate /ABS/PATH/TO/traces/decommission-custom.json \
  --traceinject-target CockroachAppModelTraceAdapter \
  --tracevalidate-target CockroachAppModelTraceAdapter \
  --traceguided \
  --seed 1 \
  --timeout 30 \
  --outdir PCheckerOutputAppConformance
```

---

## 7) Common environment variables

- `COCKROACH_BIN`: Cockroach executable path (default: repo-local `./cockroach`)
- `COCKROACH_HOST`: CLI target host (default: auto from `cluster.env`, else `127.0.0.1:26257`)
- `COCKROACH_INSECURE`: default `true`
- `TRACE_DIR`: output directory for traces (default: `$(pwd)/traces`)

Cluster/startup variables:

- `APP_TRACE_CLUSTER_DIR`: default `$(pwd)/_app_trace_cluster`
- `APP_TRACE_NODE_COUNT`: default `5`
- `APP_TRACE_BASE_SQL_PORT`: default `26257`
- `APP_TRACE_BASE_HTTP_PORT`: default `8081`
- `RESET_CLUSTER_DIR`: default `true`
- `AUTO_STOP_EXISTING`: default `true`
- `APP_TRACE_FORCE_PORTS`: default `false` (if `true`, fail instead of scanning)
- `APP_TRACE_PORT_SCAN_STEP`: default `50`
- `APP_TRACE_PORT_SCAN_TRIES`: default `20`

---

## 8) Troubleshooting

1. `Cockroach binary not found ...`
   - run from repo root: `./dev build short`
   - verify: `./cockroach version`

2. Port conflict on start
   - by default script auto-picks another port block
   - check selected host in `./_app_trace_cluster/cluster.env`

3. Restart issues / stale processes
   - by default `start_local_cluster.sh` auto-stops old cluster in the same dir
   - manual stop: `scripts/app_trace/stop_local_cluster.sh`

4. Trace file not generated
   - check script output for command failure
   - check write permission for current `traces/`

5. Decommission case fails
   - verify nodes are up first:
     `./cockroach node status --insecure --host="${COCKROACH_HOST:-127.0.0.1:26257}"`
