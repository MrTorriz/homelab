#!/usr/bin/env bash
# security-check.sh — Aggregated read-only security/health check.
# Exit codes: 0=OK, 1=warnings, 2=critical. Detailed log + digest line per run.
# Requires: ${LOG_DIR} (defaults to $HOME/logs/security); pairs with security-check.lib.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib.sh
. "${SCRIPT_DIR}/../lib.sh"
# shellcheck source=./security-check.lib.sh
. "${SCRIPT_DIR}/security-check.lib.sh"

# --- Paths ---
LOG_DIR="${LOG_DIR:-$HOME/logs/security}"
BASELINE_DIR="${BASELINE_DIR:-${LOG_DIR}/baseline}"
DIGEST_FILE="${DIGEST_FILE:-$HOME/logs/security_check_digest.log}"
TIMESTAMP_HUMAN="$(date '+%Y-%m-%d %H:%M')"
TIMESTAMP_FILE="$(date '+%Y-%m-%d_%H%M')"
DEFAULT_LOG_FILE="${LOG_DIR}/${TIMESTAMP_FILE}_security.log"

# --- Tempdir with cleanup-trap ---
WORKDIR="$(mktemp -d -t security_check.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

# --- Available checks (defined in security-check.lib.sh) ---
ALL_CHECKS=(
  firewall
  fail2ban
  vpn
  listening_ports
  docker
  suid
  updates
  rootkit
  chkrootkit
  debsums
  auditd
  failed_units
  users
  ssh_keys
  kernel_modules
)

# Per-check timeout (seconds). Default 30.
declare -A CHECK_TIMEOUT=(
  [rootkit]=300
  [chkrootkit]=180
  [debsums]=120
  [suid]=60
)

# --- Flags / arguments ---
ONLY_LIST=""
SKIP_LIST=""
UPDATE_BASELINE=0
QUIET=0
LOG_FILE="$DEFAULT_LOG_FILE"

# --- Counters and results ---
COUNT_OK=0
COUNT_INFO=0
COUNT_WARN=0
COUNT_CRIT=0
RESULTS=()   # format: "SEV|module|message"

usage() {
  cat <<EOF
security-check.sh — aggregated security check

Usage:
  security-check.sh [flags]

Flags:
  --only M1,M2,...      Run only the listed modules
  --skip M1,M2,...      Skip the listed modules
  --update-baseline     Refresh baseline files, skip diff checks
  --quiet               Print only [CRIT] to stdout
  --log-file PATH       Write detail log to alternative path
  --help                Show this help

Available modules:
  ${ALL_CHECKS[*]}

Examples:
  security-check.sh --only firewall,vpn
  security-check.sh --skip rootkit,chkrootkit
  security-check.sh --update-baseline
EOF
}

die() {
  echo "security-check: $*" >&2
  exit 2
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --only)
        [[ $# -lt 2 ]] && die "--only requires an argument"
        ONLY_LIST="$2"
        shift 2
        ;;
      --skip)
        [[ $# -lt 2 ]] && die "--skip requires an argument"
        SKIP_LIST="$2"
        shift 2
        ;;
      --update-baseline)
        UPDATE_BASELINE=1
        shift
        ;;
      --quiet)
        QUIET=1
        shift
        ;;
      --log-file)
        [[ $# -lt 2 ]] && die "--log-file requires an argument"
        LOG_FILE="$2"
        shift 2
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        die "unknown argument: $1 (see --help)"
        ;;
    esac
  done
}

validate_module_list() {
  local list="$1" name kind="$2"
  [[ -z "$list" ]] && return 0
  IFS=',' read -ra arr <<< "$list"
  for name in "${arr[@]}"; do
    if ! declare -F "check_${name}" >/dev/null; then
      echo "security-check: unknown module in --${kind}: ${name}" >&2
      echo "Available: ${ALL_CHECKS[*]}" >&2
      exit 2
    fi
  done
}

in_csv() {
  local needle="$1" csv="$2"
  [[ -z "$csv" ]] && return 1
  [[ ",${csv}," == *",${needle},"* ]]
}

should_run_check() {
  local name="$1"
  if [[ -n "$ONLY_LIST" ]]; then
    in_csv "$name" "$ONLY_LIST" || return 1
  fi
  if [[ -n "$SKIP_LIST" ]]; then
    in_csv "$name" "$SKIP_LIST" && return 1
  fi
  return 0
}

# log SEVERITY MODULE MESSAGE — buffer result, update counters.
log() {
  local sev="$1" modul="$2"
  shift 2
  local msg="$*"
  RESULTS+=("${sev}|${modul}|${msg}")
  case "$sev" in
    OK)   COUNT_OK=$((COUNT_OK + 1)) ;;
    INFO) COUNT_INFO=$((COUNT_INFO + 1)) ;;
    WARN) COUNT_WARN=$((COUNT_WARN + 1)) ;;
    CRIT) COUNT_CRIT=$((COUNT_CRIT + 1)) ;;
  esac
}

