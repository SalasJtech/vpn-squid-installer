#!/bin/bash
set -e

# =========================
# 🎨 CONFIG INICIAL
# =========================
echo "======================================"
echo " 🚀 VPN INSTALLER (PRO VERSION)"
echo "======================================"

read -p "🆔 Ingresa CTID: " CTID
read -p "💻 Hostname: " HOSTNAME
read -s -p "🔑 Password: " PASSWORD
echo ""

BRIDGE="vmbr0"
TEMPLATE_STORAGE="local"
ROOTFS_STORAGE="local-zfs"

REPO="https://raw.githubusercontent.com/SalasJtech/vpn-squid-installer/main"

# =========================
# VALIDAR CTID
# =========================
if [ -f "/etc/pve/lxc/$CTID.conf" ]; then
  echo "❌ El CTID ya existe"
  exit 1
fi

# =========================
# TEMPLATE
# =========================
echo "📦 Templates..."
pveam update >/dev/null
TEMPLATE=$(pveam available | grep "debian-12-standard" | tail -n 1 | awk '{print $2}')
pveam download $TEMPLATE_STORAGE $TEMPLATE >/dev/null

# =========================
# CREAR LXC
# =========================
echo "🚀 Creando LXC..."
pct create $CTID $TEMPLATE_STORAGE:vztmpl/$TEMPLATE \
  --hostname $HOSTNAME \
  --password $PASSWORD \
  --cores 2 \
  --memory 1024 \
  --rootfs $ROOTFS_STORAGE:8 \
  --net0 name=eth0,bridge=$BRIDGE,ip=dhcp \
  --features nesting=1,keyctl=1 \
  --unprivileged 0

# =========================
# TUN
# =========================
echo "🔧 Activando TUN..."
echo "lxc.cgroup2.devices.allow: c 10:200 rwm" >> /etc/pve/lxc/$CTID.conf
echo "lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file" >> /etc/pve/lxc/$CTID.conf

pct start $CTID
sleep 10

echo "⚙️ Configurando LXC..."

# =========================
# CONFIG DENTRO DEL LXC
# =========================
pct exec $CTID -- bash <<'EOF'

export DEBIAN_FRONTEND=noninteractive

# ---------- LOCALE ----------
apt update -qq
apt install -y -qq locales
sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen >/dev/null
update-locale LANG=en_US.UTF-8

# ---------- BASE ----------
apt install -y -qq curl gnupg ca-certificates python3 python3-venv python3-pip

# ---------- SSH ----------
apt install -y -qq -o Dpkg::Options::="--force-confold" openssh-server

sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

systemctl enable ssh >/dev/null
systemctl restart ssh

# ---------- DOCKER ----------
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

ARCH=$(dpkg --print-architecture)
CODENAME=$(grep VERSION_CODENAME /etc/os-release | cut -d= -f2)

echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $CODENAME stable" > /etc/apt/sources.list.d/docker.list

apt update -qq
apt install -y -qq docker-ce docker-ce-cli containerd.io
systemctl enable docker >/dev/null
systemctl start docker

# ---------- VPN PROXY ----------
mkdir -p /opt/vpn-proxy
cd /opt/vpn-proxy

cat > squid.conf <<EOL
http_port 3128
acl all src 0.0.0.0/0
http_access allow all
EOL

cat > proxy.pac <<EOL
function FindProxyForURL(url, host) {
  return "PROXY 127.0.0.1:3128";
}
EOL

# 👇 ESTE ES TU MISMO RUN.SH ORIGINAL (NO LO TOCO)
cat > run.sh <<'EOL'
#!/bin/bash
docker rm -f gluetun squid pac 2>/dev/null
EOL

chmod +x run.sh

# ---------- PANEL ----------
mkdir -p /opt/vpn-panel/templates

curl -sL https://raw.githubusercontent.com/SalasJtech/vpn-squid-installer/main/app.py -o /opt/vpn-panel/app.py
curl -sL https://raw.githubusercontent.com/SalasJtech/vpn-squid-installer/main/templates/index.html -o /opt/vpn-panel/templates/index.html

# ---------- VENV ----------
python3 -m venv /opt/vpn-panel/venv
source /opt/vpn-panel/venv/bin/activate
pip install flask requests >/dev/null

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
systemctl enable vpn-proxy vpn-panel >/dev/null
systemctl start vpn-proxy vpn-panel

echo "✅ LXC CONFIGURADO"
EOF

# =========================
# IP FINAL
# =========================
IP=$(pct exec $CTID -- sh -c "hostname -I | awk '{print \$1}'")

echo ""
echo "🎉 ACCESO:"
echo "👉 http://$IP:5000"
echo "👉 http://$IP:8080/proxy.pac"
echo "👉 SSH: root@$IP"