#!/bin/bash

# Script de instalación de fail2ban para Debian 12
# Verifica logging, instala dependencias y considera UFW

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para mostrar mensajes
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Verificar que se ejecuta como root
if [[ $EUID -ne 0 ]]; then
   print_error "Este script debe ejecutarse como root"
   exit 1
fi

# Verificar que es Debian 12
if ! grep -q "bookworm" /etc/os-release; then
    print_warning "Este script está optimizado para Debian 12 (bookworm)"
    read -p "¿Deseas continuar? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

print_status "Iniciando instalación de fail2ban en Debian 12..."

# Verificar si UFW está instalado y activo
print_status "Verificando estado de UFW..."
UFW_INSTALLED=false
UFW_ACTIVE=false

if command -v ufw >/dev/null 2>&1; then
    UFW_INSTALLED=true
    print_info "UFW está instalado"
    
    if ufw status | grep -q "Status: active"; then
        UFW_ACTIVE=true
        print_info "UFW está activo"
    else
        print_info "UFW está instalado pero inactivo"
    fi
else
    print_info "UFW no está instalado"
fi

# Verificar sistema de logging
print_status "Verificando sistema de logging..."
LOGGING_OK=true
RSYSLOG_INSTALLED=false
JOURNALCTL_AVAILABLE=false

# Verificar rsyslog
if systemctl is-active --quiet rsyslog 2>/dev/null; then
    RSYSLOG_INSTALLED=true
    print_info "rsyslog está activo"
else
    print_warning "rsyslog no está activo"
    LOGGING_OK=false
fi

# Verificar systemd-journald
if systemctl is-active --quiet systemd-journald 2>/dev/null; then
    JOURNALCTL_AVAILABLE=true
    print_info "systemd-journald está activo"
else
    print_warning "systemd-journald no está activo"
fi

# Verificar archivos de log críticos
print_status "Verificando archivos de log..."
if [[ ! -f /var/log/auth.log ]]; then
    print_warning "/var/log/auth.log no existe"
    LOGGING_OK=false
fi

if [[ ! -r /var/log/auth.log ]]; then
    print_warning "/var/log/auth.log no es legible"
    LOGGING_OK=false
fi

# Instalar dependencias si es necesario
print_status "Verificando e instalando dependencias..."
apt update

PACKAGES_TO_INSTALL=""

# Verificar e instalar rsyslog si no está
if ! $RSYSLOG_INSTALLED; then
    print_status "Instalando rsyslog..."
    PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL rsyslog"
fi

# Verificar iptables (necesario para fail2ban)
if ! command -v iptables >/dev/null 2>&1; then
    print_status "iptables no encontrado, agregando a la instalación..."
    PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL iptables"
fi

# Verificar python3 (requerido por fail2ban)
if ! command -v python3 >/dev/null 2>&1; then
    print_status "python3 no encontrado, agregando a la instalación..."
    PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL python3"
fi

# Instalar paquetes necesarios
if [[ -n "$PACKAGES_TO_INSTALL" ]]; then
    print_status "Instalando paquetes necesarios:$PACKAGES_TO_INSTALL"
    apt install -y $PACKAGES_TO_INSTALL
    
    # Reiniciar rsyslog si se instaló
    if echo "$PACKAGES_TO_INSTALL" | grep -q "rsyslog"; then
        systemctl enable rsyslog
        systemctl start rsyslog
        print_status "rsyslog instalado y configurado"
    fi
fi

# Instalar fail2ban
print_status "Instalando fail2ban..."
apt install -y fail2ban

# Crear directorio de configuración local si no existe
mkdir -p /etc/fail2ban/jail.d

# Determinar configuración según UFW
print_status "Configurando fail2ban..."

if $UFW_ACTIVE; then
    print_status "Configurando fail2ban para trabajar con UFW..."
    
    # Configuración específica para UFW
    cat > /etc/fail2ban/jail.d/debian12-ufw.conf << 'EOF'
[DEFAULT]
# Configuración para Debian 12 con UFW
bantime = 3600
findtime = 600
maxretry = 3
backend = systemd

# Configuración específica para UFW
banaction = ufw
banaction_allports = ufw

# Email notifications (opcional)
# destemail = admin@tudominio.com
# sender = fail2ban@tudominio.com
# action = %(action_mwl)s

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
action = ufw

# Para servicios web con UFW (descomenta si usas Apache/Nginx)
# [apache-auth]
# enabled = true
# port = http,https
# filter = apache-auth
# logpath = /var/log/apache*/*error.log
# maxretry = 6
# action = ufw

