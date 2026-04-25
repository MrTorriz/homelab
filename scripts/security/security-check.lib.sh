#!/usr/bin/env bash
# security-check.lib.sh — Check functions for security-check.sh.
# Sourced as a library OR run as a worker: bash security-check.lib.sh run <module>
# Worker expects: TMPDIR, BASELINE_DIR, RESULTS_FILE, UPDATE_BASELINE.

# log SEV MODULE MESSAGE
# In library mode, log() is provided by the parent. In worker mode we write
# directly to RESULTS_FILE (one "SEV|module|message" line per call).
_lib_log_worker() {
  local sev="$1" modul="$2"
  shift 2
  printf '%s|%s|%s\n' "$sev" "$modul" "$*" >> "$RESULTS_FILE"
}

baseline_file() {
  echo "${BASELINE_DIR}/$1"
}

# diff_against_baseline NAME MODULE < <(current_cmd)
# Reports added rows as WARN, removed rows as INFO.
diff_against_baseline() {
  local base_name="$1" modul="$2"
  local base="${BASELINE_DIR}/${base_name}"
  local current="${TMPDIR}/current.${base_name}"

  sort > "$current"

  if [[ ! -f "$base" ]]; then
    log INFO "$modul" "no baseline (${base_name}) — run --update-baseline to create"
    return 0
  fi

  local added removed
  added="$(comm -13 "$base" "$current" || true)"
  removed="$(comm -23 "$base" "$current" || true)"

  if [[ -n "$added" ]]; then
    local n
    n=$(printf '%s\n' "$added" | grep -c .)
    local first
    first="$(printf '%s' "$added" | head -3 | tr '\n' ';' | sed 's/;$//')"
    log WARN "$modul" "${n} new rows in ${base_name} [${first}]"
  fi
  if [[ -n "$removed" ]]; then
    local n
    n=$(printf '%s\n' "$removed" | grep -c .)
    local first
    first="$(printf '%s' "$removed" | head -3 | tr '\n' ';' | sed 's/;$//')"
    log INFO "$modul" "${n} rows removed from ${base_name} [${first}]"
  fi
  [[ -z "$added" && -z "$removed" ]] && return 0
}

# --- Baseline snapshot generators (called by parent on --update-baseline) ---

baseline_snapshot_suid() {
  find / -xdev -perm -4000 -type f 2>/dev/null | sort
}

baseline_snapshot_listening_ports() {
  ss -tulnH 2>/dev/null | awk '{print $1" "$5}' | sort -u
}

baseline_snapshot_containers() {
  docker ps --format '{{.Names}}' 2>/dev/null | sort -u
}

baseline_snapshot_users() {
  awk -F: '$3 >= 1000 || $3 == 0 {print $1":"$3":"$7}' /etc/passwd | sort
}

baseline_snapshot_kernel_modules() {
  lsmod 2>/dev/null | awk 'NR>1 {print $1}' | sort -u
}

