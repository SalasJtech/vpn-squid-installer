from flask import Flask, render_template, request, redirect
import subprocess, json, uuid, time

app = Flask(__name__)

CONFIG_FILE = "/opt/vpn-panel/vpns.json"
PAC_CONFIG = "/opt/vpn-panel/pac_config.json"


def get_lxc_ip():
    try:
        ip = subprocess.getoutput("hostname -I").split()[0]
        return ip.strip()
    except:
        return "127.0.0.1"


# ---------- VPN CONFIG ----------
def load_vpns():
    try:
        return json.load(open(CONFIG_FILE))
    except:
        return {}


def save_vpns(data):
    json.dump(data, open(CONFIG_FILE, "w"), indent=4)


# ---------- PAC ----------
def load_pac():
    try:
        return json.load(open(PAC_CONFIG))
    except:
        return {}


def save_pac(data):
    json.dump(data, open(PAC_CONFIG, "w"), indent=4)


def generate_pac(data):
    blocks = []
    proxy = get_lxc_ip()  # 🔥 FIX

    for name, domains in data.items():
        rules = []
        for d in domains:
            if "*" in d:
                rules.append(f'shExpMatch(host, "{d}")')
            else:
                rules.append(f'dnsDomainIs(host, "{d}")')

        if rules:
            rules_text = " ||\n        ".join(rules)
            blocks.append(
                f"""
    // 🔥 {name}
    if (
        {rules_text}
    ) {{
        return "PROXY {proxy}:3128";
    }}"""
            )

    open("/opt/vpn-proxy/proxy.pac", "w").write(
        f"""function FindProxyForURL(url, host) {{
{''.join(blocks)}
    return "DIRECT";
}}"""
    )


# ---------- INFO ----------
def get_public_ip():
    return subprocess.getoutput("curl -s ifconfig.me")


def gluetun_running():
    return (
        subprocess.getoutput("docker inspect -f '{{.State.Running}}' gluetun") == "true"
    )


def gluetun_ip():
    try:
        if not gluetun_running():
            return ""
        for _ in range(5):
            ip = subprocess.getoutput(
                "docker exec gluetun sh -c 'cat /tmp/gluetun/ip 2>/dev/null'"
            )
            if ip:
                return ip.strip()
            time.sleep(1)
    except:
        return ""
    return ""


def get_vpn_ip():
    ip = gluetun_ip()
    if not ip:
        return "Conectando..." if gluetun_running() else "N/A"
    return ip


def get_country(ip):
    if not ip or ip in ["N/A", "Conectando..."]:
        return ""
    try:
        return subprocess.getoutput(f"curl -s ipinfo.io/{ip}/country")
    except:
        return ""


def vpn_status():
    if gluetun_running():
        return "🟢 VPN OK" if gluetun_ip() else "🟡 Conectando"
    return "🔴 Detenido"


def current_vpn():
    try:
        return open("/opt/vpn-proxy/current_vpn").read().strip()
    except:
        return "desconocido"


def get_containers_status():
    containers = ["gluetun", "squid", "pac"]
    status = {}

    for c in containers:
        try:
            running = subprocess.getoutput(
                f"docker inspect -f '{{{{.State.Running}}}}' {c} 2>/dev/null"
            )

            if running == "true":
                status[c] = {"state": "running", "label": "Activo"}
            else:
                status[c] = {"state": "stopped", "label": "Caído"}
        except:
            status[c] = {"state": "error", "label": "Error"}

    return status


# ---------- START ----------
def start_vpn(cfg, name):
    host, port = cfg["endpoint"].split(":")
    if not host.replace(".", "").isdigit():
        host = subprocess.getoutput(
            f"getent hosts {host} | awk '{{print $1}}' | head -n1"
        ).strip()

    cmd = f"""
docker rm -f gluetun squid pac 2>/dev/null

docker run -d --name gluetun --cap-add=NET_ADMIN \
-e VPN_SERVICE_PROVIDER=custom \
-e VPN_TYPE=wireguard \
-e WIREGUARD_PRIVATE_KEY="{cfg['private_key']}" \
-e WIREGUARD_ADDRESSES="{cfg['address']}" \
-e WIREGUARD_PUBLIC_KEY="{cfg['public_key']}" \
-e WIREGUARD_ENDPOINT_IP="{host}" \
-e WIREGUARD_ENDPOINT_PORT="{port}" \
-e WIREGUARD_ALLOWED_IPS="0.0.0.0/0,::/0" \
-e FIREWALL=on \
-p 3128:3128 \
qmcgaw/gluetun

sleep 8

docker run -d --name squid --network container:gluetun \
-v /opt/vpn-proxy/squid.conf:/etc/squid/squid.conf:ro ubuntu/squid

docker run -d --name pac -p 8080:80 \
-v /opt/vpn-proxy:/srv:ro -w /srv python -m http.server 80

echo "{name}" > /opt/vpn-proxy/current_vpn
"""
    subprocess.call(cmd, shell=True)


# ---------- ROUTES ----------
@app.route("/")
def index():
    return render_template(
        "index.html",
        vpns=load_vpns(),
        pac_data=load_pac(),
        public_ip=get_public_ip(),
        vpn_ip=get_vpn_ip(),
        current=current_vpn(),
        status=vpn_status(),
        gluetun=gluetun_running(),
        vpn_ip_raw=gluetun_ip(),
        containers=get_containers_status(),
    )


