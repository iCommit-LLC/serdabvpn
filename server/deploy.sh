#!/usr/bin/env bash
# One command: a WireGuard server in Google Cloud Paris and your first device enrolled.
#
#   PROJECT=<gcp project id> ./deploy.sh [device-name]
#
# Knobs: ZONE (europe-west9-b, Paris)  MACHINE (e2-micro)  NAME (serdab)  PORT (51820)
# Cost: an e2-micro in Paris is about $7 a month, plus Google's internet egress
# (roughly $0.09-0.12 per GB that leaves the server). Delete it all with destroy.sh.
set -euo pipefail

: "${PROJECT:?set PROJECT to your Google Cloud project id (gcloud projects list)}"
ZONE=${ZONE:-europe-west9-b}
REGION=${ZONE%-*}
NAME=${NAME:-serdab}
MACHINE=${MACHINE:-e2-micro}
PORT=${PORT:-51820}
DEVICE=${1:-phone}
HERE=$(cd "$(dirname "$0")" && pwd)

g() { gcloud --project "$PROJECT" --quiet "$@"; }
ssh_vm() { g compute ssh "$NAME" --zone "$ZONE" --ssh-flag="-o ConnectTimeout=10" --ssh-flag="-o LogLevel=ERROR" --command "$*"; }

echo "→ Compute Engine API"
g services enable compute.googleapis.com

echo "→ static IP $NAME-ip in $REGION"
g compute addresses describe "$NAME-ip" --region "$REGION" >/dev/null 2>&1 \
  || g compute addresses create "$NAME-ip" --region "$REGION" >/dev/null
IP=$(g compute addresses describe "$NAME-ip" --region "$REGION" --format='value(address)')
echo "   $IP"

echo "→ firewall: udp/$PORT to tag $NAME"
g compute firewall-rules describe "$NAME-wg" >/dev/null 2>&1 \
  || g compute firewall-rules create "$NAME-wg" --allow "udp:$PORT" --target-tags "$NAME" --source-ranges 0.0.0.0/0 >/dev/null

echo "→ VM $NAME ($MACHINE, Debian 12) in $ZONE"
g compute instances describe "$NAME" --zone "$ZONE" >/dev/null 2>&1 \
  || g compute instances create "$NAME" --zone "$ZONE" --machine-type "$MACHINE" \
       --image-family debian-12 --image-project debian-cloud --boot-disk-size 10GB \
       --tags "$NAME" --address "$IP" >/dev/null

echo "→ waiting for ssh"
for i in $(seq 1 30); do
  ssh_vm true 2>/dev/null && break
  sleep 5
  [[ $i -eq 30 ]] && { echo "deploy.sh: ssh never came up" >&2; exit 1; }
done

echo "→ installing WireGuard"
g compute scp --recurse "$HERE/install.sh" "$HERE/serdab" "$HERE/serdabd" "$NAME:/tmp/" --zone "$ZONE" >/dev/null
ssh_vm "sudo SERDAB_PORT=$PORT SERDAB_ENDPOINT=$IP bash /tmp/install.sh && rm -rf /tmp/install.sh /tmp/serdab /tmp/serdabd"

echo "→ enrolling '$DEVICE'"
ssh_vm "sudo serdab add $DEVICE owner || sudo serdab qr $DEVICE"

cat <<DONE

Done. Your tunnel ends at $IP:$PORT (Paris).
  more devices:   gcloud compute ssh $NAME --zone $ZONE --project $PROJECT -- sudo serdab add laptop
  who is on:      gcloud compute ssh $NAME --zone $ZONE --project $PROJECT -- sudo serdab list
  tear it down:   PROJECT=$PROJECT ./destroy.sh
DONE
