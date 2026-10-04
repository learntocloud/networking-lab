#!/bin/bash
# Database server initialization script
set -e

# Install PostgreSQL and tools
# Retry: egress can lag for a minute after first boot (apt-get update alone
# exits 0 on fetch failures, so the install is what detects it).
apt_install() {
  local attempt
  for attempt in $(seq 1 30); do
    if apt-get -o DPkg::Lock::Timeout=600 update &&
      apt-get -o DPkg::Lock::Timeout=600 install -y "$@"; then
      return 0
    fi
    echo "apt attempt $attempt failed; retrying in 10s" >&2
    sleep 10
  done
  return 1
}
apt_install \
    postgresql \
    postgresql-contrib \
    net-tools \
    dnsutils \
    traceroute \
    netcat-openbsd \
    curl \
    jq \
    vim

# Configure PostgreSQL to listen on all interfaces
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /etc/postgresql/*/main/postgresql.conf

# Allow connections from private subnet (for Task 5, this won't work until NSG is fixed)
echo "host    all             all             10.0.0.0/16             md5" >> /etc/postgresql/*/main/pg_hba.conf

# Restart PostgreSQL
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
  sudo -u postgres psql -c "SELECT version();"

Connection info:
  Host: db.internal.test (after DNS is fixed)
  Port: 5432
  User: labuser
  Password: labpassword
  Database: labdb

Test local connection:
  psql -h localhost -U labuser -d labdb

============================================================
EOF

echo "Database server setup complete"
