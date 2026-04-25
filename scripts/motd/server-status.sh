#!/usr/bin/env bash
# server-status.sh — SSH login banner: ASCII hostname + live system snapshot.
# Drop into /etc/update-motd.d/ (e.g. as 00-custom-header) and chmod +x.
# The banner letters render the uppercased hostname; falls back to HOMELAB.

# --- DATA ---
UPTIME_SHORT=$(uptime -p | sed \
    's/up //;s/, [0-9]* minutes\?.*//;s/ days\?/d/;s/ hours\?/h/;s/,//')
IP=$(hostname -I | awk '{print $1}')
OS=$(lsb_release -d 2>/dev/null | cut -f2 | awk '{print tolower($0)}')
TEMP_C="??"
[ -f /sys/class/thermal/thermal_zone0/temp ] && \
    TEMP_C=$(( $(cat /sys/class/thermal/thermal_zone0/temp) / 1000 ))

MEM_USED=$(free -m | awk 'NR==2{print $3}')
MEM_TOTAL=$(free -m | awk 'NR==2{print $2}')
MEM_PERC=$((MEM_USED * 100 / MEM_TOTAL))
MEM_UG=$(echo "scale=1; $MEM_USED/1024" | bc)
MEM_TG=$(echo "scale=1; $MEM_TOTAL/1024" | bc)

DISK_USED=$(LC_ALL=C df -h / | awk '$NF=="/"{print $3}')
DISK_TOTAL=$(LC_ALL=C df -h / | awk '$NF=="/"{print $2}')
DISK_PERC=$(LC_ALL=C df -h / | awk '$NF=="/"{print $5}' | tr -d '%')

STORAGE_DIR="${STORAGE_DIR:-/mnt/storage}"
MEDIA_DIR="${MEDIA_DIR:-/mnt/media}"

STO_USED="N/A"; STO_TOTAL="N/A"; STO_PERC=0
mountpoint -q "$STORAGE_DIR" && \
    STO_USED=$(LC_ALL=C df -h "$STORAGE_DIR" | awk 'NR==2{print $3}') && \
    STO_TOTAL=$(LC_ALL=C df -h "$STORAGE_DIR" | awk 'NR==2{print $2}') && \
    STO_PERC=$(LC_ALL=C df -h "$STORAGE_DIR" | awk 'NR==2{print $5}' | tr -d '%')

MED_USED="N/A"; MED_TOTAL="N/A"; MED_PERC=0
mountpoint -q "$MEDIA_DIR" && \
    MED_USED=$(LC_ALL=C df -h "$MEDIA_DIR" | awk 'NR==2{print $3}') && \
    MED_TOTAL=$(LC_ALL=C df -h "$MEDIA_DIR" | awk 'NR==2{print $2}') && \
    MED_PERC=$(LC_ALL=C df -h "$MEDIA_DIR" | awk 'NR==2{print $5}' | tr -d '%')

LOAD=$(cut -d ' ' -f1,2,3 /proc/loadavg)

GPU_TEMP="??"; GPU_UTIL="0"; GPU_MG="??"; GPU_TG="??"
if command -v nvidia-smi &>/dev/null; then
    read -r GPU_TEMP GPU_UTIL GPU_MEM_USED GPU_MEM_TOTAL < <(
        nvidia-smi --query-gpu=temperature.gpu,utilization.gpu,memory.used,memory.total \
            --format=csv,noheader,nounits 2>/dev/null | tr -d ' ' | tr ',' ' ')
    GPU_MG=$(echo "scale=1; $GPU_MEM_USED/1024" | bc)
    GPU_TG=$(echo "scale=1; $GPU_MEM_TOTAL/1024" | bc)
fi

DR=0; DT=0
command -v docker &>/dev/null && \
    DR=$(docker ps -q | wc -l) && DT=$(docker ps -aq | wc -l)

VPN_TEXT="disconnected"; VPN_OK=false
command -v mullvad &>/dev/null && \
    [[ "$(mullvad status | head -n1)" == *"Connected"* ]] && \
    VPN_TEXT="connected" && VPN_OK=true

