#!/usr/bin/env bash
set -euo pipefail

SITE_URL="https://waymoreferralcode.com/"
SITEMAP_URL="https://waymoreferralcode.com/sitemap.xml"
SCOPES="https://www.googleapis.com/auth/webmasters https://www.googleapis.com/auth/siteverification"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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
  local response
  local status
  response="$(mktemp)"
  if [[ -n "$body" ]]; then
    status="$(curl -sS -o "$response" -w "%{http_code}" -X "$method" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d "$body" "$url")"
  else
    status="$(curl -sS -o "$response" -w "%{http_code}" -X "$method" -H "Authorization: Bearer $TOKEN" "$url")"
  fi
  cat "$response"
  rm -f "$response"
  [[ "$status" =~ ^2 ]]
}

prepare_verification_file() {
  local token_body
  local token_response
  local verify_file
  token_body="$(node -e 'process.stdout.write(JSON.stringify({site:{type:"SITE",identifier:process.argv[1]},verificationMethod:"FILE"}))' "$SITE_URL")"
  token_response="$(api POST "https://www.googleapis.com/siteVerification/v1/token" "$token_body")"
  verify_file="$(node -e 'const data = JSON.parse(process.argv[1]); process.stdout.write(data.token || "")' "$token_response")"
  if [[ -z "$verify_file" ]]; then
    echo "Could not obtain an HTML verification token. Google response:" >&2
    echo "$token_response" >&2
    exit 1
  fi
  printf 'google-site-verification: %s\n' "$verify_file" > "$REPO_ROOT/$verify_file"
  echo "Created $REPO_ROOT/$verify_file"
  echo "Commit and deploy that file, then rerun this script to verify and submit the sitemap."
  exit 2
}

verify_site() {
  local verify_body
  verify_body="$(node -e 'process.stdout.write(JSON.stringify({site:{type:"SITE",identifier:process.argv[1]}}))' "$SITE_URL")"
  api POST "https://www.googleapis.com/siteVerification/v1/webResource?verificationMethod=FILE" "$verify_body" >/dev/null
}

ENC_SITE="$(node -e 'process.stdout.write(encodeURIComponent(process.argv[1]))' "$SITE_URL")"
ENC_SITEMAP="$(node -e 'process.stdout.write(encodeURIComponent(process.argv[1]))' "$SITEMAP_URL")"

echo "Adding Search Console property: $SITE_URL"
if ! api PUT "https://www.googleapis.com/webmasters/v3/sites/$ENC_SITE" >/dev/null; then
  echo "Property is not verified for this Google account. Trying HTML-file verification."
  if verify_site; then
    echo "Verified $SITE_URL"
    api PUT "https://www.googleapis.com/webmasters/v3/sites/$ENC_SITE" >/dev/null
  else
    prepare_verification_file
  fi
fi

echo "Submitting sitemap: $SITEMAP_URL"
api PUT "https://www.googleapis.com/webmasters/v3/sites/$ENC_SITE/sitemaps/$ENC_SITEMAP" >/dev/null
echo
echo "Done. Search Console property and sitemap submission completed for $SITE_URL"
