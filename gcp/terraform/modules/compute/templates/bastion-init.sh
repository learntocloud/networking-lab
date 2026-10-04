#!/bin/bash
# Bastion host initialization script
set -e

# Install useful networking tools
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
    python3 \
    iputils-ping \
    net-tools \
    dnsutils \
    traceroute \
    netcat-openbsd \
    curl \
    jq \
    vim

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
touch /var/lib/netlab-startup-complete
