#!/usr/bin/env bash

# Fail2Ban Manager para Debian 12+ (2025, versión universal)
# Autor: ChatGPT para usuarios exigentes
# Uso: sudo ./fail2ban-manager.sh

# --- VERIFICACIONES INICIALES ---
if [[ $EUID -ne 0 ]]; then
   echo "Este script debe ejecutarse como root (usa sudo)"
   exit 1
fi

if ! command -v apt &> /dev/null; then
    echo "Este script está diseñado para sistemas Debian/Ubuntu."
    exit 1
fi

# --- COLORES ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- VARIABLES GLOBALES ---
JAIL_LOCAL="/etc/fail2ban/jail.local"
JAIL_DIR="/etc/fail2ban/jail.d"
LOG_FILE="/var/log/fail2ban.log"

# --- UTILIDADES ---
print_header() {
    echo -e "\n${PURPLE}======================================${NC}"
    echo -e "${PURPLE}  $1${NC}"
    echo -e "${PURPLE}======================================${NC}\n"
}
pause() { read -p "Presiona Enter para continuar..." -r; }
log_action() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> /var/log/fail2ban-manager.log; }

# --- CHECK E INSTALACIÓN ---
check_installed() {
    print_header "VERIFICANDO INSTALACIÓN"
    if dpkg -l | grep -q "^ii.*fail2ban"; then
        echo -e "${GREEN}✓ Fail2Ban está instalado${NC}"
        if systemctl is-active --quiet fail2ban; then
            echo -e "${GREEN}✓ Fail2Ban ejecutándose${NC}"
        else
            echo -e "${YELLOW}⚠ Fail2Ban instalado pero no activo${NC}"
            read -p "¿Iniciar y habilitar ahora? [s/N]: " start_now
            [[ $start_now =~ ^[Ss]$ ]] && systemctl start fail2ban && systemctl enable fail2ban
        fi
        return 0
    else
        echo -e "${RED}✗ Fail2Ban NO está instalado${NC}"
        return 1
    fi
}

install_fail2ban() {
    print_header "INSTALANDO FAIL2BAN"
    apt update && apt install -y fail2ban || { echo -e "${RED}Error en instalación${NC}"; return 1; }
    mkdir -p "$JAIL_DIR"
    create_basic_config
    systemctl enable --now fail2ban
    echo -e "${GREEN}✓ Fail2Ban instalado y configurado${NC}"
    log_action "Fail2Ban instalado"
    pause
}

create_basic_config() {
    cat > "$JAIL_LOCAL" << 'EOF'
[DEFAULT]
bantime = 10m
findtime = 10m
maxretry = 5
backend = systemd
usedns = warn
logencoding = auto
enabled = false

[sshd]
enabled = true
port = ssh
filter = sshd
backend = systemd
logpath = %(systemd_journal)s
maxretry = 3
bantime = 1h
findtime = 10m
EOF
    echo -e "${GREEN}✓ Configuración básica creada (SSH ya lista para Debian 12+)${NC}"
}

# --- DETECCIÓN ENTORNO ---
detect_env() {
    print_header "DETECTANDO ENTORNO"
    if systemctl get-default | grep -q graphical; then
        TYPE="desktop"
        echo -e "${YELLOW}📱 Sistema Desktop detectado${NC}"
    else
        TYPE="server"
        echo -e "${YELLOW}🖥️  Sistema Server detectado${NC}"
    fi
    echo -e "\n${BLUE}Servicios de red detectados:${NC}"
    for s in ssh:22 http:80 https:443 ftp:21 mysql:3306 postgresql:5432; do
        n=${s%:*}; p=${s#*:}
        ss -tlnp | grep -q ":$p " && echo -e "🔓 ${YELLOW}$n${NC} activo en puerto $p"
    done
    echo
}

# --- LOGS Y STATUS ---
show_status() {
    print_header "ESTADO DE FAIL2BAN"
    if ! systemctl is-active --quiet fail2ban; then
        echo -e "${RED}✗ Fail2Ban no está ejecutándose${NC}"
        return 1
    fi
    systemctl status fail2ban --no-pager -l
    echo -e "\n${BLUE}Jails activas:${NC}"
    fail2ban-client status 2>/dev/null || echo -e "${YELLOW}No se puede obtener el estado${NC}"
    echo -e "\n${BLUE}IPs baneadas actualmente:${NC}"
    fail2ban-client banned 2>/dev/null || echo "No disponible"
}

show_logs() {
    print_header "LOGS DE FAIL2BAN"
    echo "1. Ver logs recientes (journalctl)"
    echo "2. Ver archivo de log tradicional"
    echo "3. Ver IPs baneadas por jail"
    echo "4. Filtrar logs por IP específica"
    echo "5. Volver"
    read -p "Selecciona opción: " log_opt
    case $log_opt in
        1) journalctl -u fail2ban --no-pager -n 50 ;;
        2) [[ -f "$LOG_FILE" ]] && tail -n 50 "$LOG_FILE" || echo -e "${YELLOW}Archivo de log no encontrado${NC}" ;;
        3) show_banned_ips ;;
        4) read -p "IP a buscar: " search_ip; journalctl -u fail2ban | grep "$search_ip" | tail -20 ;;
        5) return ;;
        *) echo -e "${YELLOW}Opción no válida${NC}" ;;
    esac
    pause
}

