#!/usr/bin/env bash
# debian-security-setup.sh v3.3
#   Secure configuration helper for Debian 12
#   Licensed under MIT License

set -euo pipefail
IFS=$'\n\t'
LOGFILE="/var/log/security_config.log"
BACKUP_DIR="/root/security_backups"
DATE_STAMP=$(date +"%Y%m%d_%H%M%S")

# Color codes
BLUE="\e[1;34m"
GREEN="\e[1;32m"
YELLOW="\e[1;33m"
RED="\e[1;31m"
NC="\e[0m"

# Logging functions
log() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*" | tee -a "$LOGFILE"; }
warn() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $*" | tee -a "$LOGFILE"; }
error() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "$LOGFILE"; exit 1; }

# Ensure root
[[ $EUID -eq 0 ]] || error "This script must be run as root."

# Create backup dir
mkdir -p "$BACKUP_DIR" && chmod 700 "$BACKUP_DIR"

# Backup configs with checksum
create_backup() {
  log "Starting backup..."
  local stamp="$DATE_STAMP"
  mkdir -p "$BACKUP_DIR/$stamp"
  for file in /etc/ufw /etc/fail2ban /etc/ssh/sshd_config; do
    [[ -e "$file" ]] || continue
    cp -a "$file" "$BACKUP_DIR/$stamp/"
    sha256sum "$BACKUP_DIR/$stamp/$(basename "$file")" > "$BACKUP_DIR/$stamp/$(basename "$file").sha256"
  done
  ufw status verbose > "$BACKUP_DIR/$stamp/ufw_status.txt"
  log "Backup saved under $stamp"
}

# Restore backups
restore_backup() {
  local choices=($(ls -1 "$BACKUP_DIR"))
  echo -e "${GREEN}Available backups:${NC}"
  for idx in "${!choices[@]}"; do
    printf "%2d) %s\n" $((idx+1)) "${choices[$idx]}"
  done
  read -rp "Select backup to restore: " sel
  [[ "$sel" =~ ^[0-9]+$ ]] && sel=$((sel-1)) || { echo "Invalid"; return; }
  confirm_restore "${choices[$sel]}"
}
confirm_restore() {
  local stamp="$1"
  read -rp "Really restore backup $stamp? (y/n) " ans
  [[ $ans =~ ^[Yy]$ ]] || return
  for file in $(ls "$BACKUP_DIR/$stamp"); do
    [[ $file == *.sha256 ]] && continue
    sha256sum --check "$BACKUP_DIR/$stamp/$file.sha256"
    cp -a "$BACKUP_DIR/$stamp/$file" "/$(basename "$file")"
  done
  log "Restored backup $stamp"
}

# Install package if missing
install_pkg() {
  local pkg="$1"
  if ! dpkg -s "$pkg" &>/dev/null; then
    apt-get update && apt-get install -y "$pkg"
    log "Installed $pkg"
  else
    log "$pkg already installed"
  fi
}

# Detect active network services and open ports
scan_active_services() {
  declare -A ports
  while IFS= read -r line; do
    proto=$(awk '{print $1}' <<<"$line")
    addr=$(awk '{print $5}' <<<"$line")
    svc=$(awk -F '"' '{print $2}' <<<"$line" )
    port=${addr##*:}
    ports["$port/$proto/$svc"]=1
  done < <(ss -tulpnH)
  DETECTED_PORTS=()
  for key in "${!ports[@]}"; do DETECTED_PORTS+=("$key"); done
}

# Configure UFW with interactive inclusion/exclusion
configure_ufw() {
  install_pkg ufw
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow ssh && log "Allowed SSH"

  scan_active_services
  if (( ${#DETECTED_PORTS[@]} )); then
    echo -e "${YELLOW}Detected active services and ports:${NC}"
    for entry in "${DETECTED_PORTS[@]}"; do
      IFS='/' read -r port proto svc <<<"$entry"
      printf "- %s on %s/%s\n" "$svc" "$port" "$proto"
      PS3="Action for $svc ($port/$proto): "
      select choice in "Allow" "Deny"; do
        case $choice in
          Allow)
            ufw allow "$port/$proto" && log "Allowed $svc ($port/$proto)"
            break;;
          Deny)
            ufw deny "$port/$proto" && log "Denied $svc ($port/$proto)"
            break;;
          *) echo "Invalid choice";;
        esac
      done
    done
  else
    echo -e "${GREEN}No active listening services detected.${NC}"
  fi
  for svc in http https; do
    if command -v "$svc" &>/dev/null; then ufw allow "$svc" && log "Allowed $svc"; fi
  done
  ufw --force enable
  log "UFW configured"
}

# Fail2Ban config
configure_fail2ban() {
  install_pkg fail2ban
  cat > /etc/fail2ban/jail.local <<-'EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
[sshd]
enabled = true
EOF
  systemctl restart fail2ban
  log "Fail2Ban configured"
}

# Usage info
usage() {
  cat <<-EOF
Usage: $0 [options]
  -b, --backup       Backup configs
  -r, --restore      Restore backup
  -u, --ufw          Configure UFW
  -f, --fail2ban     Configure Fail2Ban
  -a, --auto         Full auto-configuration
  -h, --help         Help
EOF
}

# Argument parsing
if (( $# )); then
  while (( $# )); do
    case $1 in
      -b|--backup) create_backup;;
      -r|--restore) restore_backup;;
      -u|--ufw) configure_ufw;;
      -f|--fail2ban) configure_fail2ban;;
      -a|--auto) create_backup; configure_ufw; configure_fail2ban;;
      -h|--help) usage; exit 0;;
      *) error "Unknown option $1";;
    esac
    shift
  done
  exit
fi

# Interactive Main Menu
while :; do
  echo ""
  echo "1) Backup configs      3) Configure UFW      5) Auto-configure"
  echo "2) Restore backup      4) Configure Fail2Ban 6) Exit"
  read -rp "Main Menu > " choice
  case $choice in
    1) create_backup ;; 
    2) restore_backup ;; 
    3) configure_ufw ;; 
    4) configure_fail2ban ;; 
    5) create_backup; configure_ufw; configure_fail2ban ;; 
    6) echo "Bye!"; exit 0 ;; 
    *) echo "Invalid option" ;; 
  esac
done
