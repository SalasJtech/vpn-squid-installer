# 🚀 VPN Squid Installer (Proxmox LXC)

Instalador automático de un contenedor LXC en Proxmox con:

* 🧠 Panel web (Flask)
* 🌐 VPN (Gluetun)
* 🔁 Proxy (Squid)
* 📄 PAC (Proxy Auto Config)
* 🐳 Docker integrado
* 🔐 Acceso SSH habilitado

---

## ⚡ Instalación rápida (1 comando)

Ejecuta en tu nodo Proxmox:

```bash
bash <(curl -sL https://raw.githubusercontent.com/SalasJtech/vpn-squid-installer/main/install.sh)
```

---

## 🧾 Configuración durante instalación

El script te pedirá:

* 🆔 **CTID** → ID del contenedor (ej: 101)
* 💻 **Hostname** → Nombre del contenedor
* 🔑 **Password** → Contraseña root del LXC

---

## 🖥️ Acceso al sistema

Al finalizar verás algo como:

```
🎉 ACCESO:
👉 http://IP:5000
👉 http://IP:8080/proxy.pac
👉 SSH: root@IP
```

### 🔹 Panel Web

```
http://IP:5000
```

### 🔹 PAC (Proxy automático)

```
http://IP:8080/proxy.pac
```

### 🔹 SSH

```bash
ssh root@IP
```

---

## ⚙️ Funcionalidades

### 🌐 VPN (Gluetun)

* Conexión a proveedores OpenVPN
* Aislamiento de tráfico
* Integración con Docker

### 🔁 Proxy Squid

* Puerto: `3128`
* Permite tráfico desde cualquier origen (editable)

### 📄 PAC

* Configuración automática de proxy
* Editable desde el panel

### 🧠 Panel Web

* Gestión de VPN
* Edición de PAC
* Control de dominios
* Interfaz simple y rápida

---

## 🐳 Contenedores Docker usados

* `gluetun` → VPN
* `squid` → Proxy
* `pac` → Servidor PAC

---

## 🔧 Servicios systemd

* `vpn-proxy` → Ejecuta contenedores Docker
* `vpn-panel` → Panel web Flask

---

## 🔄 Comandos útiles

### Ver contenedores

```bash
docker ps
```

### Reiniciar VPN

```bash
systemctl restart vpn-proxy
```

### Ver logs

```bash
journalctl -u vpn-proxy -f
```

---

## ⚠️ Requisitos

* Proxmox VE
* Acceso root
* Conexión a internet

---

## 🧠 Notas importantes

* El script crea un LXC **no privilegiado (full acceso)** para compatibilidad con Docker
* Se habilita `/dev/net/tun` automáticamente
* SSH permite login con contraseña

---

## 🚀 Futuras mejoras

* 🌍 Selección de país VPN
* 📊 Estado en tiempo real
* 🔐 Autenticación en panel
* 🔄 Auto-update

---

## 👨‍💻 Autor

Proyecto desarrollado por **SalasJTech**

---

## ⭐ Soporte

Si te funciona, deja una estrella ⭐ en el repo 😉


Luego de crear el lxc solo queda entrar a la interfaz web con la ip del lxc.  hhtp://IP_LXC:5000  y configurar VPN y PAC y ya dar al boton conectar de la vpn a usar.  
Se debe configurar en el router el WPAD para que sirva el pac a las PC y Dispositivos de toda la red automaticamente.
O tambien sin necesesidad de router se puede configurar proxy de manera manual en los dispositivos http://IP_LXC:8080/proxy.pac
