#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib.sh"

parse_args "$@" || exit_error "Usage: $0 -e <environment> -c <customer>"

require_variable "Environment (-e)" "${ENV:-}"
require_variable "Customer (-c)" "${CUSTOMER:-}"
require_commands yq gcloud ansible ansible-playbook python3

CONFIG=$(validate_config_exists "$ENV" "$CUSTOMER")
INVENTORY=$(validate_inventory_exists "$ENV" "$CUSTOMER")

PROJECT=$(get_config "$CONFIG" '.project_id')
DB_TYPE=$(get_config "$CONFIG" '.db.type')
DB_NAME=$(get_config "$CONFIG" '.db.name')
MEM=$(get_config "$CONFIG" '.db.memory_mb')
REGION=$(get_config "$CONFIG" '.region')

require_variable "project_id" "$PROJECT"
require_variable "db.type" "$DB_TYPE"
if [ "$DB_TYPE" != "postgres" ]; then
    exit_error "Invalid db.type '$DB_TYPE'. This project is PostgreSQL-only; use 'postgres'."
fi

INSTANCE_NAME=$(build_instance_name "$DB_TYPE" "$REGION" "$CUSTOMER" "$ENV")

title "Configuring Database"
info "Environment: $ENV"
info "Customer: $CUSTOMER"
info "Type: PostgreSQL"
info "DB Name: $DB_NAME"
info "Memory: ${MEM}MB"
info "Instance: $INSTANCE_NAME"

info "Validating instance in inventory..."
if ! grep -q "$INSTANCE_NAME" "$INVENTORY"; then
    exit_error "Instance '$INSTANCE_NAME' not found in inventory. Expected instance name format: $INSTANCE_NAME"
fi
success "Instance found"

info "Validating inventory YAML..."
if ! python3 -c "import yaml; yaml.safe_load(open('$INVENTORY'))" 2>/dev/null; then
    error "Inventory file has YAML syntax errors"
    python3 -c "import yaml; yaml.safe_load(open('$INVENTORY'))"
    exit 1
fi
success "YAML syntax valid"

title "Preparing Database Credentials"
MASTER_PWD_FILE="env/${ENV}/${CUSTOMER}/db_master_pwd.pass"
USER_PWD_FILE="env/${ENV}/${CUSTOMER}/db_user_pwd.pass"

require_file "$MASTER_PWD_FILE"
require_file "$USER_PWD_FILE"

info "Decrypting passwords..."
MASTER_PWD=$(cat "$MASTER_PWD_FILE" | ./decrypt.sh "$ENV" 2>/dev/null) || exit_error "Failed to decrypt master password"
USER_PWD=$(cat "$USER_PWD_FILE" | ./decrypt.sh "$ENV" 2>/dev/null) || exit_error "Failed to decrypt user password"
success "Passwords decrypted"

title "Uploading Credentials"

REGION_SHORT=$(get_config "env/${ENV}/common-config.yml" ".region_short_names.\"${REGION}\"" "$REGION")
DB_TYPE_LOWER=$(to_lowercase "$DB_TYPE")
CUSTOMER_LOWER=$(to_lowercase "$CUSTOMER")

MASTER_SECRET_NAME="${DB_TYPE_LOWER}-master-pwd-${REGION_SHORT}-${ENV}-${CUSTOMER_LOWER}"
USER_SECRET_NAME="${DB_TYPE_LOWER}-user-pwd-${REGION_SHORT}-${ENV}-${CUSTOMER_LOWER}"

info "Master secret: $MASTER_SECRET_NAME"
info "User secret: $USER_SECRET_NAME"

printf '%s' "$MASTER_PWD" | gcloud secrets versions add "$MASTER_SECRET_NAME" \
    --data-file=- \
    --project "$PROJECT" >/dev/null 2>&1 || \
    (printf '%s' "$MASTER_PWD" | gcloud secrets create "$MASTER_SECRET_NAME" \
        --data-file=- \
        --project "$PROJECT" \
        --replication-policy="automatic" >/dev/null)

printf '%s' "$USER_PWD" | gcloud secrets versions add "$USER_SECRET_NAME" \
    --data-file=- \
    --project "$PROJECT" >/dev/null 2>&1 || \
    (printf '%s' "$USER_PWD" | gcloud secrets create "$USER_SECRET_NAME" \
        --data-file=- \
        --project "$PROJECT" \
        --replication-policy="automatic" >/dev/null)

success "Credentials uploaded"

title "Testing Connectivity"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY_FULL="${SCRIPT_DIR}/${INVENTORY}"

info "Testing Ansible connection..."
if ansible "$INSTANCE_NAME" -i "$INVENTORY_FULL" -m ping > /dev/null 2>&1; then
    success "Ansible connection successful"
else
    error "Ansible connection failed"
    ansible "$INSTANCE_NAME" -i "$INVENTORY_FULL" -m ping -vvv
    exit 1
fi

title "Installing ${DB_TYPE} Database"
info "This may take 30-45 minutes..."

cd "${SCRIPT_DIR}/ansible" || exit_error "Cannot change to ansible directory"

ansible-playbook playbooks/install_database.yml \
    -i "$INVENTORY_FULL" \
    --extra-vars "config_file=${SCRIPT_DIR}/${CONFIG}" \
    -l "${INSTANCE_NAME}" \
    -v

title "Database Configuration Complete"

info "Database Type: PostgreSQL"
info "Instance: $INSTANCE_NAME"
info "Database: $(to_lowercase "$DB_NAME")"
info "User: $(to_lowercase "$DB_NAME")_user"
info "Port: 5432"
info "Connect: psql -U postgres -d $(to_lowercase "$DB_NAME")"

info "Credentials: GCP Secret Manager"
info "  Master: ${MASTER_SECRET_NAME}"
info "  User: ${USER_SECRET_NAME}"
