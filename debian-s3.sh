#!/usr/bin/env bash
# debian-security-setup.sh v3.2
#   Secure configuration helper for Debian 12
#   Licensed under MIT License

set -euo pipefail
IFS=$'\n\t'
LOGFILE="/var/log/security_config.log"
BACKUP_DIR="/root/security_backups"
DATE_STAMP=$(date +"%Y%m%d_%H%M%S")

# Logging functions
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*" | tee -a "$LOGFILE"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $*" | tee -a "$LOGFILE"; }
error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "$LOGFILE"; exit 1; }

# Ensure root
[[ $EUID -eq 0 ]] || error "This script must be run as root."

# Create backup dir
mkdir -p "$BACKUP_DIR" && chmod 700 "$BACKUP_DIR"

# Generic menu
display_menu() {
  local title="$1" opts_ref="$2" act_ref="$3"
  local opts=("${!opts_ref}") actions=("${!act_ref}")
  PS3="$title > "
  select opt in "${opts[@]}"; do
    [[ -n "$opt" ]] || { echo "Invalid option"; continue; }
    eval "${actions[$REPLY-1]}"; break
  done
}

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
  local choices=($(ls -1 "$BACKUP_DIR")) actions=()
  for c in "${choices[@]}"; do actions+=("confirm_restore '$c'"); done
  display_menu "Select backup to restore" choices[@] actions[@]
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

# Configure UFW with interactive inclusion or exclusion of detected services
configure_ufw() {
  install_pkg ufw
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow ssh && log "Allowed SSH"

  scan_active_services
  if [[ ${#DETECTED_PORTS[@]} -gt 0 ]]; then
    echo "Detected active services and ports:"
    for entry in "${DETECTED_PORTS[@]}"; do
      IFS='/' read -r port proto svc <<<"$entry"
      echo "- $svc on port $port/$proto"
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
    echo "No active listening services detected."
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
  -b, --backup       Create configuration backup
  -r, --restore      Restore from backup
  -u, --ufw          Configure UFW interactively
  -f, --fail2ban     Configure Fail2Ban
  -a, --auto         Run full auto-configuration
  -h, --help         Show this help
EOF
}

# Argument parsing
if [[ $# -gt 0 ]]; then
  while [[ $# -gt 0 ]]; do
    case $1 in
      -b|--backup) create_backup; shift;;
      -r|--restore) restore_backup; shift;;
      -u|--ufw) configure_ufw; shift;;
      -f|--fail2ban) configure_fail2ban; shift;;
      -a|--auto) create_backup; configure_ufw; configure_fail2ban; shift;;
      -h|--help) usage; exit 0;;
      *) error "Unknown option $1";;
    esac
  done
  exit 0
fi

# Interactive main menu
options=("Backup configs" "Restore backup" "Configure UFW" "Configure Fail2Ban" "Auto-configure" "Exit")
actions=("create_backup" "restore_backup" "configure_ufw" "configure_fail2ban" "create_backup; configure_ufw; configure_fail2ban" "exit 0")
display_menu "Main Menu" options[@] actions[@]
