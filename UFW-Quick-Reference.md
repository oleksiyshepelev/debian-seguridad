# (UFW) Quick Reference

Este README reúne los comandos y flujos de trabajo básicos para **ver**, **añadir**, **modificar** y **eliminar** reglas en UFW, el firewall simplificado de Ubuntu/Debian.

## 1. Ver reglas

* **Listado legible**

  ```bash
  sudo ufw status
  ```
* **Listado numerado**

  ```bash
  sudo ufw status numbered
  ```

  Muestra cada regla con un índice para usarse en eliminaciones o modificaciones.

## 2. Añadir reglas

* **Permitir puerto/tipo**

  ```bash
  sudo ufw allow 80/tcp
  ```
* **Denegar por IP**

  ```bash
  sudo ufw deny from 203.0.113.5
  ```
* **Permitir SSH solo a subred**

  ```bash
  sudo ufw allow from 192.168.1.0/24 to any port 22 proto tcp
  ```

## 3. Modificar reglas

UFW no edita “in-place”: se elimina la regla numerada y se crea una nueva.

1. Ver índice:

   ```bash
   sudo ufw status numbered
   ```
2. Eliminar regla #3:

   ```bash
   sudo ufw delete 3
   ```
3. Añadir la regla corregida:

   ```bash
   sudo ufw allow from 10.0.0.0/8 to any port 22 proto tcp
   ```

> **Tip:** usa `ufw insert N` para colocar una regla en la posición N (cambia orden):
>
> ```bash
> sudo ufw insert 1 allow 22/tcp
> ```

## 4. Gestión avanzada

* **Archivo manual**
  Edita `/etc/ufw/user.rules` y luego:

  ```bash
  sudo ufw reload
  ```
* **Habilitar / Deshabilitar**

  ```bash
  sudo ufw enable
  sudo ufw disable
  ```
* **Raw iptables**

  ```bash
  sudo ufw show raw
  ```

## 5. Flujo de trabajo sugerido

1. `sudo ufw status numbered`
2. Añade o elimina reglas según necesidad
3. Comprueba de nuevo con `sudo ufw status`
4. Si editas manualmente, recarga con `sudo ufw reload`

