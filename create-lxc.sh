#!/usr/bin/env bash

set -e
set -u

# ---------- 1  Gather user input ----------

while true; do
  read -rp "Enter numeric container ID (CTID) [e.g. 1337]: " CTID
  [[ "$CTID" =~ ^[0-9]+$ ]] && break
  echo "❌  CTID must be a number."
done

read -rp "Enter hostname for container [default: funserver]: " HOSTNAME
HOSTNAME=${HOSTNAME:-funserver}

while true; do
  read -rp "Enter static IP/CIDR (e.g. 192.168.1.100/24): " STATIC_IP
  [[ "$STATIC_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}\/[0-9]{1,2}$ ]] && break
  echo "❌  Format must be something like 192.168.1.100/24"
done

while true; do
  read -rp "Enter gateway IP (e.g. 192.168.1.1): " GATEWAY
  [[ "$GATEWAY" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && break
  echo "❌  Invalid IP."
done

# ---------- 2  Static values ----------
TEMPLATE_NAME=$(pveam available | grep debian-12 | sort -r | head -n 1 | awk '{print $2}')
#TEMPLATE_NAME="debian-12-standard_12.3-1_amd64.tar.zst"
TEMPLATE="local:vztmpl/$TEMPLATE_NAME"
TEMPLATE_PATH="/var/lib/vz/template/cache/$TEMPLATE_NAME"
STORAGE="local-lvm"
ROOTFS="2"
MEMORY="512"
PASSWORD="funny123"
BRIDGE="vmbr0"
TMP_HTML="/tmp/index.html"
GITHUB_RAW="https://raw.githubusercontent.com/Nylereia/ProxMox/main/index.html"

# ---------- 3  Checks ----------

if [[ ! -f "$TEMPLATE_PATH" ]]; then
  echo "📦 Template $TEMPLATE_NAME not found. Downloading..."
  pveam update
  pveam download local "$TEMPLATE_NAME"
else
  echo "✅ Template $TEMPLATE_NAME already exists."
fi

if pct status "$CTID" &>/dev/null; then
  echo "❌  CTID $CTID already exists. Choose another."
  exit 1
fi

# ---------- 4  Create the container ----------

echo "🛠 Creating LXC $CTID..."
pct create "$CTID" "$TEMPLATE" \
  --hostname "$HOSTNAME" \
  --storage "$STORAGE" \
  --rootfs "$STORAGE:$ROOTFS" \
  --memory "$MEMORY" \
  --net0 name=eth0,bridge="$BRIDGE",ip="$STATIC_IP",gw="$GATEWAY" \
  --password "$PASSWORD" \
  --start 1

# ---------- 5  Install nginx ----------

echo " Installing nginx in container..."
pct exec "$CTID" -- bash -c "apt-get update -qq && apt-get install -y -qq nginx"

# ---------- 6  Download and push HTML ----------

echo " Downloading web page from GitHub..."
GITHUB_RAW="https://raw.githubusercontent.com/Nylereia/ProxMox/main/index.html"
TMP_HTML="/tmp/index.html"
curl -fsSL "$GITHUB_RAW" -o "$TMP_HTML"

echo " Copying index.html to container..."
pct push "$CTID" "$TMP_HTML" /tmp/index.html
pct exec "$CTID" -- bash -c "mv /tmp/index.html /var/www/html/index.html && chown www-data:www-data /var/www/html/index.html"

# ---------- ✅ Done ----------

IP_ADDR=$(cut -d'/' -f1 <<< "$STATIC_IP")
echo
echo "✅  LXC container ready"
echo "🌐  Open http://$IP_ADDR in your browser."
echo "🔑  Root password inside container: $PASSWORD"
