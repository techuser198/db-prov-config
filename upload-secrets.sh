#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib.sh"

[ $# -eq 2 ] || exit_error "Usage: $0 <env> <customer>"

ENV=$1
CUSTOMER=$2
DB_TYPE=postgres

[[ "$ENV" =~ ^(dev|cert|prod)$ ]] || exit_error "Environment must be: dev, cert, prod"

require_commands yq gcloud find grep tr

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/env/${ENV}/${CUSTOMER}"
COMMON_CONFIG="${SCRIPT_DIR}/env/${ENV}/common-config.yml"
DB_CONFIG="${CONFIG_DIR}/db-config.yml"

require_file "$DB_CONFIG"
require_file "$COMMON_CONFIG"

PROJECT_ID=$(get_config "$DB_CONFIG" '.project_id')
REGION=$(get_config "$DB_CONFIG" '.region')
require_variable "project_id" "$PROJECT_ID"
require_variable "region" "$REGION"

REGION_SHORT=$(get_config "$COMMON_CONFIG" ".region_short_names.\"${REGION}\"" "$REGION")

title "Uploading Secrets to GCP"
info "Environment: ${ENV}"
info "Customer: ${CUSTOMER}"
info "DB Type: ${DB_TYPE}"
info "Project: ${PROJECT_ID}"
info "Region: ${REGION} (${REGION_SHORT})"

CUSTOMER_LOWER=$(to_lowercase "$CUSTOMER")

mapfile -t PASS_FILES < <(find "$CONFIG_DIR" -name "*.pass" -not -name "*.example" -type f 2>/dev/null)

if [ ${#PASS_FILES[@]} -eq 0 ]; then
    warning "No .pass files found"
    info "Create password files using: ./setup-secrets.sh or ./create-password-files.sh"
    exit 0
fi

success "${#PASS_FILES[@]} password file(s) found"
echo ""

UPLOADED=0
SKIPPED=0

for PASS_FILE in "${PASS_FILES[@]}"; do
    BASE_NAME=$(basename "$PASS_FILE" .pass)

    case "$BASE_NAME" in
        db_master_pwd) SECRET_TYPE="master-pwd" ;;
        db_user_pwd) SECRET_TYPE="user-pwd" ;;
        *) SECRET_TYPE=$(echo "${BASE_NAME}" | sed 's/^db_//' | tr '_' '-') ;;
    esac

    SECRET_NAME="${DB_TYPE}-${SECRET_TYPE}-${REGION_SHORT}-${ENV}-${CUSTOMER_LOWER}"

    info "Processing: ${BASE_NAME}"
    info "Secret: ${SECRET_NAME}"

    ENCRYPTED_VALUE=$(grep -v '^#' "$PASS_FILE" | grep -v '^$' | tr -d '\n')

    if [ -z "$ENCRYPTED_VALUE" ] || [ "$ENCRYPTED_VALUE" = "REPLACE_WITH_ENCRYPTED_PASSWORD" ]; then
        warning "Skipped: placeholder or empty"
        ((SKIPPED+=1))
    else
        if gcloud secrets describe "$SECRET_NAME" --project="$PROJECT_ID" >/dev/null 2>&1; then
            printf '%s' "$ENCRYPTED_VALUE" | gcloud secrets versions add "$SECRET_NAME" \
                --data-file=- \
                --project="$PROJECT_ID" >/dev/null 2>&1 || error "Failed to add version"
            success "Version added"
        else
            printf '%s' "$ENCRYPTED_VALUE" | gcloud secrets create "$SECRET_NAME" \
                --data-file=- \
                --project="$PROJECT_ID" \
                --replication-policy="automatic" \
                --labels="environment=${ENV},customer=${CUSTOMER_LOWER},db-type=${DB_TYPE}" >/dev/null 2>&1 || error "Failed to create"
            success "Created"
        fi
        ((UPLOADED+=1))
    fi
    echo ""
done

title "Upload Complete"
info "Uploaded: ${UPLOADED}, Skipped: ${SKIPPED}"
info ""
info "Verify secrets:"
info "  gcloud secrets list --project=${PROJECT_ID} --filter='labels.customer=${CUSTOMER_LOWER}'"
info ""
info "Read secret:"
info "  gcloud secrets versions access latest --secret=${DB_TYPE}-master-pwd-${REGION_SHORT}-${ENV}-${CUSTOMER_LOWER}"
