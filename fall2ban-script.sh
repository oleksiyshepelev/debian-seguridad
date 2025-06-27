#!/usr/bin/env bash

# Gestionar Fail2Ban en Debian 12+ - Menú interactivo profesional
# Versión: 2.0 | 2025 | ChatGPT

# --- VERIFICACIONES INICIALES ---
if [[ $EUID -ne 0 ]]; then
   echo "Este script debe ejecutarse como root (usa sudo)" 
   exit 1
fi

if ! command -v apt &> /dev/null; then
    echo "Este script está diseñado para sistemas basados en Debian/Ubuntu"
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

# --- FUNCIONES DE UTILIDAD ---
print_header() {
    echo -e "\n${PURPLE}======================================${NC}"
    echo -e "${PURPLE}  $1${NC}"
    echo -e "${PURPLE}======================================${NC}\n"
}

pause() {
    read -p "Presiona Enter para continuar..." -r
}

log_action() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> /var/log/fail2ban-manager.log
}

# --- FUNCIONES BÁSICAS ---

check_installed() {
    print_header "VERIFICANDO INSTALACIÓN"
    if dpkg -l | grep -q "^ii.*fail2ban"; then
        echo -e "${GREEN}✓ Fail2Ban está instalado${NC}"
        if systemctl is-active --quiet fail2ban; then
            echo -e "${GREEN}✓ Fail2Ban está ejecutándose${NC}"
            systemctl status fail2ban --no-pager -l
        else
            echo -e "${YELLOW}⚠ Fail2Ban está instalado pero no ejecutándose${NC}"
            read -p "¿Quieres iniciarlo ahora? [s/N]: " start_now
            if [[ $start_now =~ ^[Ss]$ ]]; then
                systemctl start fail2ban
                systemctl enable fail2ban
                echo -e "${GREEN}✓ Fail2Ban iniciado y habilitado${NC}"
            fi
        fi
        return 0
    else
        echo -e "${RED}✗ Fail2Ban NO está instalado${NC}"
        return 1
    fi
}

install_fail2ban() {
    print_header "INSTALANDO FAIL2BAN"
    echo -e "${BLUE}Actualizando repositorios...${NC}"
    apt update || { echo -e "${RED}Error al actualizar repositorios${NC}"; return 1; }
    echo -e "${BLUE}Instalando Fail2Ban y dependencias...${NC}"
    apt install -y fail2ban rsyslog || { echo -e "${RED}Error en la instalación${NC}"; return 1; }
    mkdir -p "$JAIL_DIR"
    create_basic_config
    systemctl enable fail2ban
    systemctl start fail2ban
    echo -e "${GREEN}✓ Fail2Ban instalado y configurado correctamente${NC}"
    log_action "Fail2Ban instalado"
}

create_basic_config() {
    echo -e "${BLUE}Creando configuración básica...${NC}"
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
logpath = /var/log/auth.log
maxretry = 3
bantime = 1h
findtime = 10m
EOF
    echo -e "${GREEN}✓ Configuración básica creada${NC}"
}

show_status() {
    print_header "ESTADO DE FAIL2BAN"
    if ! systemctl is-active --quiet fail2ban; then
        echo -e "${RED}✗ Fail2Ban no está ejecutándose${NC}"
        return 1
    fi
    echo -e "${BLUE}Estado del servicio:${NC}"
    systemctl status fail2ban --no-pager -l
    echo -e "\n${BLUE}Jails activas:${NC}"
    fail2ban-client status 2>/dev/null || echo -e "${YELLOW}No se puede obtener el estado${NC}"
    echo -e "\n${BLUE}Estadísticas rápidas:${NC}"
    local banned_total=$(fail2ban-client banned 2>/dev/null | wc -w)
    echo -e "Total de IPs baneadas actualmente: ${YELLOW}$banned_total${NC}"
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
        1)
            echo -e "${BLUE}Últimos 50 registros:${NC}"
            journalctl -u fail2ban --no-pager -n 50
            ;;
        2)
            if [[ -f "$LOG_FILE" ]]; then
                echo -e "${BLUE}Últimas 50 líneas del log:${NC}"
                tail -n 50 "$LOG_FILE"
            else
                echo -e "${YELLOW}Archivo de log no encontrado en $LOG_FILE${NC}"
            fi
            ;;
        3)
            show_banned_ips
            ;;
        4)
            read -p "Introduce la IP a buscar: " search_ip
            if [[ -f "$LOG_FILE" ]]; then
                grep "$search_ip" "$LOG_FILE" | tail -20
            else
                journalctl -u fail2ban | grep "$search_ip" | tail -20
            fi
            ;;
        5)
            return
            ;;
        *)
            echo -e "${YELLOW}Opción no válida${NC}"
            ;;
    esac
    pause
}

