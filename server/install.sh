#!/usr/bin/env bash
# serdabVPN server installer. Run once as root on a fresh Debian 12 box (deploy.sh does this for you on Google Cloud).
# Any box with a public IP works: copy install.sh and serdab next to each other and run `sudo ./install.sh`.
set -euo pipefail

WG_DIR=/etc/wireguard
WG_IF=wg0
WG_PORT=${SERDAB_PORT:-51820}
WG_NET=10.7.0
HERE=$(cd "$(dirname "$0")" && pwd)
export DEBIAN_FRONTEND=noninteractive

[[ $EUID -eq 0 ]] || { echo "install.sh: run as root" >&2; exit 1; }
[[ -f $HERE/serdab && -f $HERE/serdabd/serdabd.py ]] || { echo "install.sh: the 'serdab' CLI and serdabd/ must sit next to this script" >&2; exit 1; }

echo "→ packages"
apt-get update -q
apt-get install -y -q wireguard-tools qrencode nftables curl iproute2 procps dnsmasq-base python3 >/dev/null

echo "→ ip forwarding"
mkdir -p /etc/sysctl.d && echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-serdab.conf
sysctl -q --system >/dev/null 2>&1 || sysctl -q -w net.ipv4.ip_forward=1 || true

umask 077
mkdir -p "$WG_DIR/clients"

echo "→ server keys"
if [[ ! -f $WG_DIR/server.key ]]; then
  wg genkey | tee "$WG_DIR/server.key" | wg pubkey > "$WG_DIR/server.pub"
fi

echo "→ public endpoint"
EP=${SERDAB_ENDPOINT:-}
[[ -n $EP ]] || EP=$(curl -fs -m 3 -H 'Metadata-Flavor: Google' \
  http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip 2>/dev/null || true)
[[ -n $EP ]] || EP=$(curl -fs4 -m 5 https://ifconfig.me 2>/dev/null || true)
[[ -n $EP ]] || { echo "install.sh: could not find the public IP; rerun with SERDAB_ENDPOINT=<ip>" >&2; exit 1; }
echo "$EP:$WG_PORT" > "$WG_DIR/endpoint"
echo "   $EP:$WG_PORT"

OUT_IF=$(ip -4 route show default | awk '{print $5; exit}')
[[ -n $OUT_IF ]] || { echo "install.sh: no default route" >&2; exit 1; }

echo "→ $WG_IF on $WG_NET.0/24, NAT out of $OUT_IF"
if [[ ! -f $WG_DIR/$WG_IF.conf ]]; then
  cat > "$WG_DIR/$WG_IF.conf" <<CONF
[Interface]
Address = $WG_NET.1/24
ListenPort = $WG_PORT
PrivateKey = $(cat "$WG_DIR/server.key")
PostUp = nft add table ip serdab; nft add chain ip serdab postrouting '{ type nat hook postrouting priority 100 ; }'; nft add rule ip serdab postrouting oifname "$OUT_IF" masquerade
PostDown = nft delete table ip serdab
CONF
fi

install -m 0755 "$HERE/serdab" /usr/local/bin/serdab

echo "→ serdabd (devices, rules, DNS filter, logs)"
install -d -m 0755 /usr/local/lib/serdab /var/log/serdab
install -d -m 0700 /etc/serdab /var/lib/serdab
install -m 0644 "$HERE/serdabd/serdabd.py" /usr/local/lib/serdab/serdabd.py
install -m 0644 "$HERE/serdabd/etc/dnsmasq-filtered.conf" "$HERE/serdabd/etc/dnsmasq-open.conf" /etc/serdab/
[[ -f /etc/serdab/admin.key ]] || head -c 32 /dev/urandom | base64 | tr -d '/+=' > /etc/serdab/admin.key
chmod 600 /etc/serdab/admin.key
INTERNAL_IP=$(curl -fs -m 3 -H 'Metadata-Flavor: Google' \
  http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip 2>/dev/null || true)
cat > /etc/serdab/serdabd.env <<ENV
# 127.0.0.1 for the CLI; the private address for the dashboard (Cloud Run, direct VPC egress)
SERDAB_ADMIN_HOSTS=127.0.0.1${INTERNAL_IP:+,$INTERNAL_IP}
SERDAB_OWNER_NAME=${SERDAB_OWNER_NAME:-Taha}
SERDAB_COST_PER_GB=${SERDAB_COST_PER_GB:-0.12}
SERDAB_TZ=${SERDAB_TZ:-Asia/Qatar}
# The dashboard's public /join page, so invitations sent in chats are tappable (optional)
SERDAB_JOIN_URL=${SERDAB_JOIN_URL:-}
ENV

if command -v systemctl >/dev/null && systemctl is-system-running >/dev/null 2>&1; then
  install -m 0644 "$HERE/serdabd/etc/serdabd.service" "$HERE/serdabd/etc/serdab-dns@.service" /etc/systemd/system/
  systemctl daemon-reload
  systemctl enable --now "wg-quick@$WG_IF" >/dev/null
  systemctl enable serdab-dns@filtered serdab-dns@open serdabd >/dev/null 2>&1
  systemctl restart serdab-dns@filtered serdab-dns@open serdabd
  for i in $(seq 1 20); do serdab list >/dev/null 2>&1 && break; sleep 0.5; done
else
  wg-quick up "$WG_IF" 2>/dev/null || true   # containers and tests: no systemd
fi

touch "$WG_DIR/.ready"
echo "✓ serdabVPN is up. Enrol a device:  sudo serdab add phone"
