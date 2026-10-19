#!/usr/bin/env bash
# Dedicated Ubuntu 24.04 VPS, run as root. Never prints generated credentials.
set -euo pipefail
umask 077

if [[ "$(id -u)" != 0 ]] || [[ "$(. /etc/os-release; echo "$ID:$VERSION_ID")" != 'ubuntu:24.04' ]]; then
  echo 'Este instalador requer root no Ubuntu 24.04.' >&2
  exit 2
fi

export DEBIAN_FRONTEND=noninteractive
if systemctl is-active --quiet nginx 2>/dev/null &&
   ! grep -q 'proxy_pass http://127.0.0.1:8765' /etc/nginx/sites-available/default 2>/dev/null; then
  echo 'Nginx já está em uso por outro site. Revise a VPS antes de substituir a configuração.' >&2
  exit 4
fi
apt-get update -qq >/dev/null
apt-get install -y -qq ca-certificates curl nginx coturn python3-venv ufw >/dev/null

install -d -m 0700 /etc/dante-live
chmod 0711 /etc/dante-live
chmod 0755 /opt/dante-live
install -d -m 0755 /var/www/dante-live-acme
install -d -m 0755 /usr/local/libexec
if [[ -f /etc/nginx/sites-available/default && ! -f /etc/dante-live/nginx-default.before-dante-live ]]; then
  cp -p /etc/nginx/sites-available/default /etc/dante-live/nginx-default.before-dante-live
  chmod 0600 /etc/dante-live/nginx-default.before-dante-live
fi
python3 -m venv /opt/dante-live-certbot
/opt/dante-live-certbot/bin/pip install --disable-pip-version-check -q 'certbot>=5.4,<7' >/dev/null

public_ip="${DANTE_LIVE_PUBLIC_IP:-}"
if [[ -z "$public_ip" ]]; then
  public_ip="$(curl -fsS --connect-timeout 5 http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address)"
fi
if ! DANTE_LIVE_PUBLIC_IP="$public_ip" python3 - <<'PY'
import ipaddress, os
value = ipaddress.ip_address(os.environ['DANTE_LIVE_PUBLIC_IP'])
raise SystemExit(0 if value.version == 4 and value.is_global else 1)
PY
then
  echo 'A VPS precisa de um IPv4 público.' >&2
  exit 3
fi

if [[ ! -f /etc/dante-live/private.json ]]; then
  DANTE_LIVE_PUBLIC_IP="$public_ip" python3 - <<'PY'
import json, os, secrets
path = '/etc/dante-live/private.json'
value = {
    'public_ip': os.environ['DANTE_LIVE_PUBLIC_IP'],
    'connection_token': secrets.token_urlsafe(48),
    'turn_secret': secrets.token_hex(48),
}
with open(path, 'x', encoding='utf-8') as output:
    json.dump(value, output)
    output.write('\n')
os.chmod(path, 0o600)
PY
fi

if ! id -u dante-live >/dev/null 2>&1; then
  useradd --system --home /nonexistent --shell /usr/sbin/nologin dante-live
fi
chown dante-live:dante-live /etc/dante-live/private.json
chmod 0600 /etc/dante-live/private.json
python3 - <<'PY'
import json, os
from pathlib import Path
config = json.loads(Path('/etc/dante-live/private.json').read_text())
Path('/etc/dante-live/connection.json').write_text(json.dumps({
    'server': 'https://' + config['public_ip'],
    'httpsPort': 443,
    'connectionToken': config['connection_token'],
    'protocol': 2,
}, indent=2) + '\n')
os.chmod('/etc/dante-live/connection.json', 0o600)
PY

install -m 0755 /opt/dante-live/turn-api.py /usr/local/libexec/dante-live-turn-api.py
install -d -o dante-live -g dante-live -m 0755 /opt/dante-live/GuestWeb
cat > /etc/systemd/system/dante-live-turn-api.service <<'EOF'
[Unit]
Description=Dante Live authenticated temporary TURN credentials
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
User=dante-live
Group=dante-live
ExecStart=/usr/bin/python3 /usr/local/libexec/dante-live-turn-api.py
Restart=always
RestartSec=3
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
[Install]
WantedBy=multi-user.target
EOF

cat > /usr/local/sbin/dante-live-cert-deploy <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
umask 077
public_ip="$(python3 -c 'import json; print(json.load(open("/etc/dante-live/private.json"))["public_ip"])')"
install -o root -g turnserver -m 0640 "/etc/letsencrypt/live/$public_ip/privkey.pem" /etc/dante-live/turn-privkey.pem
install -o root -g turnserver -m 0644 "/etc/letsencrypt/live/$public_ip/fullchain.pem" /etc/dante-live/turn-fullchain.pem
systemctl try-restart coturn.service >/dev/null
systemctl reload nginx.service >/dev/null 2>&1 || true
EOF
chmod 0700 /usr/local/sbin/dante-live-cert-deploy