show_banned_ips() {
    echo -e "${BLUE}IPs baneadas por jail:${NC}"
    local jails=$(fail2ban-client status 2>/dev/null | grep "Jail list:" | cut -d: -f2 | tr ',' '\n' | tr -d ' ')
    if [[ -z "$jails" ]]; then
        echo -e "${YELLOW}No hay jails activas${NC}"
        return
    fi
    for jail in $jails; do
        local banned_ips=$(fail2ban-client status "$jail" 2>/dev/null | grep "Banned IP list:" | cut -d: -f2)
        if [[ -n "$banned_ips" && "$banned_ips" != *"[]"* ]]; then
            echo -e "${RED}[$jail]${NC}: $banned_ips"
        else
            echo -e "${GREEN}[$jail]${NC}: Sin IPs baneadas"
        fi
    done
}

check_function() {
    print_header "VERIFICANDO FUNCIONAMIENTO"
    if ! systemctl is-active --quiet fail2ban; then
        echo -e "${RED}✗ Fail2Ban no está ejecutándose${NC}"
        return 1
    fi
    echo -e "${BLUE}Estado general:${NC}"
    fail2ban-client status
    echo -e "\n${BLUE}Verificando jails individuales:${NC}"
    local jails=$(fail2ban-client status 2>/dev/null | grep "Jail list:" | cut -d: -f2 | tr ',' '\n' | tr -d ' ')
    for jail in $jails; do
        echo -e "\n${CYAN}--- Jail: $jail ---${NC}"
        fail2ban-client status "$jail" 2>/dev/null || echo -e "${RED}Error al obtener estado de $jail${NC}"
    done
    echo -e "\n${BLUE}Verificando archivos de configuración:${NC}"
    fail2ban-client -t 2>/dev/null && echo -e "${GREEN}✓ Configuración válida${NC}" || echo -e "${RED}✗ Error en la configuración${NC}"
}

# --- DETECCIÓN DE ENTORNO ---
detect_env() {
    print_header "DETECTANDO ENTORNO"
    if systemctl get-default | grep -q graphical; then
        TYPE="desktop"
        echo -e "${YELLOW}📱 Sistema Desktop detectado${NC}"
    else
        TYPE="server"
        echo -e "${YELLOW}🖥️  Sistema Server detectado${NC}"
    fi
    echo -e "\n${BLUE}Información de red:${NC}"
    local interfaces=$(ip route | grep default | awk '{print $5}' | sort -u)
    for iface in $interfaces; do
        local ip=$(ip addr show "$iface" 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
        if [[ -n "$ip" ]]; then
            if [[ $ip =~ ^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.) ]]; then
                echo -e "🔒 Interfaz $iface: ${GREEN}$ip (IP privada)${NC}"
            else
                echo -e "🌐 Interfaz $iface: ${RED}$ip (IP pública - ¡Mayor riesgo!)${NC}"
            fi
        fi
    done
    echo -e "\n${BLUE}Servicios de red detectados:${NC}"
    local services=("ssh:22" "http:80" "https:443" "ftp:21" "mysql:3306" "postgresql:5432")
    for service in "${services[@]}"; do
        local name=${service%:*}
        local port=${service#*:}
        if ss -tlnp | grep -q ":$port "; then
            echo -e "🔓 ${YELLOW}$name${NC} activo en puerto $port"
        fi
    done
}

# --- GESTIÓN DE IPS ---
manage_ips() {
    while true; do
        print_header "GESTIÓN DE IPS"
        echo "1. Ver IPs baneadas"
        echo "2. Desbanear IP específica"
        echo "3. Banear IP manualmente"
        echo "4. Añadir IP a whitelist"
        echo "5. Ver whitelist actual"
        echo "6. Limpiar todos los baneos"
        echo "7. Volver al menú principal"
        read -p "Selecciona opción: " ip_opt
        case $ip_opt in
            1) show_banned_ips; pause ;;
            2) unban_ip ;;
            3) ban_ip ;;
            4) add_to_whitelist ;;
            5) show_whitelist; pause ;;
            6) clear_all_bans ;;
            7) break ;;
            *) echo -e "${YELLOW}Opción no válida${NC}" ;;
        esac
    done
}

