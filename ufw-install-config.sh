#!/bin/bash
# Configuración segura de UFW para servidor doméstico (solo LAN)
# Autor: Script mejorado para seguridad doméstica
# Fecha: $(date +%Y-%m-%d)

set -e  # Salir si hay algún error

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para logging
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[ADVERTENCIA] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Verificar si se ejecuta como root o con sudo
if [[ $EUID -eq 0 ]]; then
    SUDO=""
else
    SUDO="sudo"
    if ! sudo -n true 2>/dev/null; then
        error "Este script requiere permisos de administrador. Ejecuta con sudo."
    fi
fi

log "Iniciando configuración segura de UFW..."

# 1. Instalar UFW si no está instalado
if ! command -v ufw &> /dev/null; then
    warn "UFW no está instalado. Instalando..."
    if command -v apt &> /dev/null; then
        $SUDO apt update
        $SUDO apt install -y ufw
    elif command -v yum &> /dev/null; then
        $SUDO yum install -y ufw
    elif command -v dnf &> /dev/null; then
        $SUDO dnf install -y ufw
    elif command -v pacman &> /dev/null; then
        $SUDO pacman -S --noconfirm ufw
    else
        error "No se pudo detectar el gestor de paquetes. Instala UFW manualmente."
    fi
    log "UFW instalado correctamente"
else
    log "UFW ya está instalado"
fi

# 2. Detectar automáticamente la red LAN
log "Detectando red LAN automáticamente..."
LAN_NET=$(ip route | grep -E '^(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.)' | grep -v 'default' | head -1 | awk '{print $1}' 2>/dev/null || echo "")

# Fallback a red común si no se detecta
if [[ -z "$LAN_NET" ]]; then
    warn "No se pudo detectar automáticamente la red LAN"
    LAN_NET="192.168.1.0/24"
    warn "Usando red por defecto: $LAN_NET"
    read -p "¿Es correcta esta red? (s/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        read -p "Introduce tu red LAN (ej: 192.168.1.0/24): " LAN_NET
    fi
fi

# 3. Validar formato de red
if [[ ! $LAN_NET =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
    error "Formato de red no válido: $LAN_NET"
fi

info "Red LAN detectada: $LAN_NET"

# 4. Verificar conectividad antes de continuar
warn "IMPORTANTE: Asegúrate de tener acceso físico al servidor"
warn "Si pierdes conectividad SSH, necesitarás acceso local"
read -p "¿Continuar con la configuración? (s/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Ss]$ ]]; then
    info "Configuración cancelada por el usuario"
    exit 0
fi

# 5. Backup de configuración actual (si existe)
if [[ -d /etc/ufw ]]; then
    log "Creando backup de configuración actual..."
    $SUDO cp -r /etc/ufw /etc/ufw.backup.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
fi

# 6. Resetear UFW completamente
log "Reseteando configuración de UFW..."
$SUDO ufw --force reset

# 7. Configurar políticas por defecto
log "Configurando políticas por defecto..."
$SUDO ufw default deny incoming
$SUDO ufw default allow outgoing
$SUDO ufw default deny forward

# 8. Habilitar logging para auditoría
log "Habilitando logging de seguridad..."
$SUDO ufw logging on

# 9. Configurar reglas de acceso desde LAN
log "Configurando acceso SSH (puerto 22)..."
$SUDO ufw limit from $LAN_NET to any port 22 proto tcp comment 'SSH con límite de conexiones'

log "Configurando acceso HTTPS alternativo (puerto 8443)..."
$SUDO ufw allow from $LAN_NET to any port 8443 proto tcp comment 'HTTPS alternativo/Panel admin'

log "Configurando acceso HTTP (puerto 80)..."
$SUDO ufw allow from $LAN_NET to any port 80 proto tcp comment 'HTTP web server'

log "Configurando servidor de desarrollo (puerto 8000)..."
$SUDO ufw allow from $LAN_NET to any port 8000 proto tcp comment 'Servidor desarrollo'

log "Configurando rango Minecraft (puertos 25565-25585)..."
$SUDO ufw allow from $LAN_NET to any port 25565:25585 proto tcp comment 'Servidores Minecraft'

# 10. Reglas adicionales de seguridad
log "Configurando reglas adicionales de seguridad..."

# Permitir loopback (importante para aplicaciones locales)
$SUDO ufw allow in on lo
$SUDO ufw allow out on lo

# Bloquear intentos de fuerza bruta en otros puertos comunes
$SUDO ufw deny 23 comment 'Bloquear Telnet'
$SUDO ufw deny 135 comment 'Bloquear RPC'
$SUDO ufw deny 445 comment 'Bloquear SMB'

# 11. Habilitar UFW
log "Habilitando UFW..."
$SUDO ufw --force enable

# 12. Configurar UFW para iniciarse automáticamente
log "Configurando inicio automático..."
if command -v systemctl &> /dev/null; then
    $SUDO systemctl enable ufw
fi

# 13. Mostrar estado final
log "Configuración completada. Estado actual:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
$SUDO ufw status verbose
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 14. Mostrar información de puertos configurados
info "Puertos configurados para la red $LAN_NET:"
echo "  • 22    - SSH (con límite de conexiones)"
echo "  • 80    - HTTP"
echo "  • 8000  - Servidor de desarrollo"
echo "  • 8443  - HTTPS alternativo/Panel admin"
echo "  • 25565-25585 - Servidores Minecraft"

# 15. Mostrar comandos útiles
info "Comandos útiles para UFW:"
echo "  • Ver estado:          sudo ufw status verbose"
echo "  • Ver logs:            sudo tail -f /var/log/ufw.log"
echo "  • Deshabilitar:        sudo ufw disable"
echo "  • Eliminar regla:      sudo ufw delete [número]"
echo "  • Mostrar numerado:    sudo ufw status numbered"

# 16. Advertencias finales
warn "RECORDATORIOS IMPORTANTES:"
echo "  • Guarda este script para futuras modificaciones"
echo "  • Verifica que puedes conectarte vía SSH desde $LAN_NET"
echo "  • Los logs se guardan en /var/log/ufw.log"
echo "  • Backup creado en /etc/ufw.backup.* (si existía configuración previa)"

log "¡Configuración de UFW completada exitosamente!"