show_banned_ips() {
    echo -e "${BLUE}IPs baneadas por jail:${NC}"
    local jails=$(fail2ban-client status 2>/dev/null | grep "Jail list:" | cut -d: -f2 | tr ',' '\n' | tr -d ' ')
    [[ -z "$jails" ]] && echo -e "${YELLOW}No hay jails activas${NC}" && return
    for jail in $jails; do
        local ips=$(fail2ban-client status "$jail" 2>/dev/null | grep "Banned IP list:" | cut -d: -f2)
        [[ -n "$ips" && "$ips" != *"[]"* ]] && echo -e "${RED}[$jail]${NC}: $ips" || echo -e "${GREEN}[$jail]${NC}: Sin IPs baneadas"
    done
}

# --- CONFIGURACIÓN ---
config_menu() {
    while true; do
        print_header "CONFIGURACIÓN DE FAIL2BAN"
        echo "1. Configurar protección SSH"
        echo "2. Configurar protección servidor web"
        echo "3. Configurar protección servicios específicos"
        echo "4. Configuración avanzada de tiempos"
        echo "5. Editar configuración manualmente"
        echo "6. Validar configuración"
        echo "7. Resetear configuración"
        echo "8. Volver al menú principal"
        read -p "Selecciona opción: " config_opt
        case $config_opt in
            1) config_ssh ;;
            2) config_web ;;
            3) config_services ;;
            4) config_times ;;
            5) edit_jail ;;
            6) validate_config ;;
            7) reset_config ;;
            8) break ;;
            *) echo -e "${YELLOW}Opción no válida${NC}" ;;
        esac
    done
}

config_ssh() {
    print_header "CONFIGURACIÓN SSH (para Debian 12+)"
    read -p "¿Personalizar configuración SSH? [s/N]: " customize
    if [[ $customize =~ ^[Ss]$ ]]; then
        read -p "Máximo intentos antes del baneo [3]: " maxretry
        read -p "Tiempo de baneo en minutos [60]: " bantime
        read -p "Ventana de tiempo para contar intentos en minutos [10]: " findtime
        maxretry=${maxretry:-3}
        bantime=${bantime:-60}
        findtime=${findtime:-10}
        mkdir -p "$JAIL_DIR"
        cat > "$JAIL_DIR/sshd.conf" << EOF
[sshd]
enabled = true
port = ssh
filter = sshd
backend = systemd
logpath = %(systemd_journal)s
maxretry = $maxretry
bantime = ${bantime}m
findtime = ${findtime}m
EOF
        systemctl restart fail2ban
        echo -e "${GREEN}✓ Configuración SSH actualizada para Debian 12+${NC}"
        log_action "Configuración SSH personalizada"
    fi
    pause
}

config_web() {
    print_header "CONFIGURACIÓN SERVIDOR WEB"
    if systemctl is-active --quiet apache2; then
        web_service="apache"
    elif systemctl is-active --quiet nginx; then
        web_service="nginx"
    else
        read -p "¿Qué servidor web usas? [apache/nginx/otro]: " web_service
    fi
    mkdir -p "$JAIL_DIR"
    case $web_service in
        apache)
            cat > "$JAIL_DIR/apache.conf" << 'EOF'
[apache-auth]
enabled = true
port = http,https
filter = apache-auth
logpath = /var/log/apache2/error.log
maxretry = 3
bantime = 1h
EOF
            ;;
        nginx)
            cat > "$JAIL_DIR/nginx.conf" << 'EOF'
[nginx-http-auth]
enabled = true
port = http,https
filter = nginx-http-auth
logpath = /var/log/nginx/error.log
maxretry = 3
bantime = 1h
EOF
            ;;
        *) echo -e "${YELLOW}Configuración manual requerida${NC}" ;;
    esac
    systemctl restart fail2ban
    log_action "Configuración web para $web_service"
    pause
}

config_services() {
    print_header "CONFIGURACIÓN SERVICIOS ESPECÍFICOS"
    echo "1. FTP (ProFTPD/vsftpd)"
    echo "2. Postfix (correo)"
    echo "3. Dovecot (IMAP/POP3)"
    echo "4. MySQL/MariaDB"
    echo "5. Puerto personalizado"
    echo "6. Volver"
    read -p "Selecciona servicio: " service_opt
    mkdir -p "$JAIL_DIR"
    case $service_opt in
        1)
            cat > "$JAIL_DIR/ftp.conf" << 'EOF'
[proftpd]
enabled = true
port = ftp,ftp-data,ftps,ftps-data
filter = proftpd
logpath = /var/log/proftpd/proftpd.log
maxretry = 3
bantime = 1h
EOF
            ;;
        2)
            cat > "$JAIL_DIR/postfix.conf" << 'EOF'