unban_ip() {
    read -p "Introduce la IP a desbanear: " ip_to_unban
    if [[ -z "$ip_to_unban" ]]; then
        echo -e "${YELLOW}IP no válida${NC}"; return
    fi
    local jails=$(fail2ban-client status 2>/dev/null | grep "Jail list:" | cut -d: -f2 | tr ',' '\n' | tr -d ' ')
    local unbanned=false
    for jail in $jails; do
        if fail2ban-client status "$jail" | grep -q "$ip_to_unban"; then
            fail2ban-client unban "$ip_to_unban"
            echo -e "${GREEN}✓ IP $ip_to_unban desbaneada de $jail${NC}"
            unbanned=true
        fi
    done
    if [[ "$unbanned" == false ]]; then
        echo -e "${YELLOW}IP $ip_to_unban no encontrada en ninguna jail${NC}"
    fi
    log_action "IP desbaneada manualmente: $ip_to_unban"
    pause
}

ban_ip() {
    read -p "Introduce la IP a banear: " ip_to_ban
    read -p "Introduce el nombre de la jail: " jail_name
    if [[ -z "$ip_to_ban" || -z "$jail_name" ]]; then
        echo -e "${YELLOW}Datos no válidos${NC}"; return
    fi
    fail2ban-client set "$jail_name" banip "$ip_to_ban" 2>/dev/null && \
        echo -e "${GREEN}✓ IP $ip_to_ban baneada en $jail_name${NC}" || \
        echo -e "${RED}✗ Error al banear IP${NC}"
    log_action "IP baneada manualmente: $ip_to_ban en jail $jail_name"
    pause
}

add_to_whitelist() {
    read -p "Introduce la IP para la whitelist: " whitelist_ip
    if [[ -z "$whitelist_ip" ]]; then
        echo -e "${YELLOW}IP no válida${NC}"; return
    fi
    if grep -q "^ignoreip" "$JAIL_LOCAL"; then
        sed -i "s/^ignoreip.*/& $whitelist_ip/" "$JAIL_LOCAL"
    else
        sed -i '/^\[DEFAULT\]/a ignoreip = 127.0.0.1/8 ::1 '"$whitelist_ip" "$JAIL_LOCAL"
    fi
    systemctl reload fail2ban
    echo -e "${GREEN}✓ IP $whitelist_ip añadida a la whitelist${NC}"
    log_action "IP añadida a whitelist: $whitelist_ip"
    pause
}

show_whitelist() {
    echo -e "${BLUE}IPs en whitelist:${NC}"
    if grep -q "^ignoreip" "$JAIL_LOCAL"; then
        grep "^ignoreip" "$JAIL_LOCAL" | cut -d= -f2-
    else
        echo -e "${YELLOW}No hay whitelist configurada${NC}"
    fi
}

clear_all_bans() {
    read -p "¿Estás seguro de limpiar TODOS los baneos? [s/N]: " confirm
    if [[ $confirm =~ ^[Ss]$ ]]; then
        local jails=$(fail2ban-client status 2>/dev/null | grep "Jail list:" | cut -d: -f2 | tr ',' '\n' | tr -d ' ')
        for jail in $jails; do
            fail2ban-client unban --all "$jail" 2>/dev/null
        done
        echo -e "${GREEN}✓ Todos los baneos limpiados${NC}"
        log_action "Todos los baneos limpiados"
    fi
    pause
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
    print_header "CONFIGURACIÓN SSH"
    echo "Configuración actual de SSH:"
    if grep -A 10 "^\[sshd\]" "$JAIL_LOCAL" 2>/dev/null; then echo ""; else echo -e "${YELLOW}No hay configuración SSH específica${NC}"; fi
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
logpath = /var/log/auth.log
maxretry = $maxretry
bantime = ${bantime}m
findtime = ${findtime}m
EOF
        systemctl restart fail2ban
        echo -e "${GREEN}✓ Configuración SSH actualizada${NC}"
        log_action "Configuración SSH personalizada: maxretry=$maxretry, bantime=${bantime}m"
    fi
    pause
}

config_web() {
    print_header "CONFIGURACIÓN SERVIDOR WEB"
    echo "Servicios web detectados:"
    if systemctl is-active --quiet apache2; then
        echo -e "${GREEN}✓ Apache2 activo${NC}"; web_service="apache"
    elif systemctl is-active --quiet nginx; then
        echo -e "${GREEN}✓ Nginx activo${NC}"; web_service="nginx"
    else
        echo -e "${YELLOW}No se detectaron servicios web activos${NC}"
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
[apache-badbots]
enabled = true
port = http,https
filter = apache-badbots
logpath = /var/log/apache2/access.log
maxretry = 2
bantime = 2h
[apache-noscript]
enabled = true
port = http,https
filter = apache-noscript
logpath = /var/log/apache2/access.log
maxretry = 3
bantime = 1h
EOF
            echo -e "${GREEN}✓ Configuración Apache creada${NC}"
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
[nginx-limit-req]
enabled = true
port = http,https
filter = nginx-limit-req
logpath = /var/log/nginx/error.log
maxretry = 10
findtime = 60
bantime = 1h
[nginx-botsearch]
enabled = true
port = http,https
filter = nginx-botsearch
logpath = /var/log/nginx/access.log
maxretry = 2
bantime = 2h
EOF
            echo -e "${GREEN}✓ Configuración Nginx creada${NC}"
            ;;
        *) echo -e "${YELLOW}Configuración manual requerida${NC}" ;;
    esac
    systemctl restart fail2ban
    log_action "Configuración web para $web_service"
    pause
}

