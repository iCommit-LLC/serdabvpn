#!/usr/bin/env bash
# Delete everything deploy.sh created. Nothing else in the project is touched.
set -euo pipefail
: "${PROJECT:?set PROJECT to your Google Cloud project id}"
ZONE=${ZONE:-europe-west9-b}; REGION=${ZONE%-*}; NAME=${NAME:-serdab}
g() { gcloud --project "$PROJECT" --quiet "$@"; }
g compute instances delete "$NAME" --zone "$ZONE" 2>/dev/null && echo "deleted VM $NAME" || true
g compute firewall-rules delete "$NAME-wg" 2>/dev/null && echo "deleted firewall $NAME-wg" || true
g compute addresses delete "$NAME-ip" --region "$REGION" 2>/dev/null && echo "released IP $NAME-ip" || true
