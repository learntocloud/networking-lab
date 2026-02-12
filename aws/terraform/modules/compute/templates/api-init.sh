#!/bin/bash
# API server initialization script
set -e

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

# Create simple API application (offline)
mkdir -p /opt/api
cat > /opt/api/index.html << 'HTML'
<html>
  <head><title>Networking Lab API</title></head>
  <body>
    <h1>API Server</h1>
    <p>Status: running</p>
  </body>
</html>
HTML

# Create systemd service
cat > /etc/systemd/system/api.service << 'SVCFILE'
[Unit]
Description=Networking Lab API Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/api
ExecStart=/usr/bin/python3 -m http.server 8080 --bind 0.0.0.0
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
This server runs a simple HTTP server on port 8080.

Check API service:
  sudo systemctl status api
  curl http://localhost:8080/

Test connectivity:
  nc -zv db.internal.local 5432
  curl http://localhost:8080/

============================================================
EOF

echo "API server setup complete"
