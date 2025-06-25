#!/bin/bash

# Script de Configuración de Seguridad para Debian 12
# Autor: Asistente Claude
# Versión: 1.0

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Directorios y archivos
BACKUP_DIR="/root/security_backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="/var/log/security_config.log"

# Función para logging
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Función para mostrar mensaje con color
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Función para pausar y esperar input del usuario
pause() {
    read -p "Presiona Enter para continuar..."
}

# Función para verificar si el script se ejecuta como root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_message $RED "Este script debe ejecutarse como root."
        exit 1
    fi
}

# Función para crear directorio de backups
create_backup_dir() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        mkdir -p "$BACKUP_DIR"
        log_message "Directorio de backups creado: $BACKUP_DIR"
    fi
}

# Función para hacer backup de configuraciones
create_backup() {
    local backup_name="backup_$TIMESTAMP"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    print_message $YELLOW "Creando backup de configuraciones..."
    
    mkdir -p "$backup_path"
    
    # Backup de configuraciones importantes
    cp -r /etc/ufw "$backup_path/ufw_backup" 2>/dev/null || true
    cp -r /etc/fail2ban "$backup_path/fail2ban_backup" 2>/dev/null || true
    cp /etc/ssh/sshd_config "$backup_path/sshd_config_backup" 2>/dev/null || true
    
    # Guardar estado actual de UFW
    ufw status verbose > "$backup_path/ufw_status.txt" 2>/dev/null || true
    
    # Guardar lista de servicios activos
    systemctl list-units --type=service --state=active > "$backup_path/active_services.txt"
    
    # Guardar puertos abiertos
    ss -tulpn > "$backup_path/open_ports.txt"
    
    echo "$backup_name" > "$BACKUP_DIR/latest_backup.txt"
    
    print_message $GREEN "Backup creado exitosamente: $backup_path"
    log_message "Backup creado: $backup_path"
}

# Función para restaurar backup
restore_backup() {
    if [[ ! -f "$BACKUP_DIR/latest_backup.txt" ]]; then
        print_message $RED "No hay backups disponibles."
        return 1
    fi
    
    print_message $CYAN "Backups disponibles:"
    ls -la "$BACKUP_DIR" | grep "backup_" | awk '{print NR". "$9}' | head -10
    
    echo ""
    read -p "Selecciona el número del backup a restaurar (0 para cancelar): " backup_choice
    
    if [[ "$backup_choice" == "0" ]]; then
        return 0
    fi
    
    backup_name=$(ls -la "$BACKUP_DIR" | grep "backup_" | awk '{print $9}' | sed -n "${backup_choice}p")
    
    if [[ -z "$backup_name" ]]; then
        print_message $RED "Selección inválida."
        return 1
    fi
    
    backup_path="$BACKUP_DIR/$backup_name"
    
    print_message $YELLOW "Restaurando backup: $backup_name"
    
    # Confirmar restauración
    read -p "¿Estás seguro de que quieres restaurar este backup? (s/N): " confirm
    if [[ ! "$confirm" =~ ^[Ss]$ ]]; then
        print_message $YELLOW "Restauración cancelada."
        return 0
    fi
    
    # Restaurar configuraciones
    if [[ -d "$backup_path/ufw_backup" ]]; then
        systemctl stop ufw 2>/dev/null || true
        rm -rf /etc/ufw
        cp -r "$backup_path/ufw_backup" /etc/ufw
        systemctl start ufw 2>/dev/null || true
        print_message $GREEN "Configuración UFW restaurada."
    fi
    
    if [[ -d "$backup_path/fail2ban_backup" ]]; then
        systemctl stop fail2ban 2>/dev/null || true
        rm -rf /etc/fail2ban
        cp -r "$backup_path/fail2ban_backup" /etc/fail2ban
        systemctl start fail2ban 2>/dev/null || true
        print_message $GREEN "Configuración Fail2Ban restaurada."
    fi
    
    if [[ -f "$backup_path/sshd_config_backup" ]]; then
        cp "$backup_path/sshd_config_backup" /etc/ssh/sshd_config
        systemctl restart ssh
        print_message $GREEN "Configuración SSH restaurada."
    fi
    
    log_message "Backup restaurado: $backup_name"
    print_message $GREEN "Restauración completada."
}

