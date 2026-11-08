#!/usr/bin/env bash
# One-time GCP setup for serdab-dashboard (idempotent). Run as a project owner:
#   CLOUDSDK_CORE_ACCOUNT=<owner> infra/setup.sh
# Same pattern as the iCommit services in icommit-infra: a runtime SA with no
# roles, and a deployer SA only this repo's GitHub Actions can impersonate (WIF).
# The serdab VM is not in Terraform, so neither is this.
set -euo pipefail
P=gen-lang-client-0922974889
NUM=248690338020
REPO=iCommit-LLC/serdabvpn   # the dashboard lives in dashboard/ of this repo
RUN=serdab-dashboard-run
DEP=serdab-dashboard-deployer
g() { gcloud --project "$P" --quiet "$@"; }

for sa in "$RUN:serdab-dashboard runtime (no roles)" "$DEP:serdab-dashboard CI deployer (GitHub Actions via WIF)"; do
  id=${sa%%:*}
  g iam service-accounts describe "$id@$P.iam.gserviceaccount.com" >/dev/null 2>&1 \
    || g iam service-accounts create "$id" --display-name "${sa#*:}"
done
DEP_SA=$DEP@$P.iam.gserviceaccount.com
RUN_SA=$RUN@$P.iam.gserviceaccount.com

echo "→ deployer: deploy Cloud Run, push images, act as the runtime SA, use the Paris subnet"
g projects add-iam-policy-binding "$P" --member "serviceAccount:$DEP_SA" --role roles/run.developer --condition=None >/dev/null
g artifacts repositories add-iam-policy-binding icommit --location europe-west1 \
  --member "serviceAccount:$DEP_SA" --role roles/artifactregistry.writer >/dev/null
g iam service-accounts add-iam-policy-binding "$RUN_SA" \
  --member "serviceAccount:$DEP_SA" --role roles/iam.serviceAccountUser >/dev/null
g compute networks subnets add-iam-policy-binding default --region europe-west9 \
  --member "serviceAccount:$DEP_SA" --role roles/compute.networkUser >/dev/null

echo "→ only $REPO may impersonate the deployer"
g iam service-accounts add-iam-policy-binding "$DEP_SA" --role roles/iam.workloadIdentityUser \
  --member "principalSet://iam.googleapis.com/projects/$NUM/locations/global/workloadIdentityPools/github-pool/attribute.repository/$REPO" >/dev/null

echo "→ repo variables"
gh variable set GCP_WIF_PROVIDER -R "$REPO" \
  --body "projects/$NUM/locations/global/workloadIdentityPools/github-pool/providers/github-provider"
gh variable set GCP_DEPLOYER_SA -R "$REPO" --body "$DEP_SA"

echo "→ first deploy (GitHub Actions), then open the login page to the internet"
gh workflow run dashboard.yml -R "$REPO"
sleep 10
RUN_ID=$(gh run list -R "$REPO" --workflow dashboard.yml --limit 1 --json databaseId -q '.[0].databaseId')
gh run watch "$RUN_ID" -R "$REPO" --exit-status
g run services add-iam-policy-binding serdab-dashboard --region europe-west9 --member allUsers --role roles/run.invoker >/dev/null
g run services describe serdab-dashboard --region europe-west9 --format 'value(status.url)'
