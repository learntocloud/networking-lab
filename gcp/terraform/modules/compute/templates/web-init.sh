#!/bin/bash
# Web server initialization script
set -e

# Install nginx and tools
apt-get update
apt-get install -y \
    nginx \
    openssl \
    net-tools \
    dnsutils \
    traceroute \
    netcat-openbsd \
    curl \
    jq \
    vim

# Generate self-signed certificate
mkdir -p /etc/nginx/ssl-certs
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl-certs/server.key \
    -out /etc/nginx/ssl-certs/server.crt \
    -subj "/CN=networking-lab/O=LearnToCloud"

# Configure nginx with HTTP and HTTPS
cat > /etc/nginx/sites-available/default << 'NGINXCONF'
server {
    listen 80;
    server_name _;

    location / {
        return 200 'HTTP OK - Networking Lab Web Server\n';
        add_header Content-Type text/plain;
    }

    location /health {
        return 200 'healthy\n';
        add_header Content-Type text/plain;
    }
}

server {
    listen 443 ssl;
    server_name _;

    ssl_certificate     /etc/nginx/ssl-certs/server.crt;
    ssl_certificate_key /etc/nginx/ssl-certs/server.key;

    location / {
        return 200 'HTTPS OK - Networking Lab Web Server (Secure)\n';
        add_header Content-Type text/plain;
    }

    location /health {
        return 200 'healthy\n';
        add_header Content-Type text/plain;
    }
}
NGINXCONF

# Restart nginx
systemctl enable nginx
systemctl restart nginx

# Create MOTD
cat > /etc/motd << 'EOF'
============================================================
   NETWORKING LAB - WEB SERVER
============================================================

You are on the web server in the PRIVATE subnet.
This server runs nginx on ports 80 (HTTP) and 443 (HTTPS).

Check nginx:
  sudo systemctl status nginx
  sudo nginx -t
  curl http://localhost/health
  curl -k https://localhost/health

============================================================
EOF

echo "Web server setup complete"
