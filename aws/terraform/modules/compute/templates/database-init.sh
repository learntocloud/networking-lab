#!/bin/bash
# Database server initialization script
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

# Create simple DB listener (offline)
mkdir -p /opt/db
cat > /opt/db/db-listener.py << 'PYAPP'
import socket

HOST = "0.0.0.0"
PORT = 5432

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
  s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
  s.bind((HOST, PORT))
  s.listen(5)
  while True:
    conn, _ = s.accept()
    conn.close()
PYAPP

cat > /etc/systemd/system/db-listener.service << 'SVCFILE'
[Unit]
Description=Networking Lab DB Listener
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/db
ExecStart=/usr/bin/python3 /opt/db/db-listener.py
Restart=always

[Install]
WantedBy=multi-user.target
SVCFILE

systemctl daemon-reload
systemctl enable db-listener
systemctl start db-listener

# Create MOTD
cat > /etc/motd << 'EOF'
============================================================
   NETWORKING LAB - DATABASE SERVER
============================================================

You are on the database server in the DATABASE subnet.
This server runs a simple TCP listener on port 5432.

Check listener:
  sudo systemctl status db-listener
  nc -zv localhost 5432

============================================================
EOF

echo "Database server setup complete"
