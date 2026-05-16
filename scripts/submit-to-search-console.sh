#!/usr/bin/env bash
set -euo pipefail

SITE_URL="https://waymoreferralcode.com/"
SITEMAP_URL="https://waymoreferralcode.com/sitemap.xml"
SCOPES="https://www.googleapis.com/auth/webmasters https://www.googleapis.com/auth/siteverification"

if ! command -v gcloud >/dev/null 2>&1; then
  echo "Install the Google Cloud CLI first: https://cloud.google.com/sdk/docs/install" >&2
  exit 1
fi

if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
  gcloud auth application-default login --scopes="$SCOPES"
fi

TOKEN="$(gcloud auth application-default print-access-token)"

api() {
  local method="$1"
  local url="$2"
  local body="${3:-}"
  if [[ -n "$body" ]]; then
    curl -sS -X "$method" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d "$body" "$url"
  else
    curl -sS -X "$method" -H "Authorization: Bearer $TOKEN" "$url"
  fi
}

ENC_SITE="$(node -e 'process.stdout.write(encodeURIComponent(process.argv[1]))' "$SITE_URL")"
ENC_SITEMAP="$(node -e 'process.stdout.write(encodeURIComponent(process.argv[1]))' "$SITEMAP_URL")"

echo "Adding Search Console property: $SITE_URL"
api PUT "https://www.googleapis.com/webmasters/v3/sites/$ENC_SITE" >/dev/null || true

echo "Submitting sitemap: $SITEMAP_URL"
api PUT "https://www.googleapis.com/webmasters/v3/sites/$ENC_SITE/sitemaps/$ENC_SITEMAP" >/dev/null

echo "Checking verification status"
api GET "https://www.googleapis.com/siteVerification/v1/webResource?verificationMethod=FILE&verifiedSite=$SITE_URL" || true
echo
echo "Done. If Google reports the property is unverified, request an HTML-file token in Search Console, commit that google*.html file at the site root, deploy, and rerun this script."
