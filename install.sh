#!/bin/bash
set -e

# ========= COLORES =========
GREEN="\033[1;32m"
RED="\033[1;31m"
BLUE="\033[1;34m"
NC="\033[0m"

# ========= ROOT =========
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}❌ Ejecuta como root${NC}"
  exit 1
fi

# ========= INPUT =========
echo -e "${BLUE}===== VPN INSTALLER PRO =====${NC}"

read -p "🆔 Ingrese ID LXC: " CTID
read -p "💻 Ingrese Hostname: " HOSTNAME
read -s -p "🔑 Ingrese Password: " PASSWORD
echo ""

if [ -f "/etc/pve/lxc/$CTID.conf" ]; then
  echo -e "${RED}❌ CTID ya existe${NC}"
  exit 1
fi

# ========= CONFIG =========
BRIDGE="vmbr0"
REPO="https://raw.githubusercontent.com/SalasJtech/vpn-squid-installer/main"

# ========= TEMPLATE =========
echo "📦 Descargando template..."
pveam update >/dev/null
TEMPLATE=$(pveam available | grep debian-12 | tail -n 1 | awk '{print $2}')
pveam download local $TEMPLATE >/dev/null

# ========= CREAR LXC =========
echo "🚀 Creando LXC..."
pct create $CTID local:vztmpl/$TEMPLATE \
  --hostname $HOSTNAME \
  --password $PASSWORD \
  --cores 2 \
  --memory 1024 \
  --rootfs local-zfs:8 \
  --net0 name=eth0,bridge=$BRIDGE,ip=dhcp \
  --features nesting=1,keyctl=1 \
  --unprivileged 0

# ========= TUN =========
echo "🔧 Activando TUN..."
echo "lxc.cgroup2.devices.allow: c 10:200 rwm" >> /etc/pve/lxc/$CTID.conf
echo "lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file" >> /etc/pve/lxc/$CTID.conf

pct start $CTID
sleep 8

# ========= CONFIG LXC =========
pct exec $CTID -- bash <<'EOF'

apt update -qq
apt install -y -qq curl gnupg ca-certificates python3 python3-venv python3-pip openssh-server docker.io nginx

# LOCALE FIX
apt install -y locales
sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen >/dev/null

# SSH
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl enable ssh
systemctl restart ssh

# ========= VPN PROXY =========
mkdir -p /opt/vpn-proxy

cat > /opt/vpn-proxy/squid.conf <<EOL
http_port 3128
acl all src 0.0.0.0/0
http_access allow all
EOL

cat > proxy.pac <<EOL
EOL

# ========= RUN.SH =========
cat > run.sh <<EOL
#!/bin/bash
docker rm -f gluetun squid pac 2>/dev/null
EOL

chmod +x run.sh

# ========= PANEL =========
mkdir -p /opt/vpn-panel/templates

curl -sL https://raw.githubusercontent.com/SalasJtech/vpn-squid-installer/main/app.py -o /opt/vpn-panel/app.py
curl -sL https://raw.githubusercontent.com/SalasJtech/vpn-squid-installer/main/templates/index.html -o /opt/vpn-panel/templates/index.html

# VENV
python3 -m venv /opt/vpn-panel/venv
source /opt/vpn-panel/venv/bin/activate
pip install flask requests >/dev/null

# ========= SERVICES =========
# ---------- SYSTEMD ----------
cat > /etc/systemd/system/vpn-proxy.service <<EOL
[Unit]
Description=VPN Proxy
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/opt/vpn-proxy/run.sh
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOL

cat > /etc/systemd/system/vpn-panel.service <<EOL
[Unit]
Description=VPN Panel
After=network.target

[Service]
WorkingDirectory=/opt/vpn-panel
ExecStart=/opt/vpn-panel/venv/bin/python /opt/vpn-panel/app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload
systemctl enable vpn-proxy vpn-panel
systemctl start vpn-proxy vpn-panel

echo "✅ LXC CONFIGURADO"
EOF

# ========= IP =========
IP=$(pct exec $CTID -- sh -c "hostname -I | awk '{print \$1}'")

echo ""
echo -e "${GREEN}🎉 INSTALADO${NC}"
echo "🌐 Panel: http://$IP:5000"
echo "🌐 PAC:   http://$IP:8080/proxy.pac"
echo "🔐 SSH:   ssh root@$IP"
echo "🔑 PASS:  $PASSWORD"