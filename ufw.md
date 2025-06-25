Aquí tienes los comandos básicos para gestionar las reglas de UFW (Uncomplicated Firewall) en Ubuntu/Debian:

---

## 1. Ver las reglas actuales

* **Listado simple**

  ```bash
  sudo ufw status
  ```

  Muestra las reglas activas en formato legible (ALLOW/DENY).

* **Listado numerado**

  ```bash
  sudo ufw status numbered
  ```

  Muestra cada regla con un índice, muy útil para referirte a ellas al eliminarlas o modificarlas.

---

## 2. Añadir nuevas reglas

* **Permitir tráfico en un puerto**

  ```bash
  sudo ufw allow 80/tcp
  ```

  Permite HTTP (puerto 80 TCP).

* **Denegar tráfico desde una IP concreta**

  ```bash
  sudo ufw deny from 203.0.113.5
  ```

  Bloquea todo el tráfico proveniente de esa IP.

* **Permitir solo SSH desde una red**

  ```bash
  sudo ufw allow from 192.168.1.0/24 to any port 22 proto tcp
  ```

  Solo máquinas de la subred 192.168.1.0/24 pueden usar SSH.

---

## 3. Modificar reglas existentes

UFW no edita reglas “in-place”; hay que borrarlas y volverlas a crear:

1. Listar reglas numeradas

   ```bash
   sudo ufw status numbered
   ```
2. Eliminar la regla a modificar (por ejemplo, regla \[3])

   ```bash
   sudo ufw delete 3
   ```
3. Crear la regla corregida

   ```bash
   sudo ufw allow from 10.0.0.0/8 to any port 22 proto tcp
   ```

> **Tip:** si solo quieres cambiar el orden de evaluación de las reglas (por ejemplo, dar prioridad a una nueva), puedes usar `ufw insert`:
>
> ```bash
> sudo ufw insert 1 allow 22/tcp
> ```
>
> Esto inserta la regla al principio (posición 1).

---

## 4. Ajustes avanzados manuales

Si necesitas configurar cosas más complejas (limites de conexiones, logging avanzado, etc.), puedes editar directamente:

```bash
sudo nano /etc/ufw/user.rules
```

Tras guardar, recarga UFW para aplicar los cambios:

```bash
sudo ufw reload
```

---

## 5. Otros comandos útiles

* **Habilitar/deshabilitar UFW**

  ```bash
  sudo ufw enable
  sudo ufw disable
  ```
* **Reiniciar UFW (desactiva y activa)**

  ```bash
  sudo ufw reload
  ```
* **Ver configuración detallada**

  ```bash
  sudo ufw show raw
  ```

Con estos pasos podrás **ver**, **añadir**, **eliminar** y **modificar** tus reglas de UFW de forma segura y ordenada.