@app.route("/connect", methods=["POST"])
def connect():
    import subprocess

    print("🔥 CONNECT LLAMADO")

    if not request.json or "vpn" not in request.json:
        return {"status": "error", "msg": "No JSON recibido"}

    vpns = load_vpns()
    name = request.json["vpn"]

    if name not in vpns:
        return {"status": "error", "msg": "VPN no existe"}

    cfg = vpns[name]

    host, port = cfg["endpoint"].split(":")

    # 🔥 resolver dominio → IP
    if not host.replace(".", "").isdigit():
        host = subprocess.getoutput(
            f"getent hosts {host} | awk '{{print $1}}' | head -n1"
        ).strip()

    # 🔥 generar run.sh dinámico
    run_script = f"""#!/bin/bash

echo "🧹 Limpiando contenedores..."
docker rm -f gluetun squid pac 2>/dev/null

echo "🌐 Iniciando Gluetun..."

docker run -d \\
  --name gluetun \\
  --cap-add=NET_ADMIN \\
  -e VPN_SERVICE_PROVIDER=custom \\
  -e VPN_TYPE=wireguard \\
  -e WIREGUARD_PRIVATE_KEY="{cfg['private_key']}" \\
  -e WIREGUARD_ADDRESSES="{cfg['address']}" \\
  -e WIREGUARD_PUBLIC_KEY="{cfg['public_key']}" \\
  -e WIREGUARD_ENDPOINT_IP="{host}" \\
  -e WIREGUARD_ENDPOINT_PORT="{port}" \\
  -e WIREGUARD_ALLOWED_IPS="0.0.0.0/0,::/0" \\
  -e FIREWALL=on \\
  -p 3128:3128 \\
  qmcgaw/gluetun

sleep 8

echo "🦑 Iniciando Squid..."

docker run -d \\
  --name squid \\
  --network container:gluetun \\
  -v /opt/vpn-proxy/squid.conf:/etc/squid/squid.conf:ro \\
  ubuntu/squid

echo "📡 Iniciando PAC..."

docker run -d \\
  --name pac \\
  -p 8080:80 \\
  -v /opt/vpn-proxy:/srv:ro \\
  -w /srv \\
  python:3.12-alpine \\
  python -m http.server 80

echo "✅ TODO LEVANTADO"
"""

    # 🔥 guardar run.sh
    with open("/opt/vpn-proxy/run.sh", "w") as f:
        f.write(run_script)

    subprocess.call("chmod +x /opt/vpn-proxy/run.sh", shell=True)

    # 🔥 guardar VPN actual
    with open("/opt/vpn-proxy/current_vpn", "w") as f:
        f.write(name)

    # 🔥 reiniciar servicio (CLAVE)
    subprocess.call("systemctl restart vpn-proxy", shell=True)

    return {"status": "ok"}


@app.route("/status")
def status():
    vpn_ip = get_vpn_ip()
    public_ip = get_public_ip()
    return {
        "vpn_ip": vpn_ip,
        "vpn_country": get_country(vpn_ip),
        "public_ip": public_ip,
        "public_country": get_country(public_ip),
    }


@app.route("/save", methods=["POST"])
def save():
    vpns = load_vpns()
    data = request.json

    vid = data.get("id")

    vpn_data = {
        "name": data.get("display"),
        "private_key": data.get("private"),
        "address": data.get("address"),
        "public_key": data.get("public"),
        "endpoint": data.get("endpoint"),
    }

    if vid and vid in vpns:
        vpns[vid] = vpn_data
    else:
        import uuid

        vid = str(uuid.uuid4())
        vpns[vid] = vpn_data

    save_vpns(vpns)

    return {"status": "ok", "vpns": vpns}


@app.route("/delete", methods=["POST"])
def delete():
    vpns = load_vpns()
    vid = request.json.get("vpn")

    if vid in vpns:
        vpns.pop(vid)

    save_vpns(vpns)

    return {"status": "ok", "vpns": vpns}


@app.route("/block/add", methods=["POST"])
def add_block():
    d = load_pac()
    d[request.json["name"]] = []
    save_pac(d)
    generate_pac(d)
    return {"ok": True}


@app.route("/block/delete", methods=["POST"])
def del_block():
    d = load_pac()
    d.pop(request.json["block"], None)
    save_pac(d)
    generate_pac(d)
    return {"ok": True}


@app.route("/domain/add", methods=["POST"])
def add_domain():
    d = load_pac()
    d[request.json["block"]].append(request.json["domain"])
    save_pac(d)
    generate_pac(d)
    return {"ok": True}


@app.route("/domain/delete", methods=["POST"])
def del_domain():
    d = load_pac()
    d[request.json["block"]].remove(request.json["domain"])
    save_pac(d)
    generate_pac(d)
    return {"ok": True}


@app.route("/restart", methods=["POST"])
def restart():
    import subprocess  # 🔥 FIX

    cmds = [
        "docker rm -f gluetun squid pac",
        "ip link delete docker0 || true",
        "systemctl restart docker",
        "sleep 3",
        "/opt/vpn-proxy/run.sh",
    ]
    for c in cmds:
        subprocess.call(c, shell=True)
    return {"status": "ok"}


@app.route("/geo")
def geo():
    import requests

    ip = request.args.get("ip")

    try:
        if ip:
            url = f"https://ipwho.is/{ip}"
        else:
            url = "https://ipwho.is/"

        data = requests.get(url, timeout=5).json()

        return data
    except:
        return {"success": False}


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