UPDATES=0; SEC_UPD=0
if [ -f /var/lib/update-notifier/updates-available ]; then
    U=$(grep -oP '^\d+(?= updates? can be installed)' \
        /var/lib/update-notifier/updates-available)
    S=$(grep -oP '^\d+(?= updates are security updates)' \
        /var/lib/update-notifier/updates-available)
    [ -n "$U" ] && UPDATES=$U; [ -n "$S" ] && SEC_UPD=$S
fi

F2B=0
command -v fail2ban-client &>/dev/null && \
    F2B=$(fail2ban-client status 2>/dev/null | grep "Jail list" | sed 's/.*Jail list://' | \
        tr -d ',' | xargs -n1 fail2ban-client status 2>/dev/null | \
        grep "Currently banned" | awk '{sum+=$4} END{print sum+0}')

BACKUP_LOG="${BACKUP_LOG:-$HOME/logs/backup.log}"
LAST_BACKUP=$([ -f "$BACKUP_LOG" ] && \
    date -r "$BACKUP_LOG" "+%Y-%m-%d %H:%M" || echo "N/A")
LAST_USER="${SUDO_USER:-${USER:-$(id -un)}}"
LAST_RAW=$(LC_TIME=C last -F "$LAST_USER" 2>/dev/null \
    | grep -v "still logged in\|^$\|^wtmp" | head -1)
LAST_IP=$(echo "$LAST_RAW" | awk '{print $3}')
LAST_DATE=$(echo "$LAST_RAW" | awk '{printf "%s %s %s", $5, $6, substr($7,1,5)}')

# --- COLORS ---
NC="\033[0m"
DIM="\033[38;5;238m"
LBL="\033[38;5;244m"
OK="\033[38;5;71m"
WARN="\033[38;5;179m"
CRIT="\033[38;5;167m"
A="\033[38;2;99;166;255m"

sc() { [ "$1" -gt 95 ] && echo "$CRIT" || { [ "$1" -gt 80 ] && echo "$WARN" || echo "$OK"; }; }
C_MEM=$(sc $MEM_PERC); C_DISK=$(sc $DISK_PERC)
C_STO=$(sc $STO_PERC); C_MED=$(sc $MED_PERC)
C_VPN=$OK;  $VPN_OK || C_VPN=$CRIT
C_UPD=$OK;  [ "$UPDATES" != "0" ] && C_UPD=$WARN
             [ "$SEC_UPD" != "0" ] && C_UPD=$CRIT

bar() {
    local p=$1 c=$2 f=$(( p * 24 / 100 )) b=""
    [ $f -gt 24 ] && f=24
    for ((i=0;i<f;i++));  do b+="█"; done
    for ((i=f;i<24;i++)); do b+="░"; done
    printf "${c}%s${NC}" "$b"
}

rule() {
    printf "\n  ${DIM}"
    for ((i=0;i<60;i++)); do printf "─"; done
    printf "${NC}\n\n"
}

# --- BANNER LETTERS (block-style figlet glyphs) ---
# A glyph is 6 lines tall, fixed width per letter.
declare -A G

G[A_0]="  █████╗ "
G[A_1]=" ██╔══██╗"
G[A_2]=" ███████║"
G[A_3]=" ██╔══██║"
G[A_4]=" ██║  ██║"
G[A_5]=" ╚═╝  ╚═╝"

G[B_0]=" ██████╗ "
G[B_1]=" ██╔══██╗"
G[B_2]=" ██████╔╝"
G[B_3]=" ██╔══██╗"
G[B_4]=" ██████╔╝"
G[B_5]=" ╚═════╝ "

G[C_0]="  ██████╗"
G[C_1]=" ██╔════╝"
G[C_2]=" ██║     "
G[C_3]=" ██║     "
G[C_4]=" ╚██████╗"
G[C_5]="  ╚═════╝"

G[D_0]=" ██████╗ "
G[D_1]=" ██╔══██╗"
G[D_2]=" ██║  ██║"
G[D_3]=" ██║  ██║"
G[D_4]=" ██████╔╝"
G[D_5]=" ╚═════╝ "

G[E_0]=" ███████╗"
G[E_1]=" ██╔════╝"
G[E_2]=" █████╗  "
G[E_3]=" ██╔══╝  "
G[E_4]=" ███████╗"
G[E_5]=" ╚══════╝"

G[H_0]=" ██╗  ██╗"
G[H_1]=" ██║  ██║"
G[H_2]=" ███████║"
G[H_3]=" ██╔══██║"
G[H_4]=" ██║  ██║"
G[H_5]=" ╚═╝  ╚═╝"

