#!/bin/bash
# Bastion host initialization script
set -e

admin_username="${admin_username}"
ssh_public_key="${ssh_public_key}"

# Create admin user
if ! id -u "$admin_username" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$admin_username"
  usermod -aG sudo "$admin_username"
fi

# Install useful networking tools
apt-get update
apt-get install -y \
    net-tools \
    dnsutils \
    traceroute \
    netcat-openbsd \
    curl \
    jq \
    vim

# Set authorized keys for admin user
mkdir -p /home/${admin_username}/.ssh
cat > /home/${admin_username}/.ssh/authorized_keys << 'SSHKEY'
${ssh_public_key}
SSHKEY
chmod 600 /home/${admin_username}/.ssh/authorized_keys
chown -R ${admin_username}:${admin_username} /home/${admin_username}/.ssh

# Save the SSH private key for jumping to other hosts
mkdir -p /home/${admin_username}/.ssh
cat > /home/${admin_username}/.ssh/id_rsa << 'SSHKEY'
${ssh_private_key}
SSHKEY
chmod 600 /home/${admin_username}/.ssh/id_rsa
chown -R ${admin_username}:${admin_username} /home/${admin_username}/.ssh

# Create a helpful MOTD
cat > /etc/motd << 'EOF'
============================================================
   NETWORKING LAB - BASTION HOST
============================================================

You are on the bastion host in the PUBLIC subnet.
From here you can SSH to other hosts in the lab:

  ssh <private-ip>      # Connect to web/api/database servers

Useful commands:
  ip addr               # Show network interfaces
  ip route              # Show routing table
  ping <ip>             # Test connectivity
  traceroute <ip>       # Trace packet path
  nc -zv <ip> <port>    # Test port connectivity
  dig <hostname>        # DNS lookup
  nslookup <hostname>   # DNS lookup (alternative)
  curl -I <url>         # HTTP HEAD request

============================================================
EOF

echo "Bastion host setup complete"
