Características Principales:
🔍 Detección Inteligente del Sistema

Escanea automáticamente todos los servicios activos
Detecta puertos abiertos y procesos asociados
Identifica la red local automáticamente
Sugiere servicios que se pueden instalar

🛡️ Configuración de UFW

Instalación automática si no está presente
Configuración interactiva con opciones seguras
Permite SSH solo desde red local o IPs específicas
Mantiene acceso para actualizaciones del sistema
Configuración personalizada por servicio

🚫 Configuración de Fail2Ban

Instalación automática
Configuración de jails específicos según servicios detectados
Protección para SSH, Apache, Nginx, MySQL, FTP, etc.
Configuración personalizable de tiempos y intentos

💾 Sistema de Backup y Rollback

Backup automático antes de cambios
Restauración completa de configuraciones
Múltiples puntos de restauración
Logs detallados de todas las operaciones

Mejoras Adicionales Implementadas:

Interfaz Colorizada: Mejor experiencia visual con códigos de color
Logging Completo: Registro detallado de todas las operaciones
Menú Interactivo: Navegación fácil e intuitiva
Validaciones de Seguridad: Verificaciones antes de aplicar cambios
Configuración Modular: Puedes ejecutar solo las partes que necesites
Detección de Red Local: Configuración automática para redes privadas
Sugerencias Inteligentes: Recomienda servicios basados en el sistema actual

Uso del Script:
# Hacer ejecutable
chmod +x security_config.sh

# Ejecutar como root
sudo ./security_config.sh

Sugerencias de Uso:

Primera vez: Usa la opción 6 (Configuración automática completa)
Personalización: Usa las opciones individuales para ajustes específicos
Mantenimiento: Revisa regularmente el estado del sistema (opción 7)
Seguridad: Siempre crea backup antes de cambios importantes

Consideraciones de Seguridad:

El script detecta automáticamente tu red local para configuraciones seguras
SSH se puede restringir solo a la red local por defecto
Se mantiene acceso para actualizaciones del sistema
Fail2Ban se configura con reglas específicas por servicio
Todos los cambios se registran en logs para auditoría