# [nginx-http-auth]
# enabled = true
# port = http,https
# filter = nginx-http-auth
# logpath = /var/log/nginx/error.log
# maxretry = 6
# action = ufw
EOF

    # Crear acción personalizada para UFW si no existe
    if [[ ! -f /etc/fail2ban/action.d/ufw.conf ]]; then
        print_status "Creando acción UFW personalizada..."
        cat > /etc/fail2ban/action.d/ufw.conf << 'EOF'
[Definition]

actionstart =

actionstop =

actioncheck =

actionban = ufw insert 1 deny from <ip> to any

actionunban = ufw delete deny from <ip> to any

[Init]
EOF
    fi

else
    print_status "Configurando fail2ban con iptables estándar..."
    
    # Configuración estándar con iptables
    cat > /etc/fail2ban/jail.d/debian12-standard.conf << 'EOF'
[DEFAULT]
# Configuración estándar para Debian 12
bantime = 3600
findtime = 600
maxretry = 3
backend = systemd

# Email notifications (opcional)
# destemail = admin@tudominio.com
# sender = fail2ban@tudominio.com
# action = %(action_mwl)s

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600

# Para servicios web (descomenta si usas Apache/Nginx)
# [apache-auth]
# enabled = true
# port = http,https
# filter = apache-auth
# logpath = /var/log/apache*/*error.log
# maxretry = 6

# [nginx-http-auth]
# enabled = true
# port = http,https
# filter = nginx-http-auth
# logpath = /var/log/nginx/error.log
# maxretry = 6
EOF
fi

# Verificar y corregir permisos de logs
print_status "Verificando permisos de archivos de log..."
if [[ -f /var/log/auth.log ]]; then
    chown root:adm /var/log/auth.log
    chmod 640 /var/log/auth.log
fi

# Habilitar y iniciar el servicio
print_status "Habilitando e iniciando fail2ban..."
systemctl enable fail2ban
systemctl start fail2ban

# Esperar un momento para que el servicio se inicie completamente
sleep 2

# Verificar estado del servicio
if systemctl is-active --quiet fail2ban; then
    print_status "fail2ban instalado y funcionando correctamente"
else
    print_error "Error al iniciar fail2ban"
    print_info "Verificando logs de error..."
    journalctl -u fail2ban --no-pager -l -n 10
    exit 1
fi

# Mostrar configuración aplicada
print_status "Configuración aplicada:"
echo "- Tiempo de baneo: 1 hora (3600 segundos)"
echo "- Intentos máximos: 3"
echo "- Ventana de tiempo: 10 minutos (600 segundos)"
echo "- Backend: systemd"
echo "- SSH protegido por defecto"

if $UFW_ACTIVE; then
    echo "- Integración con UFW: ACTIVADA"
    print_warning "Las reglas de fail2ban se aplicarán através de UFW"
else
    echo "- Usando iptables estándar"
fi

print_status "Comandos útiles de fail2ban:"
echo "- Ver estado: fail2ban-client status"
echo "- Ver jail SSH: fail2ban-client status sshd"
echo "- Desbanear IP: fail2ban-client set sshd unbanip <IP>"
echo "- Ver IPs baneadas: fail2ban-client get sshd banip"
echo "- Ver logs: journalctl -u fail2ban -f"

if $UFW_ACTIVE; then
    echo "- Ver reglas UFW: ufw status numbered"
fi

# Verificar configuración
print_status "Verificando configuración..."
if fail2ban-client reload; then
    print_status "Configuración recargada correctamente"
else
    print_error "Error al recargar configuración"
    exit 1
fi

# Mostrar estado final
print_status "Estado final de fail2ban:"
fail2ban-client status

print_status "¡Instalación completada exitosamente!"

if $UFW_ACTIVE; then
    print_warning "IMPORTANTE: fail2ban está configurado para trabajar con UFW"
    print_warning "Las IPs baneadas aparecerán como reglas UFW"
fi

print_warning "Recuerda:"
print_warning "- Configurar notificaciones por email si las necesitas"
print_warning "- Revisar la configuración en /etc/fail2ban/jail.d/"
print_warning "- Probar que el logging funciona correctamente"

# Verificación final de logging
print_status "Verificación final del sistema de logging..."
if tail -1 /var/log/auth.log >/dev/null 2>&1; then
    print_status "Sistema de logging funcionando correctamente"
else
    print_warning "Problema detectado con el sistema de logging"
    print_warning "Verifica manualmente: tail -f /var/log/auth.log"
fi

if ! $RSYSLOG_INSTALLED && $JOURNALCTL_AVAILABLE; then
    print_warning "Solo systemd-journald está activo. Considera configurar fail2ban para usar journald como backend y ajustar logpath."
fi