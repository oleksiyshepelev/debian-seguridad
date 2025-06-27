#!/bin/bash
# Configuración segura de UFW para servidor doméstico (solo LAN)
LAN_NET="192.168.1.0/24"

sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from $LAN_NET to any port 22 proto tcp
sudo ufw allow from $LAN_NET to any port 8443 proto tcp
sudo ufw allow from $LAN_NET to any port 80 proto tcp
sudo ufw allow from $LAN_NET to any port 8000 proto tcp
sudo ufw allow from $LAN_NET to any port 25565:25585 proto tcp
sudo ufw enable
sudo ufw status verbose