config_services() {
    print_header "CONFIGURACIÓN SERVICIOS ESPECÍFICOS"
    echo "Servicios disponibles para proteger:"
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
[vsftpd]
enabled = true
port = ftp,ftp-data,ftps,ftps-data
filter = vsftpd
logpath = /var/log/vsftpd.log
maxretry = 3
bantime = 1h
EOF
            echo -e "${GREEN}✓ Configuración FTP creada${NC}"
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
[postfix-sasl]
enabled = true
port = smtp,465,submission,imap3,imaps,pop3,pop3s
filter = postfix-sasl
logpath = /var/log/mail.log
maxretry = 3
bantime = 1h
EOF
            echo -e "${GREEN}✓ Configuración Postfix creada${NC}"
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
            echo -e "${GREEN}✓ Configuración Dovecot creada${NC}"
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
            echo -e "${GREEN}✓ Configuración MySQL creada${NC}"
            ;;
        5) config_custom_port ;;
        6) return ;;
        *) echo -e "${YELLOW}Opción no válida${NC}" ;;
    esac
    if [[ $service_opt != 5 && $service_opt != 6 ]]; then
        systemctl restart fail2ban
        log_action "Configuración de servicio específico creada"
    fi
    pause
}

config_custom_port() {
    read -p "Introduce el puerto a proteger: " custom_port
    read -p "Nombre para la jail [custom-$custom_port]: " jail_name
    read -p "Archivo de log a monitorear [/var/log/auth.log]: " log_path
    jail_name=${jail_name:-custom-$custom_port}
    log_path=${log_path:-/var/log/auth.log}
    mkdir -p "$JAIL_DIR"
    cat > "$JAIL_DIR/$jail_name.conf" << EOF
[$jail_name]
enabled = true
port = $custom_port
filter = sshd
logpath = $log_path
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
    echo "Configuración actual en $JAIL_LOCAL:"
    grep -E "^(bantime|findtime|maxretry)" "$JAIL_LOCAL" 2>/dev/null || echo -e "${YELLOW}Usando valores por defecto${NC}"
    echo -e "\n${BLUE}Personalizar tiempos globales:${NC}"
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
    log_action "Tiempos globales actualizados: bantime=${def_bantime}m, findtime=${def_findtime}m, maxretry=$def_maxretry"
    pause
}

