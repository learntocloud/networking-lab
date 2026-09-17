#!/bin/bash
# Database server initialization script (runs via cloud-init user data)
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

# Install PostgreSQL and diagnostic tools (through the database subnet's NAT route)
apt-get -o DPkg::Lock::Timeout=600 update
apt-get -o DPkg::Lock::Timeout=600 install -y \
  python3 \
  iputils-ping \
  postgresql \
  postgresql-contrib \
  net-tools \
  dnsutils \
  traceroute \
  netcat-openbsd \
  curl \
  jq \
  vim

# Listen on all interfaces; security groups and the network ACL decide who can connect.
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /etc/postgresql/*/main/postgresql.conf
echo "host    all             all             10.0.0.0/16             md5" >> /etc/postgresql/*/main/pg_hba.conf

systemctl restart postgresql
systemctl enable postgresql

# Create a test database and user
sudo -u postgres psql << 'SQLCMD'
CREATE USER labuser WITH PASSWORD 'labpassword';
CREATE DATABASE labdb OWNER labuser;
GRANT ALL PRIVILEGES ON DATABASE labdb TO labuser;
SQLCMD

# Create MOTD
cat > /etc/motd << 'EOF'
============================================================
   NETWORKING LAB - DATABASE SERVER
============================================================

You are on the database server in the DATABASE subnet.
This server runs PostgreSQL on port 5432.

Check PostgreSQL:
  sudo systemctl status postgresql
  pg_isready -h 127.0.0.1 -p 5432 -U labuser -d labdb -t 3

Connection info:
  Host: db.internal.test (after DNS is fixed)
  Port: 5432
  User: labuser
  Password: labpassword
  Database: labdb

============================================================
EOF

echo "Database server setup complete"
touch /var/lib/netlab-startup-complete