G[L_0]=" ██╗     "
G[L_1]=" ██║     "
G[L_2]=" ██║     "
G[L_3]=" ██║     "
G[L_4]=" ███████╗"
G[L_5]=" ╚══════╝"

G[M_0]=" ███╗   ███╗"
G[M_1]=" ████╗ ████║"
G[M_2]=" ██╔████╔██║"
G[M_3]=" ██║╚██╔╝██║"
G[M_4]=" ██║ ╚═╝ ██║"
G[M_5]=" ╚═╝     ╚═╝"

G[O_0]="  ██████╗ "
G[O_1]=" ██╔═══██╗"
G[O_2]=" ██║   ██║"
G[O_3]=" ██║   ██║"
G[O_4]=" ╚██████╔╝"
G[O_5]="  ╚═════╝ "

# Default banner if hostname has letters we don't have a glyph for.
HOSTBANNER="${HOSTNAME:-$(hostname -s 2>/dev/null)}"
HOSTBANNER="${HOSTBANNER^^}"
SUPPORTED="ABCDEHLMO"
banner_letters="HOMELAB"
for ((i=0; i<${#HOSTBANNER}; i++)); do
    ch="${HOSTBANNER:$i:1}"
    [[ "$SUPPORTED" != *"$ch"* ]] && { banner_letters="HOMELAB"; break; }
    [[ $i -eq 0 ]] && banner_letters=""
    banner_letters+="$ch"
done

# --- OUTPUT ---
printf "\n"

declare -a GRAD=("50;100;210" "63;120;232" "77;140;248" "90;158;255" "103;173;255" "116;188;255")

for row in 0 1 2 3 4 5; do
    line="  "
    for ((i=0; i<${#banner_letters}; i++)); do
        ch="${banner_letters:$i:1}"
        line+="${G[${ch}_${row}]}"
    done
    printf "\033[38;2;%sm%s\033[0m\n" "${GRAD[$row]}" "$line"
done

printf "\n"
printf "  ${LBL}%s${NC}  ·  up %s  ·  ${A}%s${NC}\n" "$OS" "$UPTIME_SHORT" "$IP"

rule

printf "  ${LBL}cpu  ${NC}%s   ${LBL}temp ${NC}%sC\n" "$LOAD" "$TEMP_C"
printf "  ${LBL}gpu  ${NC}%sC   %s%% util   %s / %sG vram\n" \
    "$GPU_TEMP" "$GPU_UTIL" "$GPU_MG" "$GPU_TG"
printf "\n"
printf "  ${LBL}mem    ${NC}"; bar $MEM_PERC  "$C_MEM"
    printf "  ${C_MEM}%3d%%${NC}  %s / %s GB\n" $MEM_PERC  "$MEM_UG"    "$MEM_TG"
printf "  ${LBL}root   ${NC}"; bar $DISK_PERC "$C_DISK"
    printf "  ${C_DISK}%3d%%${NC}  %s / %s\n"   $DISK_PERC "$DISK_USED" "$DISK_TOTAL"
printf "  ${LBL}store  ${NC}"; bar $STO_PERC  "$C_STO"
    printf "  ${C_STO}%3d%%${NC}  %s / %s\n"    $STO_PERC  "$STO_USED"  "$STO_TOTAL"
printf "  ${LBL}media  ${NC}"; bar $MED_PERC  "$C_MED"
    printf "  ${C_MED}%3d%%${NC}  %s / %s\n"    $MED_PERC  "$MED_USED"  "$MED_TOTAL"

rule

printf "  ${LBL} docker  ${A}%-16s${NC}  ${LBL} vpn      ${C_VPN}%s${NC}\n" \
    "$DR / $DT" "$VPN_TEXT"
printf "  ${LBL} updates ${C_UPD}%-16s${NC}  ${LBL} banned   ${NC}%s IPs\n" \
    "$UPDATES" "$F2B"

rule

printf "  ${LBL} login   ${NC}%s   %s\n" "$LAST_DATE" "$LAST_IP"
printf "  ${LBL} backup  ${OK}%s${NC}\n" "$LAST_BACKUP"
printf "\n  ${DIM}"
for ((i=0;i<60;i++)); do printf "─"; done
printf "${NC}\n\n"