validate_config() {
    print_header "VALIDANDO CONFIGURACIÓN"
    echo -e "${BLUE}Verificando sintaxis...${NC}"
    if fail2ban-client -t; then
        echo -e "${GREEN}✓ Configuración válida${NC}"
    else
        echo -e "${RED}✗ Errores en la configuración${NC}"; return 1
    fi
    echo -e "\n${BLUE}Archivos de configuración encontrados:${NC}"
    ls -la /etc/fail2ban/jail.* /etc/fail2ban/jail.d/*.conf 2>/dev/null
    pause
}

reset_config() {
    print_header "RESETEAR CONFIGURACIÓN"
    echo -e "${RED}¡ATENCIÓN!${NC} Esto eliminará toda la configuración personalizada"
    read -p "¿Estás seguro? Escribe 'CONFIRMAR' para continuar: " confirm
    if [[ "$confirm" == "CONFIRMAR" ]]; then
        backup_dir="/root/fail2ban-backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$backup_dir"
        cp -r /etc/fail2ban/ "$backup_dir/"
        rm -f "$JAIL_LOCAL"
        rm -f "$JAIL_DIR"/*.conf
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

edit_jail() {
    print_header "EDICIÓN MANUAL"
    echo "Archivos disponibles para editar:"
    echo "1. $JAIL_LOCAL (configuración principal)"
    echo "2. Archivos en $JAIL_DIR/"
    echo "3. Crear nuevo archivo de jail"
    echo "4. Volver"
    read -p "Selecciona opción: " edit_opt
    case $edit_opt in
        1)
            if [[ -f "$JAIL_LOCAL" ]]; then nano "$JAIL_LOCAL"; systemctl restart fail2ban; echo -e "${GREEN}✓ Configuración actualizada${NC}"; else echo -e "${YELLOW}Archivo no encontrado${NC}"; fi
            ;;
        2)
            local conf_files=($(ls "$JAIL_DIR"/*.conf 2>/dev/null))
            if [[ ${#conf_files[@]} -eq 0 ]]; then echo -e "${YELLOW}No hay archivos de configuración personalizados${NC}"; return; fi
            echo "Archivos disponibles:"
            for i in "${!conf_files[@]}"; do echo "$((i+1)). $(basename "${conf_files[$i]}")"; done
            read -p "Selecciona archivo (número): " file_num
            if [[ $file_num -ge 1 && $file_num -le ${#conf_files[@]} ]]; then
                nano "${conf_files[$((file_num-1))]}"
                systemctl restart fail2ban
                echo -e "${GREEN}✓ Configuración actualizada${NC}"
            fi
            ;;
        3)
            read -p "Nombre del nuevo archivo (sin extensión): " new_file
            if [[ -n "$new_file" ]]; then
                touch "$JAIL_DIR/$new_file.conf"
                nano "$JAIL_DIR/$new_file.conf"
                systemctl restart fail2ban
                echo -e "${GREEN}✓ Nuevo archivo creado y configurado${NC}"
            fi
            ;;
        4) return ;;
        *) echo -e "${YELLOW}Opción no válida${NC}" ;;
    esac
    pause
}

# --- MONITOREO, HERRAMIENTAS Y UPDATE FILTERS ---
monitoring_menu() { pause; }
tools_menu() { update_filters; }

update_filters() {
    print_header "ACTUALIZAR FILTROS"
    echo -e "${BLUE}Actualizando sistema y Fail2Ban...${NC}"
    apt update
    if apt list --upgradable 2>/dev/null | grep -q fail2ban; then
        echo -e "${YELLOW}Actualización de Fail2Ban disponible${NC}"
        read -p "¿Actualizar Fail2Ban? [s/N]: " update_f2b
        if [[ $update_f2b =~ ^[Ss]$ ]]; then
            apt upgrade -y fail2ban
            echo -e "${GREEN}✓ Fail2Ban actualizado${NC}"
        fi
    else
        echo -e "${GREEN}✓ Fail2Ban ya está actualizado${NC}"
    fi
    echo -e "\n${BLUE}Filtros disponibles en el sistema:${NC}"
    ls /etc/fail2ban/filter.d/*.conf | wc -l | awk '{print "Total: " $1 " filtros"}'
    echo -e "\n${BLUE}Filtros más recientes (últimos 10):${NC}"
    ls -lt /etc/fail2ban/filter.d/*.conf | head -10 | awk '{print $9}' | xargs -I {} basename {} .conf
    echo -e "\n${CYAN}Filtros recomendados según servicios detectados:${NC}"
    if systemctl is-active --quiet nginx; then
        echo "- nginx-http-auth, nginx-limit-req, nginx-botsearch"
    fi
    if systemctl is-active --quiet apache2; then
        echo "- apache-auth, apache-badbots, apache-noscript, apache-overflows"
    fi
    if systemctl is-active --quiet ssh || systemctl is-active --quiet sshd; then
        echo "- sshd"
    fi
    if systemctl is-active --quiet proftpd || systemctl is-active --quiet vsftpd; then
        echo "- proftpd, vsftpd"
    fi
    if systemctl is-active --quiet postfix; then
        echo "- postfix, postfix-sasl"
    fi
    if systemctl is-active --quiet dovecot; then
        echo "- dovecot"
    fi
    echo -e "\n${BLUE}¿Deseas añadir algún filtro específico a una jail? Puedes hacerlo editando los archivos en ${YELLOW}/etc/fail2ban/jail.d/${NC}"
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
        echo "6. Gestión de IPs"
        echo "7. Monitorización y estadísticas"
        echo "8. Herramientas adicionales"
        echo "9. Salir"
        echo
        read -p "Selecciona opción: " main_opt
        case $main_opt in
            1) check_installed || install_fail2ban; pause ;;
            2) detect_env; pause ;;
            3) config_menu ;;
            4) show_status; check_function; pause ;;
            5) show_logs ;;
            6) manage_ips ;;
            7) monitoring_menu ;;
            8) tools_menu ;;
            9) echo -e "${GREEN}¡Hasta luego!${NC}"; exit 0 ;;
            *) echo -e "${YELLOW}Opción no válida${NC}" ;;
        esac
    done
}

# --- INICIO ---
detect_env
main_menu