sev_glyph() {
  case "$1" in
    OK)   printf '+' ;;
    INFO) printf 'i' ;;
    WARN) printf '!' ;;
    CRIT) printf 'X' ;;
    *)    printf '?' ;;
  esac
}

# run_check MODULE — fork the lib in worker mode with a timeout.
run_check() {
  local name="$1"
  local timeout_s="${CHECK_TIMEOUT[$name]:-30}"
  local results_file="$WORKDIR/results.$name"
  local stderr_file="$WORKDIR/stderr.$name"
  local rc=0

  : > "$results_file"
  : > "$stderr_file"

  TMPDIR="$WORKDIR" \
  BASELINE_DIR="$BASELINE_DIR" \
  RESULTS_FILE="$results_file" \
  UPDATE_BASELINE="$UPDATE_BASELINE" \
  timeout --signal=TERM --kill-after=5 "${timeout_s}s" \
    bash "${SCRIPT_DIR}/security-check.lib.sh" run "$name" \
    >>"$stderr_file" 2>&1 || rc=$?

  if [[ -s "$results_file" ]]; then
    local sev modul msg
    while IFS='|' read -r sev modul msg; do
      [[ -z "${sev:-}" ]] && continue
      log "$sev" "$modul" "$msg"
    done < "$results_file"
  fi

  if [[ $rc -ne 0 ]]; then
    if [[ $rc -eq 124 ]]; then
      log WARN "$name" "check timed out after ${timeout_s}s"
    else
      local errtail=""
      [[ -s "$stderr_file" ]] && \
        errtail=" ($(tail -1 "$stderr_file" 2>/dev/null | head -c 200))"
      log WARN "$name" "check exited with code=${rc}${errtail}"
    fi
  fi
}

write_detail_log() {
  local line sev modul msg
  {
    printf '=== Security check %s ===\n' "$TIMESTAMP_HUMAN"
    printf 'Host: %s  Kernel: %s\n' "$(hostname)" "$(uname -r)"
    if [[ "$UPDATE_BASELINE" -eq 1 ]]; then
      printf 'Mode: --update-baseline (diff checks skipped)\n'
    fi
    printf '\n'
    for line in "${RESULTS[@]}"; do
      IFS='|' read -r sev modul msg <<< "$line"
      printf '[%s] [%-4s] %-16s — %s\n' "$TIMESTAMP_HUMAN" "$sev" "$modul" "$msg"
    done
    printf '\nSummary: %d OK, %d INFO, %d WARN, %d CRIT\n' \
      "$COUNT_OK" "$COUNT_INFO" "$COUNT_WARN" "$COUNT_CRIT"
  } >> "$LOG_FILE"
}