ssh_port="$(sshd -T 2>/dev/null | awk '$1 == "port" && !found {print $2; found=1}')"
ssh_port="${ssh_port:-22}"
ufw allow OpenSSH >/dev/null
ufw allow "${ssh_port}/tcp" >/dev/null
ufw allow 80/tcp >/dev/null
ufw allow 443/tcp >/dev/null
ufw allow 3478/tcp >/dev/null
ufw allow 3478/udp >/dev/null
ufw allow 5349/tcp >/dev/null
ufw allow 49160:49200/udp >/dev/null
ufw --force enable >/dev/null

if [[ ! -f "/etc/letsencrypt/live/$public_ip/fullchain.pem" ]]; then
  systemctl stop nginx.service >/dev/null 2>&1 || true
  /opt/dante-live-certbot/bin/certbot certonly --standalone --non-interactive --agree-tos \
    --register-unsafely-without-email --preferred-profile shortlived \
    --ip-address "$public_ip" >/dev/null
fi

python3 - <<'PY'
import json, os
from pathlib import Path
v = json.loads(Path('/etc/dante-live/private.json').read_text())
ip = v['public_ip']
nginx = '''server {
    listen 80 default_server;
    server_name _;
    location /.well-known/acme-challenge/ { root /var/www/dante-live-acme; }
    location / { return 308 https://$host$request_uri; }
}
server {
    listen 443 ssl default_server;
    server_name _;
    ssl_certificate /etc/letsencrypt/live/IP/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/IP/privkey.pem;
    client_max_body_size 100k;
    add_header Strict-Transport-Security "max-age=31536000" always;
    location /api/ {
        proxy_pass http://127.0.0.1:8765;
        proxy_set_header Host $host;
        proxy_read_timeout 30s;
    }
    location / {
        proxy_pass http://127.0.0.1:8765;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 35s;
    }
}
'''.replace('IP', ip)
Path('/etc/nginx/sites-available/default').write_text(nginx)
turn = '''fingerprint
use-auth-secret
static-auth-secret=SECRET
realm=IP
server-name=IP
listening-port=3478
tls-listening-port=5349
min-port=49160
max-port=49200
cert=/etc/dante-live/turn-fullchain.pem
pkey=/etc/dante-live/turn-privkey.pem
user-quota=8
total-quota=32
max-bps=2000000
no-cli
no-loopback-peers
no-multicast-peers
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
denied-peer-ip=192.168.0.0-192.168.255.255
denied-peer-ip=169.254.0.0-169.254.255.255
'''.replace('SECRET', v['turn_secret']).replace('IP', ip)
Path('/etc/turnserver.conf').write_text(turn)
os.chown('/etc/turnserver.conf', 0, __import__('grp').getgrnam('turnserver').gr_gid)
Path('/etc/turnserver.conf').chmod(0o640)
PY

sed -i 's/^#\?TURNSERVER_ENABLED=.*/TURNSERVER_ENABLED=1/' /etc/default/coturn
/usr/local/sbin/dante-live-cert-deploy
nginx -t >/dev/null 2>&1
systemctl daemon-reload
systemctl enable --now nginx coturn dante-live-turn-api >/dev/null
systemctl restart dante-live-turn-api >/dev/null
if python3 - "$public_ip" <<'PY'
import sys
from pathlib import Path
config = Path('/etc/letsencrypt/renewal') / (sys.argv[1] + '.conf')
raise SystemExit(0 if 'authenticator = standalone' in config.read_text() else 1)
PY
then
  /opt/dante-live-certbot/bin/certbot reconfigure --cert-name "$public_ip" \
    --webroot -w /var/www/dante-live-acme --non-interactive >/dev/null
fi
cat > /etc/systemd/system/dante-live-cert-renew.service <<'EOF'
[Unit]
Description=Renew short-lived HTTPS certificate for Dante Live IP
[Service]
Type=oneshot
ExecStart=/opt/dante-live-certbot/bin/certbot renew --non-interactive --webroot --webroot-path /var/www/dante-live-acme --deploy-hook /usr/local/sbin/dante-live-cert-deploy
EOF
cat > /etc/systemd/system/dante-live-cert-renew.timer <<'EOF'
[Unit]
Description=Check Dante Live IP certificate renewal twice daily
[Timer]
OnCalendar=*-*-* 03,15:15:00
RandomizedDelaySec=30m
Persistent=true
[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now dante-live-cert-renew.timer >/dev/null

python3 - <<'PY'
import json, urllib.request
v = json.load(open('/etc/dante-live/private.json'))
request = urllib.request.Request('http://127.0.0.1:8765/api/health', headers={'Authorization': 'Bearer ' + v['connection_token']})
assert json.load(urllib.request.urlopen(request, timeout=5))['status'] == 'ready'
PY
echo 'Dante Live VPS: serviços instalados e API local validada. Credenciais permanecem em arquivo protegido.'
