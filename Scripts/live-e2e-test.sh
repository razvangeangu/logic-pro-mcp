#!/bin/bash
# Compatibility wrapper for the maintained Python live E2E harness.
#
# In default mode this delegates directly to the Python stateful stdio client.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
export LOGIC_PRO_MCP_BINARY="${LOGIC_PRO_MCP_BINARY:-.build/release/LogicProMCP}"

if [ "${LOGIC_PRO_MCP_STRICT_LIVE:-0}" != "1" ]; then
    exec python3 "$SCRIPT_DIR/live-e2e-test.py"
fi

command -v tmux >/dev/null 2>&1 || {
    echo "ERROR: strict live E2E requires tmux for trusted-parent stdio launch." >&2
    exit 1
}

SESSION="logic-mcp-e2e-$$"
TMPDIR="$(mktemp -d /private/tmp/logic-mcp-e2e.XXXXXX)"
REQUEST_FIFO="$TMPDIR/requests.fifo"
CAPTURE_FILE="$TMPDIR/capture.txt"
OUTPUT_FILE="$TMPDIR/output.txt"
STDERR_FILE="${LOGIC_PRO_MCP_E2E_STDERR:-$TMPDIR/stderr.txt}"
mkfifo "$REQUEST_FIFO"
: > "$CAPTURE_FILE"
PROFILE_DIR="${LOGIC_PRO_MCP_PROFILE_DIR:-$TMPDIR/profraw}"
mkdir -p "$PROFILE_DIR"
export LOGIC_PRO_MCP_PROFILE_DIR="$PROFILE_DIR"
export LLVM_PROFILE_FILE="${LLVM_PROFILE_FILE:-$PROFILE_DIR/%m-%p.profraw}"
BINARY_COMMAND="$(printf '%q' "$LOGIC_PRO_MCP_BINARY")"
STDERR_COMMAND="$(printf '%q' "$STDERR_FILE")"
PROFILE_COMMAND="$(printf '%q' "$LLVM_PROFILE_FILE")"
REQUEST_FIFO_COMMAND="$(printf '%q' "$REQUEST_FIFO")"
CAPTURE_FILE_COMMAND="$(printf '%q' "$CAPTURE_FILE")"

cleanup() {
    set +e
    tmux send-keys -t "$SESSION" C-c 2>/dev/null
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        tmux has-session -t "$SESSION" 2>/dev/null || break
        sleep 0.1
    done
    tmux kill-session -t "$SESSION" 2>/dev/null
    rm -rf "$TMPDIR"
}
trap cleanup EXIT INT TERM

tmux new-session -d -x 1000 -y 80 -s "$SESSION" -c "$ROOT_DIR" \
    "set -euo pipefail; stty -icanon -echo min 1 time 0; export LLVM_PROFILE_FILE=${PROFILE_COMMAND}; cat ${REQUEST_FIFO_COMMAND} | ${BINARY_COMMAND} 2>${STDERR_COMMAND} | tee -a ${CAPTURE_FILE_COMMAND} >/dev/null"
tmux set-option -t "$SESSION" history-limit 200000 >/dev/null 2>&1 || true

export LOGIC_PRO_MCP_E2E_TRANSPORT=external-tmux
export LOGIC_PRO_MCP_E2E_REQUEST_FIFO="$REQUEST_FIFO"
export LOGIC_PRO_MCP_E2E_CAPTURE_FILE="$CAPTURE_FILE"

set +e
PYTHONUNBUFFERED=1 python3 "$SCRIPT_DIR/live-e2e-test.py" > "$OUTPUT_FILE" 2>&1
PY_STATUS=$?
cat "$OUTPUT_FILE"
exit "$PY_STATUS"
