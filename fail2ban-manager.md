# fail2ban-manager.sh

**fail2ban-manager.sh** es un script interactivo para instalar, configurar y administrar Fail2Ban en Debian 12+ y Ubuntu.

---

## Características

- Menú interactivo fácil de usar
- Instalación automática de Fail2Ban si no está presente
- Detección de entorno (servidor o desktop)
- Configuración guiada de jails para servicios comunes (SSH, web, FTP, correo, MySQL, puertos personalizados)
- Gestión de IPs: banear, desbanear, whitelist, limpiar baneos
- Consulta de logs y estado de Fail2Ban
- Edición, validación y reseteo de configuración
- Actualización y gestión de filtros de Fail2Ban
- Seguro para equipos detrás de NAT o en red local

---

## Requisitos

- Debian 12, Ubuntu 22.04 o superior
- Ejecutar como **root** (usa `sudo`)

---

## Uso

1. Copia el archivo `fail2ban-manager.sh` en tu servidor.
2. Dale permisos de ejecución:

   ```bash
   chmod +x fail2ban-manager.sh