baseline_snapshot_ssh_keys() {
  # Hash each authorized_keys line so we detect changes without logging keys
  local f
  for f in /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys; do
    [[ -f "$f" ]] || continue
    while IFS= read -r line; do
      [[ -z "$line" || "$line" == \#* ]] && continue
      printf '%s %s\n' "$f" "$(printf '%s' "$line" | sha256sum | awk '{print $1}')"
    done < "$f" 2>/dev/null
  done | sort -u
}

# --- Checks ---

check_firewall() {
  if ! command -v ufw >/dev/null 2>&1; then
    log CRIT firewall "ufw binary missing"
    return
  fi

  local status
  status="$(sudo -n ufw status verbose 2>/dev/null || ufw status verbose 2>/dev/null || true)"
  if [[ -z "$status" ]]; then
    log WARN firewall "could not read ufw status (needs passwordless sudo)"
    return
  fi

  if ! grep -qE '^Status: active' <<<"$status"; then
    log CRIT firewall "ufw is NOT active"
    return
  fi

  if ! grep -qE 'Default:.*deny \(incoming\)' <<<"$status"; then
    log CRIT firewall "default incoming is not deny"
    return
  fi

  local rule_count
  rule_count="$(grep -cE '(ALLOW|DENY|REJECT|LIMIT) (IN|OUT|FWD)' <<<"$status" || true)"
  [[ -z "$rule_count" ]] && rule_count=0

  log OK firewall "ufw active, default deny in, ${rule_count} rules"
}

check_fail2ban() {
  if ! command -v fail2ban-client >/dev/null 2>&1; then
    log WARN fail2ban "fail2ban-client missing"
    return
  fi

  if ! systemctl is-active --quiet fail2ban 2>/dev/null; then
    log CRIT fail2ban "service is not active"
    return
  fi

  local out jails jail_count banned_total=0 banned jail
  out="$(sudo -n fail2ban-client status 2>/dev/null || fail2ban-client status 2>/dev/null || true)"
  if [[ -z "$out" ]]; then
    log WARN fail2ban "could not read status (needs sudo)"
    return
  fi

  jails="$(sed -n 's/.*Jail list:[[:space:]]*//p' <<<"$out" | tr ',' '\n' | awk 'NF{$1=$1;print}')"
  jail_count=0
  if [[ -n "$jails" ]]; then
    while IFS= read -r jail; do
      [[ -z "$jail" ]] && continue
      jail_count=$((jail_count + 1))
      banned="$(sudo -n fail2ban-client status "$jail" 2>/dev/null \
                | sed -n 's/.*Currently banned:[[:space:]]*//p' | head -1 || true)"
      [[ -z "$banned" ]] && banned=0
      banned_total=$((banned_total + banned))
    done <<< "$jails"
  fi

  if [[ "$jail_count" -eq 0 ]]; then
    log WARN fail2ban "no jails configured"
    return
  fi

  log OK fail2ban "active, ${jail_count} jail(s), ${banned_total} active bans"
}

check_vpn() {
  # Interface
  if ! ip -4 addr show wg0-mullvad >/dev/null 2>&1; then
    log CRIT vpn "wg0-mullvad missing/down"
    return
  fi

  # Mullvad client
  local status
  if command -v mullvad >/dev/null 2>&1; then
    status="$(mullvad status 2>/dev/null || true)"
    if [[ -z "$status" ]] || ! grep -qiE 'Connected' <<<"$status"; then
      log CRIT vpn "mullvad status not Connected: ${status:-empty}"
      return
    fi

    local lockdown
    lockdown="$(mullvad lockdown-mode get 2>/dev/null || true)"
    if ! grep -qi 'on' <<<"$lockdown"; then
      log CRIT vpn "killswitch (lockdown-mode) not on: ${lockdown:-empty}"
      return
    fi
  else
    log WARN vpn "mullvad client missing, cannot verify status/killswitch"
  fi

  # Exit-IP via Mullvad API
  local exit_json exit_ip is_mullvad
  exit_json="$(curl -sf --max-time 8 https://am.i.mullvad.net/json 2>/dev/null || true)"
  if [[ -n "$exit_json" ]]; then
    exit_ip="$(sed -n 's/.*"ip"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' <<<"$exit_json" | head -1)"
    is_mullvad="$(sed -n 's/.*"mullvad_exit_ip"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' <<<"$exit_json" | head -1)"
    if [[ "$is_mullvad" == "true" ]]; then
      log OK vpn "mullvad connected via ${exit_ip:-?} (killswitch on)"
    else
      log CRIT vpn "traffic NOT going via mullvad (exit-ip ${exit_ip:-?})"
    fi
  else
    log WARN vpn "could not reach am.i.mullvad.net for exit-IP verification"
  fi
}

check_listening_ports() {
  [[ "$UPDATE_BASELINE" == "1" ]] && return
  local current
  current="$(ss -tulnH 2>/dev/null | awk '{print $1" "$5}' | sort -u)"
  if [[ -z "$current" ]]; then
    log WARN listening_ports "ss returned empty"
    return
  fi
  diff_against_baseline listening_ports.list listening_ports <<<"$current"
  local n
  n="$(grep -c . <<<"$current" || true)"
  log OK listening_ports "${n:-0} listening sockets"
}

check_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    log WARN docker "docker binary missing"
    return
  fi

  # Socket permissions
  local perm
  perm="$(stat -c %a /var/run/docker.sock 2>/dev/null || echo "")"
  if [[ -z "$perm" ]]; then
    log WARN docker "cannot read /var/run/docker.sock"
  elif [[ "$perm" != "660" ]]; then
    log CRIT docker "docker.sock has perm ${perm} (expected 660)"
  fi

  # Containers
  local running stopped restarting
  running="$(docker ps -q 2>/dev/null | wc -l)"
  stopped="$(docker ps -aq --filter 'status=exited' 2>/dev/null | wc -l)"
  restarting="$(docker ps --filter 'status=restarting' --format '{{.Names}}' 2>/dev/null)"

  if [[ -n "$restarting" ]]; then
    local names
    names="$(tr '\n' ',' <<<"$restarting" | sed 's/,$//')"
    log WARN docker "containers in restart loop: ${names}"
  fi

  # Root user inside containers
  local root_count=0 root_examples=""
  local cid name user
  while IFS= read -r cid; do
    [[ -z "$cid" ]] && continue
    name="$(docker inspect -f '{{.Name}}' "$cid" 2>/dev/null | sed 's|^/||')"
    user="$(docker inspect -f '{{.Config.User}}' "$cid" 2>/dev/null)"
    if [[ -z "$user" || "$user" == "0" || "$user" == "root" ]]; then
      root_count=$((root_count + 1))
      if [[ "$root_count" -le 5 ]]; then
        root_examples+="${name},"
      fi
    fi
  done < <(docker ps -q 2>/dev/null)
  root_examples="${root_examples%,}"

  # Exposure on 0.0.0.0
  local exposed_wide
  exposed_wide="$(docker ps --format '{{.Ports}}' 2>/dev/null \
    | tr ',' '\n' | grep -E '(0\.0\.0\.0|\[::\])' | awk '{print $1}' | sort -u | tr '\n' ',' | sed 's/,$//')"

  if [[ "$UPDATE_BASELINE" != "1" ]]; then
    local current
    current="$(docker ps --format '{{.Names}}' 2>/dev/null | sort -u)"
    diff_against_baseline containers.list docker <<<"$current"
  fi

  local ok_msg="${running} running, ${stopped} stopped"
  [[ -n "$exposed_wide" ]] && ok_msg+=", ${#exposed_wide} bytes exposed on 0.0.0.0 ports"
  log OK docker "$ok_msg"

  if [[ "$root_count" -gt 0 ]]; then
    log WARN docker "${root_count} containers running as root (e.g. ${root_examples}...)"
  fi
}

check_suid() {
  [[ "$UPDATE_BASELINE" == "1" ]] && return
  local current
  current="$(find / -xdev -perm -4000 -type f 2>/dev/null | sort)"
  if [[ -z "$current" ]]; then
    log WARN suid "find returned empty"
    return
  fi
  diff_against_baseline suid.list suid <<<"$current"
  local n
  n="$(grep -c . <<<"$current" || true)"
  log OK suid "${n:-0} SUID binaries total"
}

check_updates() {
  if ! command -v apt >/dev/null 2>&1; then
    log INFO updates "apt missing — skipping"
    return
  fi

  local up sec_count total_count
  up="$(apt list --upgradable 2>/dev/null | tail -n +2 || true)"
  total_count=0
  [[ -n "$up" ]] && total_count=$(printf '%s\n' "$up" | grep -c .)
  sec_count=0
  [[ -n "$up" ]] && sec_count=$(printf '%s\n' "$up" | grep -c -- '-security' || true)

  if [[ "$sec_count" -gt 0 ]]; then
    log WARN updates "${sec_count} security updates pending (${total_count} total)"
  elif [[ "$total_count" -gt 0 ]]; then
    log INFO updates "${total_count} package updates (no security)"
  else
    log OK updates "no updates pending"
  fi

  # Unattended-upgrades last run
  local last
  last="$(journalctl -u unattended-upgrades.service -n 1 --no-pager -o short-iso 2>/dev/null \
          | head -1 | awk '{print $1}')"
  if [[ -n "$last" ]]; then
    local age_days now_s last_s
    now_s="$(date +%s)"
    last_s="$(date -d "$last" +%s 2>/dev/null || echo 0)"
    if [[ "$last_s" -gt 0 ]]; then
      age_days=$(( (now_s - last_s) / 86400 ))
      if [[ "$age_days" -gt 7 ]]; then
        log WARN updates "unattended-upgrades last ran ${age_days} days ago"
      else
        log OK updates "unattended-upgrades last ran ${age_days} days ago"
      fi
    fi
  else
    log INFO updates "no unattended-upgrades log found in journalctl"
  fi
}

check_rootkit() {
  if ! command -v rkhunter >/dev/null 2>&1; then
    log INFO rootkit "rkhunter missing"
    return
  fi

  local out rc=0
  out="$(sudo -n rkhunter --check --sk --rwo 2>&1 || rc=$?)"
  if [[ -z "$out" && "$rc" -eq 0 ]]; then
    log OK rootkit "rkhunter: no warnings"
    return
  fi

  local infected_count warning_count
  infected_count="$(grep -cE 'Infected|Rootkit.*found' <<<"$out" || true)"
  warning_count="$(grep -cE '^Warning' <<<"$out" || true)"

  if [[ "$infected_count" -gt 0 ]]; then
    log CRIT rootkit "rkhunter: ${infected_count} infected rows"
  elif [[ "$warning_count" -gt 0 ]]; then
    log WARN rootkit "rkhunter: ${warning_count} warnings"
  elif [[ "$rc" -ne 0 ]]; then
    log WARN rootkit "rkhunter exit=${rc}"
  else
    log OK rootkit "rkhunter: clean"
  fi
}

check_chkrootkit() {
  if ! command -v chkrootkit >/dev/null 2>&1; then
    log INFO chkrootkit "chkrootkit missing"
    return
  fi

  local out rc=0
  out="$(sudo -n chkrootkit -q 2>&1 || rc=$?)"

  local infected vulnerable
  infected="$(grep -cE 'INFECTED' <<<"$out" || true)"
  vulnerable="$(grep -ciE 'vulnerable' <<<"$out" || true)"

  if [[ "$infected" -gt 0 ]]; then
    log CRIT chkrootkit "${infected} INFECTED rows"
  elif [[ "$vulnerable" -gt 0 ]]; then
    log WARN chkrootkit "${vulnerable} vulnerable rows"
  elif [[ "$rc" -ne 0 && -z "$out" ]]; then
    log WARN chkrootkit "exit=${rc} with no output (sudo?)"
  else
    log OK chkrootkit "clean"
  fi
}

check_debsums() {
  if ! command -v debsums >/dev/null 2>&1; then
    log INFO debsums "debsums missing"
    return
  fi
  local out
  out="$(sudo -n debsums -s 2>&1 || true)"
  if [[ -z "$out" ]]; then
    log OK debsums "all package hashes match"
  else
    local n
    n="$(printf '%s\n' "$out" | grep -c .)"
    log WARN debsums "${n} package-hash mismatches"
  fi
}

check_auditd() {
  if ! command -v auditctl >/dev/null 2>&1 && [[ ! -f /etc/audit/auditd.conf ]]; then
    log INFO auditd "auditd not installed"
    return
  fi
  if systemctl is-active --quiet auditd 2>/dev/null; then
    local size=""
    [[ -f /var/log/audit/audit.log ]] && \
      size="$(stat -c%s /var/log/audit/audit.log 2>/dev/null || echo 0)"
    log OK auditd "active, audit.log=${size:-?}B"
  else
    log WARN auditd "auditd not active"
  fi
}

check_failed_units() {
  # Allowlist for known-failing units that should not count as CRIT
  local allowlist=("chkrootkit.service" "postfix@-.service")

  local failed
  failed="$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}')"
  if [[ -z "$failed" ]]; then
    log OK failed_units "no failed units"
    return
  fi

  local critical_count=0 warn_count=0 unit is_wl w names_crit="" names_wl=""
  while IFS= read -r unit; do
    [[ -z "$unit" ]] && continue
    is_wl=0
    for w in "${allowlist[@]}"; do
      [[ "$unit" == "$w" ]] && { is_wl=1; break; }
    done
    if [[ "$is_wl" -eq 1 ]]; then
      warn_count=$((warn_count + 1))
      names_wl+="${unit},"
    else
      critical_count=$((critical_count + 1))
      names_crit+="${unit},"
    fi
  done <<< "$failed"

  names_wl="${names_wl%,}"
  names_crit="${names_crit%,}"

  if [[ "$critical_count" -gt 0 ]]; then
    log CRIT failed_units "${critical_count} failed units: ${names_crit}"
  fi
  if [[ "$warn_count" -gt 0 ]]; then
    log WARN failed_units "${warn_count} known-failing units (allowlisted): ${names_wl}"
  fi
}

check_users() {
  [[ "$UPDATE_BASELINE" == "1" ]] && return
  local current
  current="$(awk -F: '$3 >= 1000 || $3 == 0 {print $1":"$3":"$7}' /etc/passwd | sort)"
  diff_against_baseline users.list users <<<"$current"

  # Extra UID-0 accounts
  local uid0_count
  uid0_count="$(awk -F: '$3 == 0 {print $1}' /etc/passwd | grep -cv '^root$' || true)"
  if [[ "$uid0_count" -gt 0 ]]; then
    local extras
    extras="$(awk -F: '$3 == 0 && $1 != "root" {print $1}' /etc/passwd | tr '\n' ',' | sed 's/,$//')"
    log CRIT users "extra UID-0 accounts: ${extras}"
  fi

  # Failed logins last 24h
  local failed_logins
  failed_logins="$(sudo -n lastb -s "-24hours" 2>/dev/null | grep -c . || echo 0)"
  if [[ "$failed_logins" -gt 50 ]]; then
    log WARN users "${failed_logins} failed logins in last 24h"
  fi

  log OK users "$(wc -l <<<"$current") accounts (UID 0 or >=1000)"
}

check_ssh_keys() {
  [[ "$UPDATE_BASELINE" == "1" ]] && return
  local current
  current="$(
    for f in /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys; do
      [[ -f "$f" ]] || continue
      while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        printf '%s %s\n' "$f" "$(printf '%s' "$line" | sha256sum | awk '{print $1}')"
      done < "$f" 2>/dev/null
    done | sort -u
  )"
  diff_against_baseline ssh_keys.list ssh_keys <<<"$current"
  local n
  n="$(grep -c . <<<"$current" || echo 0)"
  log OK ssh_keys "${n} authorized_keys lines total"
}

