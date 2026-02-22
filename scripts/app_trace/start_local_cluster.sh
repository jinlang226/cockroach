#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DEFAULT_COCKROACH_BIN="${REPO_ROOT}/cockroach"
COCKROACH_BIN="${COCKROACH_BIN:-${DEFAULT_COCKROACH_BIN}}"

if [[ ! -x "${COCKROACH_BIN}" ]]; then
  echo "Cockroach binary not found (or not executable): ${COCKROACH_BIN}"
  echo "Build your local source binary first:"
  echo "  cd ${REPO_ROOT}"
  echo "  ./dev build short"
  echo "Then rerun this script, or set COCKROACH_BIN explicitly."
  exit 1
fi

CLUSTER_DIR="${APP_TRACE_CLUSTER_DIR:-$(pwd)/_app_trace_cluster}"
NODE_COUNT="${APP_TRACE_NODE_COUNT:-5}"
BASE_SQL_PORT="${APP_TRACE_BASE_SQL_PORT:-26257}"
BASE_HTTP_PORT="${APP_TRACE_BASE_HTTP_PORT:-8081}"
RESET_CLUSTER_DIR="${RESET_CLUSTER_DIR:-true}"
AUTO_STOP_EXISTING="${AUTO_STOP_EXISTING:-true}"
APP_TRACE_FORCE_PORTS="${APP_TRACE_FORCE_PORTS:-false}"
PORT_SCAN_STEP="${APP_TRACE_PORT_SCAN_STEP:-50}"
PORT_SCAN_TRIES="${APP_TRACE_PORT_SCAN_TRIES:-20}"

port_in_use() {
  local p="$1"
  if command -v ss >/dev/null 2>&1; then
    if ss -ltn "sport = :${p}" | awk 'NR>1 {found=1} END {exit(found ? 0 : 1)}'; then
      return 0
    fi
    return 1
  fi

  python3 - "$p" <<'PY'
import socket, sys
port = int(sys.argv[1])
with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
    s.settimeout(0.2)
    rc = s.connect_ex(("127.0.0.1", port))
sys.exit(0 if rc == 0 else 1)
PY
}

ports_available_block() {
  local sql_base="$1"
  local http_base="$2"
  local i sql_port http_port

  for ((i=0; i<NODE_COUNT; i++)); do
    sql_port=$((sql_base + i))
    http_port=$((http_base + i))
    if port_in_use "$sql_port" || port_in_use "$http_port"; then
      return 1
    fi
  done
  return 0
}

if [[ "${AUTO_STOP_EXISTING}" == "true" ]]; then
  APP_TRACE_CLUSTER_DIR="${CLUSTER_DIR}" "${SCRIPT_DIR}/stop_local_cluster.sh" >/dev/null 2>&1 || true
fi

if [[ "${RESET_CLUSTER_DIR}" == "true" ]]; then
  rm -rf "${CLUSTER_DIR}"
fi
mkdir -p "${CLUSTER_DIR}"

if ! ports_available_block "${BASE_SQL_PORT}" "${BASE_HTTP_PORT}"; then
  if [[ "${APP_TRACE_FORCE_PORTS}" == "true" ]]; then
    echo "Requested ports are busy and APP_TRACE_FORCE_PORTS=true."
    echo "Either free the ports or set different APP_TRACE_BASE_SQL_PORT / APP_TRACE_BASE_HTTP_PORT."
    exit 1
  fi

  found="false"
  for ((t=0; t<PORT_SCAN_TRIES; t++)); do
    BASE_SQL_PORT=$((BASE_SQL_PORT + PORT_SCAN_STEP))
    BASE_HTTP_PORT=$((BASE_HTTP_PORT + PORT_SCAN_STEP))
    if ports_available_block "${BASE_SQL_PORT}" "${BASE_HTTP_PORT}"; then
      found="true"
      break
    fi
  done

  if [[ "${found}" != "true" ]]; then
    echo "Failed to find a free port block after ${PORT_SCAN_TRIES} attempts."
    echo "Try increasing APP_TRACE_PORT_SCAN_TRIES or APP_TRACE_PORT_SCAN_STEP."
    exit 1
  fi

  echo "Requested ports were busy. Switched to free port block:"
  echo "  SQL base port : ${BASE_SQL_PORT}"
  echo "  HTTP base port: ${BASE_HTTP_PORT}"
fi

join_addrs=""
for ((i=0; i<NODE_COUNT; i++)); do
  sql_port=$((BASE_SQL_PORT + i))
  addr="127.0.0.1:${sql_port}"
  if [[ -z "${join_addrs}" ]]; then
    join_addrs="${addr}"
  else
    join_addrs="${join_addrs},${addr}"
  fi
done

started_any="false"
cleanup_on_error() {
  if [[ "${started_any}" == "true" ]]; then
    APP_TRACE_CLUSTER_DIR="${CLUSTER_DIR}" "${SCRIPT_DIR}/stop_local_cluster.sh" >/dev/null 2>&1 || true
  fi
}
trap cleanup_on_error ERR

echo "Starting ${NODE_COUNT} Cockroach nodes in ${CLUSTER_DIR}"
for ((i=0; i<NODE_COUNT; i++)); do
  node_idx=$((i + 1))
  sql_port=$((BASE_SQL_PORT + i))
  http_port=$((BASE_HTTP_PORT + i))
  node_dir="${CLUSTER_DIR}/node${node_idx}"
  mkdir -p "${node_dir}"

  "${COCKROACH_BIN}" start \
    --insecure \
    --store="${node_dir}" \
    --listen-addr="127.0.0.1:${sql_port}" \
    --advertise-addr="127.0.0.1:${sql_port}" \
    --http-addr="127.0.0.1:${http_port}" \
    --join="${join_addrs}" \
    --background \
    --pid-file="${node_dir}/cockroach.pid"

  started_any="true"
done

sleep 3

set +e
"${COCKROACH_BIN}" init --insecure --host="127.0.0.1:${BASE_SQL_PORT}"
init_rc=$?
set -e

if [[ ${init_rc} -ne 0 ]]; then
  echo "init returned non-zero (cluster may already be initialized); continuing"
fi

CLUSTER_ENV="${CLUSTER_DIR}/cluster.env"
cat > "${CLUSTER_ENV}" <<ENV
export APP_TRACE_CLUSTER_DIR="${CLUSTER_DIR}"
export COCKROACH_HOST="127.0.0.1:${BASE_SQL_PORT}"
export APP_TRACE_BASE_SQL_PORT="${BASE_SQL_PORT}"
export APP_TRACE_BASE_HTTP_PORT="${BASE_HTTP_PORT}"
ENV

trap - ERR

echo "Cluster is up."
echo "SQL endpoint: 127.0.0.1:${BASE_SQL_PORT}"
echo "Cluster metadata: ${CLUSTER_ENV}"
echo "To stop cluster: scripts/app_trace/stop_local_cluster.sh"
