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
# 🔍 AUTO CTID
# =========================
if [ -z "$CTID" ]; then
  for i in $(seq 100 999); do
    if ! pct status $i &>/dev/null; then
      CTID=$i
      break
    fi
  done
fi

echo -e "${GREEN}🆔 Usando CTID: $CTID${NC}"

# =========================
# ⚙️ DEFAULTS
# =========================

HOSTNAME="VPN-Gluetun"
PASSWORD="246800"
BRIDGE="vmbr0"
RAM=1024
CORES=2
DISK=8

REPO="https://raw.githubusercontent.com/SalasJtech/vpn-squid-installer/main"

# =========================
# 📥 ARGUMENTOS
# =========================
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --ctid) CTID="$2"; shift ;;
    --ram) RAM="$2"; shift ;;
    --cores) CORES="$2"; shift ;;
    --disk) DISK="$2"; shift ;;
  esac
  shift
done

# =========================
# 🔍 VALIDACIONES
# =========================
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}❌ Ejecuta como root${NC}"
  exit 1
fi

# =========================
# 🚀 INICIO
# =========================
clear
echo -e "${BLUE}"
echo "======================================"
echo " 🚀 VPN PANEL INSTALLER (HELPER PRO)"
echo "======================================"
echo -e "${NC}"

sleep 1

# =========================
# 📦 TEMPLATE
# =========================
echo -e "${GREEN}📦 Descargando template...${NC}"
pveam update >/dev/null
TEMPLATE=$(pveam available | grep "debian-12-standard" | tail -n 1 | awk '{print $2}')
pveam download local $TEMPLATE >/dev/null

# =========================
# 🧱 CREAR LXC
# =========================
echo -e "${GREEN}🚀 Creando LXC...${NC}"
pct create $CTID local:vztmpl/$TEMPLATE \
  --hostname $HOSTNAME \
  --password $PASSWORD \
  --cores $CORES \
  --memory $RAM \
  --rootfs local-zfs:$DISK \
  --net0 name=eth0,bridge=$BRIDGE,ip=dhcp \
  --features nesting=1,keyctl=1 \
  --unprivileged 0 >/dev/null

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
apt install -y -qq curl gnupg ca-certificates python3 python3-venv python3-pip openssh-server git

# SSH
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl enable ssh >/dev/null
systemctl restart ssh

# Docker
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \$(. /etc/os-release && echo \$VERSION_CODENAME) stable\" > /etc/apt/sources.list.d/docker.list

apt update -qq
apt install -y -qq docker-ce docker-ce-cli containerd.io
systemctl enable docker >/dev/null
systemctl start docker

# Carpetas
mkdir -p /opt/vpn-panel/templates

# Descargar panel desde GitHub
curl -sL $REPO/app.py -o /opt/vpn-panel/app.py
curl -sL $REPO/index.html -o /opt/vpn-panel/templates/index.html

# VENV
python3 -m venv /opt/vpn-panel/venv
source /opt/vpn-panel/venv/bin/activate
pip install flask requests >/dev/null

# SYSTEMD
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

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable vpn-panel >/dev/null
systemctl start vpn-panel
"

# =========================
# 🌐 IP FINAL
# =========================
IP=$(pct exec $CTID -- hostname -I | awk '{print $1}')

# =========================
# 🎉 FINAL
# =========================
echo ""
echo -e "${GREEN}🎉 INSTALACIÓN COMPLETA${NC}"
echo "--------------------------------------"
echo -e "🌐 Panel: ${BLUE}http://$IP:5000${NC}"
echo -e "🔐 SSH:   ${BLUE}ssh root@$IP${NC}"
echo -e "🔑 Pass:  ${YELLOW}$PASSWORD${NC}"
echo "--------------------------------------"