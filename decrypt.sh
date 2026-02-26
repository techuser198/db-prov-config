#!/usr/bin/env bash
set -euo pipefail

# Decrypt secrets using GCP KMS
# Usage: cat db_master_pwd.pass | ./decrypt.sh dev
# Usage: echo "encrypted_base64" | ./decrypt.sh prod

BASE_DIR=$(dirname "$0")

if [ $# -ne 1 ]; then
    echo "Usage: $0 <env>"
    echo ""
    echo "Decrypts Base64-encoded stdin using GCP KMS"
    echo ""
    echo "Arguments:"
    echo "  env    Environment: dev, cert, or prod"
    echo ""
    echo "Example:"
    echo "  cat env/dev/AM/db_master_pwd.pass | $0 dev"
    echo "  echo 'CiQA...' | $0 prod"
    exit 1
fi

ENV=$1

[[ "$ENV" =~ ^(dev|cert|prod)$ ]] || {
    echo "Error: Environment must be dev, cert, or prod" >&2
    exit 1
}

SECRETS_DIR="$BASE_DIR/secrets"
SEC_CONF="$SECRETS_DIR/kms-config.yml"
ENV_CONFIG="$BASE_DIR/env/$ENV/common-config.yml"

[ -f "$SEC_CONF" ] || {
    echo "Error: KMS config not found: $SEC_CONF" >&2
    echo ""
    echo "Create $SEC_CONF with:" >&2
    echo "  security:" >&2
    echo "    EncryptionKey:" >&2
    echo "      Ring: keyring-name" >&2
    echo "      Location: global" >&2
    echo "      Key: key-name" >&2
    exit 1
}

[ -f "$ENV_CONFIG" ] || {
    echo "Error: Environment config not found: $ENV_CONFIG" >&2
    exit 1
}

PROJECT=$(yq eval ".project_id" "$ENV_CONFIG")
[ "$PROJECT" != "null" ] && [ -n "$PROJECT" ] || {
    echo "Error: project_id not found in $ENV_CONFIG" >&2
    exit 1
}

KEY_RING=$(yq eval ".security.EncryptionKey.Ring" "$SEC_CONF")
KEY_LOCATION=$(yq eval ".security.EncryptionKey.Location" "$SEC_CONF")
KEY_NAME=$(yq eval ".security.EncryptionKey.Key" "$SEC_CONF")

[ "$KEY_RING" != "null" ] && [ "$KEY_LOCATION" != "null" ] && [ "$KEY_NAME" != "null" ] || {
    echo "Error: Invalid KMS configuration" >&2
    exit 1
}

grep -v '^#' | grep -v '^$' | tr -d '\r\n' | base64 -d | \
    gcloud kms decrypt \
        --project "$PROJECT" \
        --ciphertext-file - \
        --plaintext-file - \
        --keyring "$KEY_RING" \
        --location "$KEY_LOCATION" \
        --key "$KEY_NAME"