# Función para detectar red local
detect_local_network() {
    local_ip=$(ip route get 8.8.8.8 | grep -oP 'src \K\S+')
    local_network=$(ip route | grep "$local_ip" | grep -E "192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\." | head -1 | awk '{print $1}')
    
    if [[ -z "$local_network" ]]; then
        # Fallback: detectar basado en la IP local
        if [[ "$local_ip" =~ ^192\.168\. ]]; then
            local_network=$(echo "$local_ip" | cut -d. -f1-3).0/24
        elif [[ "$local_ip" =~ ^10\. ]]; then
            local_network="10.0.0.0/8"
        elif [[ "$local_ip" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]]; then
            local_network=$(echo "$local_ip" | cut -d. -f1-2).0.0/16
        else
            local_network="192.168.1.0/24"  # Default
        fi
    fi
    
    echo "$local_network"
}

# Función para escanear servicios activos
scan_active_services() {
    print_message $CYAN "Escaneando servicios activos..."
    
    # Servicios comunes y sus puertos
    declare -A services_ports
    services_ports[ssh]="22"
    services_ports[apache2]="80,443"
    services_ports[nginx]="80,443"
    services_ports[mysql]="3306"
    services_ports[mariadb]="3306"
    services_ports[postgresql]="5432"
    services_ports[redis]="6379"
    services_ports[mongodb]="27017"
    services_ports[ftp]="21"
    services_ports[vsftpd]="21"
    services_ports[proftpd]="21"
    services_ports[dovecot]="143,993,110,995"
    services_ports[postfix]="25,587"
    services_ports[bind9]="53"
    services_ports[named]="53"
    services_ports[samba]="139,445"
    services_ports[nfs]="2049"
    services_ports[docker]="2376"
    
    echo ""
    print_message $GREEN "=== SERVICIOS ACTIVOS DETECTADOS ==="
    
    active_services=()
    for service in "${!services_ports[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            ports="${services_ports[$service]}"
            print_message $GREEN "✓ $service (puerto(s): $ports)"
            active_services+=("$service:$ports")
        fi
    done
    
    # Detectar otros servicios escuchando en puertos
    print_message $CYAN "\n=== PUERTOS ABIERTOS DETECTADOS ==="
    ss -tulpn | grep LISTEN | while read line; do
        port=$(echo "$line" | grep -oP ':(\d+)' | tail -1 | cut -d: -f2)
        process=$(echo "$line" | grep -oP 'users:\(\(".*?"\)' | grep -oP '"\K[^"]+')
        if [[ -n "$port" && -n "$process" ]]; then
            print_message $BLUE "Puerto $port - Proceso: $process"
        fi
    done
    
    echo ""
}

# Función para sugerir servicios que se pueden instalar
suggest_services() {
    print_message $PURPLE "=== SERVICIOS SUGERIDOS PARA INSTALAR ==="
    
    suggest_list=()
    
    if ! systemctl is-active --quiet apache2 && ! systemctl is-active --quiet nginx; then
        suggest_list+=("nginx:80,443:Servidor web ligero y eficiente")
        suggest_list+=("apache2:80,443:Servidor web robusto")
    fi
    
    if ! systemctl is-active --quiet mysql && ! systemctl is-active --quiet mariadb; then
        suggest_list+=("mariadb-server:3306:Base de datos MySQL compatible")
    fi
    
    if ! systemctl is-active --quiet postgresql; then
        suggest_list+=("postgresql:5432:Base de datos PostgreSQL")
    fi
    
    if ! systemctl is-active --quiet vsftpd && ! systemctl is-active --quiet proftpd; then
        suggest_list+=("vsftpd:21:Servidor FTP seguro")
    fi
    
    if ! systemctl is-active --quiet redis; then
        suggest_list+=("redis-server:6379:Base de datos en memoria")
    fi
    
    for i in "${!suggest_list[@]}"; do
        IFS=':' read -r service ports description <<< "${suggest_list[$i]}"
        printf "%d. %-15s (Puerto: %-8s) - %s\n" $((i+1)) "$service" "$ports" "$description"
    done
    
    echo ""
}