write_digest() {
  local digest_basename
  digest_basename="$(basename "$LOG_FILE")"

  if [[ "$UPDATE_BASELINE" -eq 1 ]]; then
    printf '[%s] i baseline updated — see %s/\n' \
      "$TIMESTAMP_HUMAN" "$BASELINE_DIR" \
      >> "$DIGEST_FILE"
  elif [[ "$COUNT_CRIT" -eq 0 && "$COUNT_WARN" -eq 0 ]]; then
    printf '[%s] OK — %d/%d checks passed\n' \
      "$TIMESTAMP_HUMAN" \
      "$COUNT_OK" \
      "$((COUNT_OK + COUNT_INFO + COUNT_WARN + COUNT_CRIT))" \
      >> "$DIGEST_FILE"
  else
    {
      printf '[%s] FAIL (%d crit, %d warn) — see security/%s\n' \
        "$TIMESTAMP_HUMAN" "$COUNT_CRIT" "$COUNT_WARN" "$digest_basename"
      local line sev modul msg glyph
      for line in "${RESULTS[@]}"; do
        IFS='|' read -r sev modul msg <<< "$line"
        [[ "$sev" == "OK" || "$sev" == "INFO" ]] && continue
        glyph="$(sev_glyph "$sev")"
        printf '              -> %s %s: %s\n' "$glyph" "$modul" "$msg"
      done
    } >> "$DIGEST_FILE"
  fi

  log_rotate "$DIGEST_FILE" 500
}

write_stdout() {
  local line sev modul msg
  for line in "${RESULTS[@]}"; do
    IFS='|' read -r sev modul msg <<< "$line"
    if [[ "$QUIET" -eq 1 ]]; then
      [[ "$sev" == "CRIT" ]] || continue
    fi
    printf '[%-4s] %-16s — %s\n' "$sev" "$modul" "$msg"
  done
  if [[ "$QUIET" -eq 0 ]]; then
    printf 'Summary: %d OK, %d INFO, %d WARN, %d CRIT\n' \
      "$COUNT_OK" "$COUNT_INFO" "$COUNT_WARN" "$COUNT_CRIT"
    printf 'Detail log: %s\n' "$LOG_FILE"
  fi
}

compute_exit_code() {
  if [[ "$COUNT_CRIT" -gt 0 ]]; then
    echo 2
  elif [[ "$COUNT_WARN" -gt 0 ]]; then
    echo 1
  else
    echo 0
  fi
}

do_update_baseline() {
  mkdir -p "$BASELINE_DIR"

  baseline_snapshot_suid             > "$BASELINE_DIR/suid.list"
  baseline_snapshot_listening_ports  > "$BASELINE_DIR/listening_ports.list"
  baseline_snapshot_containers       > "$BASELINE_DIR/containers.list"
  baseline_snapshot_users            > "$BASELINE_DIR/users.list"
  baseline_snapshot_kernel_modules   > "$BASELINE_DIR/kernel_modules.list"
  baseline_snapshot_ssh_keys         > "$BASELINE_DIR/ssh_keys.list"

  {
    printf 'hostname=%s\n' "$(hostname)"
    printf 'kernel=%s\n'   "$(uname -r)"
    printf 'created=%s\n'  "$(date -Iseconds)"
    printf 'user=%s\n'     "${USER:-$(id -un)}"
  } > "$BASELINE_DIR/baseline.meta"

  log INFO baseline "new baseline written to ${BASELINE_DIR}"
}

main() {
  parse_args "$@"
  validate_module_list "$ONLY_LIST" "only"
  validate_module_list "$SKIP_LIST" "skip"

  mkdir -p "$LOG_DIR" "$BASELINE_DIR"

  if [[ "$UPDATE_BASELINE" -eq 1 ]]; then
    do_update_baseline
  else
    local name
    for name in "${ALL_CHECKS[@]}"; do
      should_run_check "$name" || continue
      run_check "$name"
    done
  fi

  write_detail_log
  write_digest
  write_stdout

  exit "$(compute_exit_code)"
}

main "$@"
