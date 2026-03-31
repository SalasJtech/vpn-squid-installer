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
bash <(curl -sL https://raw.githubusercontent.com/SalasJtech/vpn-proxy-manager/main/install.sh)
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

## 🌐 Configuración de red (Router, Windows y Móvil)

Para usar el proxy automáticamente en toda tu red, puedes configurar **WPAD / PAC** o hacerlo manualmente por dispositivo.

---

# 🧠 ¿Qué es PAC / WPAD?

* 📄 **PAC (Proxy Auto Config):** archivo que indica cuándo usar proxy
* 🌐 **WPAD:** permite que los dispositivos lo detecten automáticamente

Tu PAC está disponible en:

```text
http://IP:8080/proxy.pac
```

---

# 🌐 🔧 OPCIÓN 1: CONFIGURAR EN EL ROUTER (RECOMENDADO)

Esto permite que **todos los dispositivos de tu red usen el proxy automáticamente**.

## 📡 Método 1: DHCP (WPAD)

En tu router (o servidor DHCP):

1. Busca:

   * DHCP Options
   * Advanced DHCP

2. Agrega:

```text
Option 252 → http://IP:8080/proxy.pac
```

💥 Resultado:

* PCs y algunos móviles detectan el proxy automáticamente

---

## 🌍 Método 2: DNS (WPAD)

Crea un registro DNS:

```text
wpad → IP_DEL_SERVIDOR
```

Y asegúrate que el PAC esté disponible en:

```text
http://wpad/wpad.dat
```

💡 Puedes copiar tu PAC a:

```text
/opt/vpn-proxy/proxy.pac → /var/www/html/wpad.dat
```

---

# 💻 🪟 WINDOWS

## 🔹 Automático (WPAD)

1. Configuración → Red e Internet
2. Proxy
3. Activar:

```text
✔ Detectar configuración automáticamente
```

---

## 🔹 Manual (PAC)

1. Configuración → Red → Proxy
2. Activar:

```text
✔ Usar script de configuración
```

3. URL:

```text
http://IP:8080/proxy.pac
```

---

## 🔹 Manual (Proxy directo)

```text
IP:  IP_DEL_SERVIDOR
PORT: 3128
```

---

# 📱 ANDROID

## 🔹 WiFi → Editar red

1. Mantén presionada tu red WiFi
2. Modificar red
3. Opciones avanzadas

---

### ✔ PAC:

```text
Proxy → Auto
PAC URL → http://IP:8080/proxy.pac
```

---

### ✔ Manual:

```text
Proxy → Manual
Host → IP
Puerto → 3128
```

---

# 🍎 iPhone (iOS)

1. Ajustes → WiFi
2. Selecciona tu red
3. Configurar proxy

---

### ✔ PAC:

```text
Automático → http://IP:8080/proxy.pac
```

---

### ✔ Manual:

```text
Servidor → IP
Puerto → 3128
```

---

# 🧪 PRUEBA DE FUNCIONAMIENTO

Después de configurar:

1. Abre:

```text
https://ipinfo.io
```

2. Verifica que la IP sea la del VPN

---

# ⚠️ NOTAS IMPORTANTES

* Algunos routers de ISP NO permiten opción 252
* iPhone no soporta WPAD automático → usar PAC manual
* Android sí soporta PAC en WiFi
* Windows funciona perfecto con WPAD

---

# 🔥 RECOMENDACIÓN

👉 Usa **DHCP Option 252 + PAC**

Es:

✔ automático
✔ limpio
✔ sin tocar cada dispositivo

---

# 🚀 TIP PRO

Si quieres que funcione aún mejor:

* Usa dominio interno:

```text
http://proxy.local/proxy.pac
```

* Configura DNS interno en tu router

---

## 👨‍💻 Autor

Proyecto desarrollado por **SalasJTech**

---

## ⭐ Soporte

Si te funciona, deja una estrella ⭐ en el repo 😉

