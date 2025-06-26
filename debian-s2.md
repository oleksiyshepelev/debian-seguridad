Nuevas Funcionalidades:
1. Menú de Comandos UFW (Opción 8)

Ver estado detallado y numerado
Habilitar/deshabilitar UFW
Resetear configuración
Agregar/eliminar reglas personalizadas
Ver logs de UFW
Configurar políticas por defecto
Gestionar aplicaciones predefinidas
Comandos UFW personalizados

2. Menú de Comandos Fail2Ban (Opción 9)

Ver estado general y jails activos
Ver estado de jails específicos
Ver IPs baneadas
Desbanear/banear IPs manualmente
Recargar configuración
Reiniciar Fail2Ban
Ver logs
Habilitar/deshabilitar jails
Comandos Fail2Ban personalizados

3. Herramientas de Red y Escaneo (Opción 10)

Instalación automática de nmap
Escaneos básicos y avanzados:

Escaneo de puertos rápido (nmap -F)
Escaneo de red local (nmap -sn)
Escaneo de servicios y versiones (nmap -sV)
Escaneo de vulnerabilidades (nmap --script vuln)


Comandos de red básicos:

Conexiones activas (ss -tuln, ss -tp)
Tabla de rutas (ip route)
Información de interfaces (ip addr)
Ping y traceroute
Verificación de puertos locales
Verificación DNS (nslookup, dig)



4. Mejoras en el Menú Principal

Organización por categorías (Básica, Avanzada, Gestión)
Numeración más clara
Versión 2.0 indicada

Comandos Útiles Incluidos:
UFW:
ufw status verbose
ufw status numbered
ufw allow/deny [puerto/regla]
ufw delete [número]
ufw app list

Fail2Ban:
fail2ban-client status
fail2ban-client status [jail]
fail2ban-client set [jail] unbanip [IP]
fail2ban-client set [jail] banip [IP]
fail2ban-client reload

Nmap:
nmap -F [host]           # Escaneo rápido
nmap -sn [red]           # Descubrimiento de hosts
nmap -sV [host]          # Detección de versiones
nmap --script vuln [host] # Escaneo de vulnerabilidades

Comandos de Red:
ss -tulpn                # Puertos abiertos
ip route                 # Tabla de rutas
ip addr show             # Interfaces
ping/traceroute          # Conectividad
nslookup/dig             # DNS

El script ahora es mucho más completo y funcional, permitiendo tanto configuración automática como control manual granular de UFW y Fail2Ban, además de incluir herramientas profesionales de diagnóstico de red.