#!/bin/bash
# Zenith Account Server - DigitalOcean systemd bootstrap
# Usage:
#   sudo bash digitalocean-systemd-bootstrap.sh --no-tls
#   sudo bash digitalocean-systemd-bootstrap.sh --domain api.example.com --email admin@example.com

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="/opt/zenith-server"
DATA_DIR="/var/lib/zenith"
SERVICE_USER="zenith"

TLS_MODE="none"
DOMAIN=""
EMAIL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-tls)
      TLS_MODE="none"
      shift
      ;;
    --domain)
      DOMAIN="${2:-}"
      TLS_MODE="tls"
      shift 2
      ;;
    --email)
      EMAIL="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--no-tls | --domain DOMAIN --email EMAIL]"
      exit 1
      ;;
  esac
done

if [[ "$TLS_MODE" == "tls" ]] && [[ -z "$DOMAIN" || -z "$EMAIL" ]]; then
  echo "Error: --domain and --email are required in TLS mode"
  exit 1
fi

echo "[1/8] Install system packages"
apt-get update
apt-get install -y ca-certificates curl gnupg apt-transport-https ufw fail2ban unattended-upgrades nginx certbot python3-certbot-nginx

echo "[2/8] Install Dart SDK"
wget -qO- https://dl-ssl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/dart.gpg
echo 'deb [signed-by=/usr/share/keyrings/dart.gpg arch=amd64] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main' > /etc/apt/sources.list.d/dart_stable.list
apt-get update
apt-get install -y dart

echo "[3/8] Configure host firewall and hardening"
ufw --force default deny incoming
ufw --force default allow outgoing
ufw allow 22/tcp
if [[ "$TLS_MODE" == "tls" ]]; then
  ufw allow 80/tcp
  ufw allow 443/tcp
else
  ufw allow 3000/tcp
fi
ufw --force enable
systemctl enable fail2ban --now
systemctl enable unattended-upgrades --now

echo "[4/8] Create service user and data dirs"
if ! id "$SERVICE_USER" >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /bin/false "$SERVICE_USER"
fi
mkdir -p "$DATA_DIR/.config" "$DATA_DIR/.pub-cache"
chown -R "$SERVICE_USER:$SERVICE_USER" "$DATA_DIR"

echo "[5/8] Validate server directory"
if [[ ! -f "$SERVER_DIR/pubspec.yaml" ]]; then
  echo "Missing $SERVER_DIR/pubspec.yaml"
  echo "Copy your server code to $SERVER_DIR first (e.g. rsync)."
  exit 1
fi
chown -R "$SERVICE_USER:$SERVICE_USER" "$SERVER_DIR"

echo "[6/8] Install Dart dependencies"
cd "$SERVER_DIR"
sudo -u "$SERVICE_USER" HOME="$DATA_DIR" XDG_CONFIG_HOME="$DATA_DIR/.config" PUB_CACHE="$DATA_DIR/.pub-cache" DART_SUPPRESS_ANALYTICS=true /usr/lib/dart/bin/dart pub get

echo "[7/8] Write environment and install systemd service"
if [[ ! -f "$SERVER_DIR/.env" ]]; then
  cat > "$SERVER_DIR/.env" <<EOF
ZENITH_HOST=0.0.0.0
ZENITH_PORT=3000
ZENITH_JWT_SECRET=$(openssl rand -base64 32)
ZENITH_DB_PATH=$DATA_DIR/accounts.json
EOF
  chown "$SERVICE_USER:$SERVICE_USER" "$SERVER_DIR/.env"
  chmod 600 "$SERVER_DIR/.env"
fi

cp "$SCRIPT_DIR/zenith-server.service" /etc/systemd/system/zenith-server.service
systemctl daemon-reload
systemctl enable zenith-server
systemctl restart zenith-server
sleep 2

if ! systemctl is-active --quiet zenith-server; then
  echo "Service failed to start. Recent logs:"
  journalctl -u zenith-server -n 60 --no-pager
  exit 1
fi

echo "[8/8] Configure Nginx"
if [[ "$TLS_MODE" == "tls" ]]; then
  cat > /etc/nginx/sites-available/zenith <<EOF
server {
  listen 80;
  server_name $DOMAIN;

  location /.well-known/acme-challenge/ {
    root /var/www/html;
  }

  location / {
    return 301 https://\$host\$request_uri;
  }
}
EOF

  ln -sf /etc/nginx/sites-available/zenith /etc/nginx/sites-enabled/zenith
  rm -f /etc/nginx/sites-enabled/default
  nginx -t
  systemctl reload nginx

  certbot --nginx -d "$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive

  cat > /etc/nginx/sites-available/zenith <<EOF
server {
  listen 80;
  server_name $DOMAIN;
  return 301 https://\$host\$request_uri;
}

server {
  listen 443 ssl http2;
  server_name $DOMAIN;

  ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

  add_header X-Frame-Options DENY;
  add_header X-Content-Type-Options nosniff;
  add_header Referrer-Policy no-referrer;

  location / {
    proxy_pass http://127.0.0.1:3000;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }
}
EOF

  nginx -t
  systemctl reload nginx

  echo "Deployment complete with HTTPS: https://$DOMAIN/health"
else
  systemctl reload nginx || true
  echo "Deployment complete over HTTP: http://$(curl -s ifconfig.me):3000/health"
fi

echo "Manage service with:"
echo "  sudo systemctl status zenith-server"
echo "  sudo journalctl -u zenith-server -f"
