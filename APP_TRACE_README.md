# Cockroach Application Trace README

This README explains how to, on Ubuntu:

1. install CockroachDB CLI/binary,
2. start a local multi-node Cockroach cluster,
3. run application trace test cases (auto-generate JSON traces),
4. run application conformance against the P model in `autokctrl/cockroach`.

---

## 0) Are these logs sufficient for model trace validation?

Yes, for the current Cockroach application model in `autokctrl/cockroach`.

Current app-model events required:

- `NodeInitCommand` / `NodeInitCommandReturn`
- `DecommissionCommand` / `DecommissionCommandReturn`

These events are now logged in this repo at:

- `pkg/cli/init.go` (init path)
- `pkg/cli/node.go` (decommission path)
- `pkg/cli/app_trace_logger.go` (JSON trace writer)

If the model adds new app events/fields later, logging must be extended accordingly.

---

## 1) Install CockroachDB on Ubuntu (binary)

Example for `v25.4.3`:

```bash
sudo apt-get update
sudo apt-get install -y curl tar

cd /tmp
curl -LO https://binaries.cockroachdb.com/cockroach-v25.4.3.linux-amd64.tgz
tar -xzf cockroach-v25.4.3.linux-amd64.tgz
sudo cp -i cockroach-v25.4.3.linux-amd64/cockroach /usr/local/bin/

cockroach version
```

---

## 2) Start a local 5-node cluster (for trace cases)

From the Cockroach repo root:

```bash
cd /path/to/cockroach
scripts/app_trace/start_local_cluster.sh
```

Default behavior:

- starts 5 local nodes on `127.0.0.1:26257..26261`
- uses local data dir `./_app_trace_cluster`
- runs `cockroach init` once

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

- `COCKROACH_BIN`: Cockroach executable path (default: `cockroach`)
- `COCKROACH_HOST`: CLI target host (default: `127.0.0.1:26257`)
- `COCKROACH_INSECURE`: default `true`
- `TRACE_DIR`: output directory for traces (default: `$(pwd)/traces`)

Local cluster script vars:

- `APP_TRACE_CLUSTER_DIR`: default `$(pwd)/_app_trace_cluster`
- `APP_TRACE_NODE_COUNT`: default `5`
- `APP_TRACE_BASE_SQL_PORT`: default `26257`
- `APP_TRACE_BASE_HTTP_PORT`: default `8081`
- `RESET_CLUSTER_DIR`: default `true`

---

## 8) Troubleshooting

1. `cockroach: command not found`
   - check `cockroach version`
   - make sure `/usr/local/bin` is in PATH

2. Port conflict
   - stop existing Cockroach processes, or change `APP_TRACE_BASE_SQL_PORT`

3. Trace file not generated
   - check script stderr/stdout for command failure
   - check write permission for current `traces/`

4. Decommission case fails
   - verify 5-node cluster is up first
   - run: `cockroach node status --insecure --host=127.0.0.1:26257`
