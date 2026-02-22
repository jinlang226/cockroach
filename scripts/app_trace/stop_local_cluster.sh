#!/usr/bin/env bash
set -euo pipefail

CLUSTER_DIR="${APP_TRACE_CLUSTER_DIR:-$(pwd)/_app_trace_cluster}"

if [[ ! -d "${CLUSTER_DIR}" ]]; then
  echo "Cluster directory not found: ${CLUSTER_DIR}"
  exit 0
fi

echo "Stopping Cockroach nodes from ${CLUSTER_DIR}"
shopt -s nullglob
for pid_file in "${CLUSTER_DIR}"/node*/cockroach.pid; do
  if [[ -f "${pid_file}" ]]; then
    pid="$(cat "${pid_file}")"
    if kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}" || true
      echo "Stopped PID ${pid}"
    fi
  fi
done
shopt -u nullglob

sleep 1

# Best-effort cleanup of lingering processes started from this cluster dir.
pkill -f "${CLUSTER_DIR}" || true

echo "Done."