[postfix]
enabled = true
port = smtp,465,submission
filter = postfix
logpath = /var/log/mail.log
maxretry = 5
bantime = 1h
EOF
            ;;
        3)
            cat > "$JAIL_DIR/dovecot.conf" << 'EOF'
[dovecot]
enabled = true
port = pop3,pop3s,imap,imaps,submission,465,sieve
filter = dovecot
logpath = /var/log/mail.log
maxretry = 3
bantime = 1h
EOF
            ;;
        4)
            cat > "$JAIL_DIR/mysql.conf" << 'EOF'
[mysqld-auth]
enabled = true
port = 3306
filter = mysqld-auth
logpath = /var/log/mysql/error.log
maxretry = 3
bantime = 1h
EOF
            ;;
        5) config_custom_port ;;
        6) return ;;
        *) echo -e "${YELLOW}Opción no válida${NC}" ;;
    esac
    systemctl restart fail2ban
    log_action "Configuración de servicio específica creada"
    pause
}

config_custom_port() {
    read -p "Introduce el puerto a proteger: " custom_port
    read -p "Nombre para la jail [custom-$custom_port]: " jail_name
    jail_name=${jail_name:-custom-$custom_port}
    mkdir -p "$JAIL_DIR"
    cat > "$JAIL_DIR/$jail_name.conf" << EOF
[$jail_name]
enabled = true
port = $custom_port
filter = sshd
backend = systemd
logpath = %(systemd_journal)s
maxretry = 3
bantime = 10m
findtime = 10m
EOF
    echo -e "${GREEN}✓ Jail personalizada '$jail_name' creada para puerto $custom_port${NC}"
    systemctl restart fail2ban
    log_action "Jail personalizada creada: $jail_name (puerto $custom_port)"
    pause
}

config_times() {
    print_header "CONFIGURACIÓN DE TIEMPOS"
    read -p "Tiempo de baneo por defecto en minutos [10]: " def_bantime
    read -p "Ventana de tiempo para contar intentos en minutos [10]: " def_findtime
    read -p "Máximo de intentos por defecto [5]: " def_maxretry
    def_bantime=${def_bantime:-10}
    def_findtime=${def_findtime:-10}
    def_maxretry=${def_maxretry:-5}
    sed -i "s/^bantime.*/bantime = ${def_bantime}m/" "$JAIL_LOCAL"
    sed -i "s/^findtime.*/findtime = ${def_findtime}m/" "$JAIL_LOCAL"
    sed -i "s/^maxretry.*/maxretry = $def_maxretry/" "$JAIL_LOCAL"
    systemctl restart fail2ban
    echo -e "${GREEN}✓ Configuración de tiempos actualizada${NC}"
    log_action "Tiempos globales actualizados"
    pause
}

edit_jail() {
    print_header "EDICIÓN MANUAL"
    nano "$JAIL_LOCAL"
    systemctl restart fail2ban
    echo -e "${GREEN}✓ Configuración actualizada${NC}"
    pause
}

validate_config() {
    print_header "VALIDANDO CONFIGURACIÓN"
    fail2ban-client -t && echo -e "${GREEN}✓ Configuración válida${NC}" || echo -e "${RED}✗ Errores en la configuración${NC}"
    pause
}

reset_config() {
    print_header "RESETEAR CONFIGURACIÓN"
    read -p "¿Estás seguro? Escribe 'CONFIRMAR': " confirm
    if [[ "$confirm" == "CONFIRMAR" ]]; then
        backup_dir="/root/fail2ban-backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$backup_dir"
        cp -r /etc/fail2ban/ "$backup_dir/"
        rm -f "$JAIL_LOCAL" "$JAIL_DIR"/*.conf
        create_basic_config
        systemctl restart fail2ban
        echo -e "${GREEN}✓ Configuración reseteada${NC}"
        echo -e "${BLUE}Backup guardado en: $backup_dir${NC}"
        log_action "Configuración reseteada, backup en $backup_dir"
    else
        echo -e "${YELLOW}Operación cancelada${NC}"
    fi
    pause
}

# --- MENÚ PRINCIPAL ---
main_menu() {
    while true; do
        print_header "GESTOR INTERACTIVO FAIL2BAN - Debian 12+"
        echo "1. Verificar e instalar Fail2Ban"
        echo "2. Detectar entorno y servicios"
        echo "3. Configurar Fail2Ban"
        echo "4. Estado y funcionamiento"
        echo "5. Logs y actividad"
        echo "6. Salir"
        read -p "Selecciona opción: " main_opt
        case $main_opt in
            1) check_installed || install_fail2ban ;;
            2) detect_env; pause ;;
            3) config_menu ;;
            4) show_status; pause ;;
            5) show_logs ;;
            6) echo -e "${GREEN}¡Hasta luego!${NC}"; exit 0 ;;
            *) echo -e "${YELLOW}Opción no válida${NC}" ;;
        esac
    done
}

# --- EJECUCIÓN ---
detect_env
main_menu
