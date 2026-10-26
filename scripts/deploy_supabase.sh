#!/usr/bin/env bash
set -euo pipefail

: "${SUPABASE_ACCESS_TOKEN:?Run 'supabase login' or export SUPABASE_ACCESS_TOKEN first}"
: "${XENDIT_SECRET_KEY:?Set the Xendit test secret before deploying}"
: "${XENDIT_WEBHOOK_TOKEN:?Set the Xendit webhook token before deploying}"

project_ref="jnukqrpkyqwoatesuelp"

npx --yes supabase@latest link --project-ref "$project_ref" --password "${SUPABASE_DB_PASSWORD:?Set SUPABASE_DB_PASSWORD for the linked project}"
npx --yes supabase@latest db push --linked
npx --yes supabase@latest secrets set \
  XENDIT_SECRET_KEY="$XENDIT_SECRET_KEY" \
  XENDIT_WEBHOOK_TOKEN="$XENDIT_WEBHOOK_TOKEN" \
  XENDIT_SUCCESS_URL="${XENDIT_SUCCESS_URL:-https://scentify.app/payment/success}" \
  XENDIT_CANCEL_URL="${XENDIT_CANCEL_URL:-https://scentify.app/payment/cancel}"
npx --yes supabase@latest functions deploy create-xendit-session --project-ref "$project_ref" --use-api
npx --yes supabase@latest functions deploy xendit-webhook --project-ref "$project_ref" --no-verify-jwt --use-api

echo "Supabase cutover deployed to $project_ref"
echo "Create: https://$project_ref.supabase.co/functions/v1/create-xendit-session"
echo "Webhook: https://$project_ref.supabase.co/functions/v1/xendit-webhook"
