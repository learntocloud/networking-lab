#!/bin/bash
# API server initialization script (runs via cloud-init user data)
set -e
export DEBIAN_FRONTEND=noninteractive

admin_username="${admin_username}"
ssh_public_key="${ssh_public_key}"

# Create admin user
if ! id -u "$admin_username" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$admin_username"
  usermod -aG sudo "$admin_username"
fi

# Set authorized keys for admin user
mkdir -p /home/${admin_username}/.ssh
cat > /home/${admin_username}/.ssh/authorized_keys << 'SSHKEY'
${ssh_public_key}
SSHKEY
chmod 600 /home/${admin_username}/.ssh/authorized_keys
chown -R ${admin_username}:${admin_username} /home/${admin_username}/.ssh

# Package installation needs the private subnet's NAT route, which setup.sh
# removes only after this script has finished (INC-4521).
apt-get -o DPkg::Lock::Timeout=600 update
apt-get -o DPkg::Lock::Timeout=600 install -y \
  python3 \
  python3-flask \
  postgresql-client \
  iputils-ping \
  net-tools \
  dnsutils \
  traceroute \
  netcat-openbsd \
  curl \
  jq \
  vim

mkdir -p /opt/api
cat > /opt/api/app.py << 'PYAPP'
from flask import Flask, jsonify
import os
import socket

app = Flask(__name__)

@app.route('/')
def home():
    return jsonify(service='API Server', status='running', hostname=socket.gethostname())

@app.route('/health')
def health():
    return jsonify(status='healthy')

@app.route('/db-check')
def db_check():
    host = os.environ.get('DB_HOST', 'db.internal.test')
    try:
        with socket.create_connection((host, 5432), timeout=5):
            return jsonify(database='reachable', host=host, port=5432)
    except OSError as error:
        return jsonify(database='unreachable', host=host, port=5432, error=str(error)), 503

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
PYAPP

# Create systemd service
cat > /etc/systemd/system/api.service << 'SVCFILE'
[Unit]
Description=Networking Lab API Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/api
Environment=DB_HOST=db.internal.test
ExecStart=/usr/bin/python3 /opt/api/app.py
Restart=always

[Install]
WantedBy=multi-user.target
SVCFILE

systemctl daemon-reload
systemctl enable api
systemctl start api

# Create MOTD
cat > /etc/motd << 'EOF'
============================================================
   NETWORKING LAB - API SERVER
============================================================

You are on the API server in the PRIVATE subnet.
This server runs a Flask API on port 8080.

Check API service:
  sudo systemctl status api
  curl http://localhost:8080/health
  curl http://localhost:8080/db-check

Test connectivity:
  curl -sS -o /dev/null -w '%%{http_code}\n' --max-time 10 https://example.com
  dig +short @169.254.169.253 db.internal.test A
  pg_isready -h <database-private-ip> -p 5432 -U labuser -d labdb -t 3

============================================================
EOF

echo "API server setup complete"
touch /var/lib/netlab-startup-complete