# Función para instalar UFW
install_ufw() {
    if ! command -v ufw &> /dev/null; then
        print_message $YELLOW "Instalando UFW..."
        apt update
        apt install -y ufw
        log_message "UFW instalado"
    else
        print_message $GREEN "UFW ya está instalado."
    fi
}

# Función para configurar UFW
configure_ufw() {
    print_message $CYAN "=== CONFIGURACIÓN DE UFW ==="
    
    local_network=$(detect_local_network)
    print_message $BLUE "Red local detectada: $local_network"
    
    # Reset UFW si el usuario quiere empezar desde cero
    read -p "¿Quieres resetear la configuración de UFW? (s/N): " reset_ufw
    if [[ "$reset_ufw" =~ ^[Ss]$ ]]; then
        ufw --force reset
        print_message $YELLOW "UFW reseteado."
    fi
    
    # Política por defecto
    print_message $YELLOW "Configurando políticas por defecto..."
    ufw default deny incoming
    ufw default allow outgoing
    
    # Configurar SSH
    if systemctl is-active --quiet ssh || systemctl is-active --quiet sshd; then
        echo ""
        print_message $CYAN "Configuración SSH:"
        echo "1. Permitir SSH desde cualquier lugar (menos seguro)"
        echo "2. Permitir SSH solo desde red local (más seguro)"
        echo "3. Permitir SSH desde IP específica"
        read -p "Selecciona opción (1-3): " ssh_option
        
        case $ssh_option in
            1)
                ufw allow ssh
                print_message $GREEN "SSH permitido desde cualquier lugar."
                ;;
            2)
                ufw allow from "$local_network" to any port 22
                print_message $GREEN "SSH permitido solo desde red local ($local_network)."
                ;;
            3)
                read -p "Introduce la IP específica: " specific_ip
                ufw allow from "$specific_ip" to any port 22
                print_message $GREEN "SSH permitido desde $specific_ip."
                ;;
        esac
    fi
    
    # Configurar otros servicios activos
    for service_info in "${active_services[@]}"; do
        IFS=':' read -r service ports <<< "$service_info"
        
        if [[ "$service" != "ssh" && "$service" != "sshd" ]]; then
            echo ""
            print_message $CYAN "Configurar $service (puerto(s): $ports):"
            echo "1. Permitir desde cualquier lugar"
            echo "2. Permitir solo desde red local"
            echo "3. Permitir desde IP específica"
            echo "4. Denegar (mantener bloqueado)"
            read -p "Selecciona opción (1-4): " service_option
            
            IFS=',' read -ra port_array <<< "$ports"
            for port in "${port_array[@]}"; do
                case $service_option in
                    1)
                        ufw allow "$port"
                        print_message $GREEN "$service puerto $port permitido desde cualquier lugar."
                        ;;
                    2)
                        ufw allow from "$local_network" to any port "$port"
                        print_message $GREEN "$service puerto $port permitido solo desde red local."
                        ;;
                    3)
                        read -p "Introduce la IP específica para puerto $port: " specific_ip
                        ufw allow from "$specific_ip" to any port "$port"
                        print_message $GREEN "$service puerto $port permitido desde $specific_ip."
                        ;;
                    4)
                        print_message $YELLOW "$service puerto $port mantenido bloqueado."
                        ;;
                esac
            done
        fi
    done
    
    # Permitir actualizaciones del sistema
    print_message $CYAN "\nConfigurando acceso para actualizaciones del sistema..."
    ufw allow out 80/tcp
    ufw allow out 443/tcp
    ufw allow out 53
    print_message $GREEN "Actualizaciones del sistema permitidas (HTTP, HTTPS, DNS)."
    
    # Habilitar UFW
    print_message $YELLOW "Habilitando UFW..."
    ufw --force enable
    
    # Mostrar estado
    echo ""
    print_message $GREEN "=== ESTADO ACTUAL DE UFW ==="
    ufw status verbose
    
    log_message "UFW configurado y habilitado"
}

