#!/bin/bash
set -e

# =========================
# 🎨 COLORES
# =========================
GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
NC="\033[0m"

# =========================
# 🔐 VALIDAR ROOT
# =========================
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}❌ Ejecuta como root${NC}"
  exit 1
fi

# =========================
# 🧾 INPUT USUARIO
# =========================
echo -e "${BLUE}======================================"
echo " 🚀 VPN PANEL INSTALLER (INTERACTIVO)"
echo "======================================${NC}"

read -p "🆔 Ingresa CTID (ej: 101): " CTID
read -p "💻 Hostname (ej: VPN-Gluetun): " HOSTNAME
read -s -p "🔑 Password root: " PASSWORD
echo ""

# =========================
# ⚠️ VALIDAR CTID
# =========================
if [ -f "/etc/pve/lxc/$CTID.conf" ]; then
  echo -e "${RED}❌ El CTID $CTID ya existe${NC}"
  exit 1
fi

# =========================
# ⚙️ CONFIG
# =========================
RAM=1024
CORES=2
DISK=8
BRIDGE="vmbr0"

REPO="https://raw.githubusercontent.com/SalasJtech/vpn-squid-installer/main"

# =========================
# 📦 TEMPLATE
# =========================
echo -e "${GREEN}📦 Descargando template...${NC}"
pveam update >/dev/null
TEMPLATE=$(pveam available | grep "debian-12-standard" | tail -n 1 | awk '{print $2}')
pveam download local $TEMPLATE >/dev/null

# =========================
# 🚀 CREAR LXC
# =========================
echo -e "${GREEN}🚀 Creando LXC con CTID $CTID...${NC}"
pct create $CTID local:vztmpl/$TEMPLATE \
  --hostname $HOSTNAME \
  --password $PASSWORD \
  --cores $CORES \
  --memory $RAM \
  --rootfs local-zfs:$DISK \
  --net0 name=eth0,bridge=$BRIDGE,ip=dhcp \
  --features nesting=1,keyctl=1 \
  --unprivileged 0

# =========================
# 🔌 TUN
# =========================
echo -e "${GREEN}🔧 Activando TUN...${NC}"
echo "lxc.cgroup2.devices.allow: c 10:200 rwm" >> /etc/pve/lxc/$CTID.conf
echo "lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file" >> /etc/pve/lxc/$CTID.conf

pct start $CTID
sleep 8

# =========================
# ⚙️ CONFIG LXC
# =========================
echo -e "${GREEN}⚙️ Configurando contenedor...${NC}"

pct exec $CTID -- bash -c "
apt update -qq

# LOCALES (fix warnings)
apt install -y -qq locales
sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen >/dev/null
update-locale LANG=en_US.UTF-8

# BASE + SSH
apt install -y -qq curl gnupg ca-certificates python3 python3-venv python3-pip openssh-server git

# SSH CONFIG
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl enable ssh >/dev/null
systemctl restart ssh

# DOCKER
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \$(. /etc/os-release && echo \$VERSION_CODENAME) stable\" > /etc/apt/sources.list.d/docker.list

apt update -qq
apt install -y -qq docker-ce docker-ce-cli containerd.io
systemctl enable docker >/dev/null
systemctl start docker

# PANEL
mkdir -p /opt/vpn-panel/templates

curl -sL \"$REPO/app.py\" -o /opt/vpn-panel/app.py
curl -sL \"$REPO/templates/index.html\" -o /opt/vpn-panel/templates/index.html

# VENV
python3 -m venv /opt/vpn-panel/venv
. /opt/vpn-panel/venv/bin/activate
pip install flask requests >/dev/null

# SERVICE
cat > /etc/systemd/system/vpn-panel.service <<EOF
[Unit]
Description=VPN Panel
After=network.target

[Service]
WorkingDirectory=/opt/vpn-panel
ExecStart=/opt/vpn-panel/venv/bin/python /opt/vpn-panel/app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vpn-panel >/dev/null
systemctl start vpn-panel
"

# =========================
# 🌐 IP FINAL
# =========================
IP=$(pct exec $CTID -- sh -c "hostname -I | awk '{print \$1}'")

# =========================
# 🎉 FINAL
# =========================
echo ""
echo -e "${GREEN}🎉 INSTALACIÓN COMPLETA${NC}"
echo "--------------------------------------"
echo -e "🆔 CTID:  ${BLUE}$CTID${NC}"
echo -e "🌐 Panel: ${BLUE}http://$IP:5000${NC}"
echo -e "🔐 SSH:   ${BLUE}ssh root@$IP${NC}"
echo -e "🔑 Pass:  ${YELLOW}$PASSWORD${NC}"
echo "--------------------------------------"