check_kernel_modules() {
  [[ "$UPDATE_BASELINE" == "1" ]] && return
  local current
  current="$(lsmod 2>/dev/null | awk 'NR>1 {print $1}' | sort -u)"
  diff_against_baseline kernel_modules.list kernel_modules <<<"$current"
  local n
  n="$(grep -c . <<<"$current" || true)"
  log OK kernel_modules "${n:-0} loaded modules"
}

# --- Worker mode: run a single check, write results to $RESULTS_FILE ---

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -uo pipefail

  case "${1:-}" in
    run)
      : "${RESULTS_FILE:?RESULTS_FILE must be set by caller}"
      : "${TMPDIR:?TMPDIR must be set by caller}"
      : "${BASELINE_DIR:?BASELINE_DIR must be set by caller}"
      : "${UPDATE_BASELINE:=0}"
      export TMPDIR BASELINE_DIR UPDATE_BASELINE

      fn="check_${2:-}"
      if ! declare -F "$fn" >/dev/null; then
        echo "security-check.lib.sh: unknown module: ${2:-}" >&2
        exit 2
      fi

      # Bind log() to RESULTS_FILE writer when running as worker
      log() { _lib_log_worker "$@"; }

      "$fn"
      ;;
    *)
      echo "security-check.lib.sh is a library. Usage:" >&2
      echo "  bash security-check.lib.sh run <module>   (worker mode)" >&2
      exit 2
      ;;
  esac
fi