# Función para instalar Fail2Ban
install_fail2ban() {
    if ! command -v fail2ban-server &> /dev/null; then
        print_message $YELLOW "Instalando Fail2Ban..."
        apt update
        apt install -y fail2ban
        log_message "Fail2Ban instalado"
    else
        print_message $GREEN "Fail2Ban ya está instalado."
    fi
}

# Función para configurar Fail2Ban
configure_fail2ban() {
    print_message $CYAN "=== CONFIGURACIÓN DE FAIL2BAN ==="
    
    # Crear jail.local personalizado
    cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
# Configuración por defecto
bantime = 10m
findtime = 10m
maxretry = 5
backend = systemd

# Configuración de email (opcional)
# destemail = admin@tudominio.com
# sendername = Fail2Ban
# mta = sendmail

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 1h

EOF

    # Configurar jails adicionales basados en servicios activos
    for service_info in "${active_services[@]}"; do
        IFS=':' read -r service ports <<< "$service_info"
        
        case $service in
            apache2)
                cat >> /etc/fail2ban/jail.local << EOF
[apache-auth]
enabled = true
port = http,https
filter = apache-auth
logpath = /var/log/apache2/*error.log
maxretry = 3

[apache-badbots]
enabled = true
port = http,https
filter = apache-badbots
logpath = /var/log/apache2/*access.log
maxretry = 2

[apache-noscript]
enabled = true
port = http,https
filter = apache-noscript
logpath = /var/log/apache2/*access.log
maxretry = 3

EOF
                ;;
            nginx)
                cat >> /etc/fail2ban/jail.local << EOF
[nginx-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 3

[nginx-limit-req]
enabled = true
filter = nginx-limit-req
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 10

[nginx-botsearch]
enabled = true
filter = nginx-botsearch
port = http,https
logpath = /var/log/nginx/access.log
maxretry = 2

EOF
                ;;
            mysql|mariadb)
                cat >> /etc/fail2ban/jail.local << EOF
[mysqld-auth]
enabled = true
filter = mysqld-auth
port = 3306
logpath = /var/log/mysql/error.log
maxretry = 3

EOF
                ;;
            vsftpd|proftpd)
                cat >> /etc/fail2ban/jail.local << EOF
[vsftpd]
enabled = true
port = ftp,ftp-data,ftps,ftps-data
filter = vsftpd
logpath = /var/log/vsftpd.log
maxretry = 3

EOF
                ;;
        esac
    done
    
    # Permitir al usuario personalizar configuración
    echo ""
    read -p "¿Quieres personalizar la configuración de Fail2Ban? (s/N): " customize
    if [[ "$customize" =~ ^[Ss]$ ]]; then
        echo ""
        print_message $CYAN "Configuración personalizada:"
        
        read -p "Tiempo de baneo en minutos (por defecto 10): " bantime
        bantime=${bantime:-10}
        
        read -p "Ventana de tiempo para detectar intentos en minutos (por defecto 10): " findtime
        findtime=${findtime:-10}
        
        read -p "Máximo número de intentos antes del baneo (por defecto 5): " maxretry
        maxretry=${maxretry:-5}
        
        # Aplicar configuración personalizada
        sed -i "s/bantime = 10m/bantime = ${bantime}m/" /etc/fail2ban/jail.local
        sed -i "s/findtime = 10m/findtime = ${findtime}m/" /etc/fail2ban/jail.local
        sed -i "s/maxretry = 5/maxretry = ${maxretry}/" /etc/fail2ban/jail.local
        
        print_message $GREEN "Configuración personalizada aplicada."
    fi
    
    # Reiniciar y habilitar Fail2Ban
    systemctl enable fail2ban
    systemctl restart fail2ban
    
    # Mostrar estado
    sleep 2
    echo ""
    print_message $GREEN "=== ESTADO DE FAIL2BAN ==="
    fail2ban-client status
    
    log_message "Fail2Ban configurado y habilitado"
}

# Función para mostrar estado del sistema
show_system_status() {
    print_message $CYAN "=== ESTADO DEL SISTEMA DE SEGURIDAD ==="
    
    echo ""
    print_message $BLUE "Estado de UFW:"
    ufw status verbose
    
    echo ""
    print_message $BLUE "Estado de Fail2Ban:"
    systemctl is-active fail2ban && fail2ban-client status
    
    echo ""
    print_message $BLUE "Servicios de red activos:"
    ss -tulpn | grep LISTEN
    
    echo ""
    print_message $BLUE "Últimas líneas del log de seguridad:"
    tail -10 "$LOG_FILE" 2>/dev/null || echo "No hay logs disponibles"
}

# Función para mostrar menú principal
show_menu() {
    clear
    print_message $PURPLE "========================================"
    print_message $PURPLE "  CONFIGURADOR DE SEGURIDAD DEBIAN 12  "
    print_message $PURPLE "========================================"
    echo ""
    print_message $CYAN "1.  Escanear servicios del sistema"
    print_message $CYAN "2.  Instalar/Verificar UFW"
    print_message $CYAN "3.  Configurar UFW"
    print_message $CYAN "4.  Instalar/Verificar Fail2Ban"
    print_message $CYAN "5.  Configurar Fail2Ban"
    print_message $CYAN "6.  Configuración completa automática"
    print_message $CYAN "7.  Mostrar estado del sistema"
    print_message $CYAN "8.  Crear backup de configuración"
    print_message $CYAN "9.  Restaurar backup"
    print_message $CYAN "10. Ver logs del sistema"
    print_message $CYAN "11. Sugerir servicios para instalar"
    print_message $RED "0.  Salir"
    echo ""
    print_message $YELLOW "Selecciona una opción: "
}

# Función para configuración automática completa
auto_configure() {
    print_message $YELLOW "=== CONFIGURACIÓN AUTOMÁTICA COMPLETA ==="
    
    create_backup
    scan_active_services
    
    print_message $YELLOW "Instalando componentes necesarios..."
    install_ufw
    install_fail2ban
    
    print_message $YELLOW "Configurando UFW..."
    configure_ufw
    
    print_message $YELLOW "Configurando Fail2Ban..."
    configure_fail2ban
    
    print_message $GREEN "¡Configuración automática completada!"
    show_system_status
}

# Función principal
main() {
    check_root
    create_backup_dir
    
    while true; do
        show_menu
        read -r choice
        
        case $choice in
            1)
                scan_active_services
                pause
                ;;
            2)
                install_ufw
                pause
                ;;
            3)
                scan_active_services
                configure_ufw
                pause
                ;;
            4)
                install_fail2ban
                pause
                ;;
            5)
                configure_fail2ban
                pause
                ;;
            6)
                auto_configure
                pause
                ;;
            7)
                show_system_status
                pause
                ;;
            8)
                create_backup
                pause
                ;;
            9)
                restore_backup
                pause
                ;;
            10)
                print_message $CYAN "=== ÚLTIMOS LOGS ==="
                tail -20 "$LOG_FILE" 2>/dev/null || echo "No hay logs disponibles"
                pause
                ;;
            11)
                suggest_services
                pause
                ;;
            0)
                print_message $GREEN "¡Hasta luego!"
                exit 0
                ;;
            *)
                print_message $RED "Opción inválida. Inténtalo de nuevo."
                sleep 2
                ;;
        esac
    done
}

# Inicializar log
log_message "=== INICIO DEL SCRIPT DE CONFIGURACIÓN DE SEGURIDAD ==="

# Ejecutar función principal
main