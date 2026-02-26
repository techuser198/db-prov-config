#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib.sh"

parse_args "$@" || exit_error "Usage: $0 -e <environment> -c <customer> [-p] [-f] [-s]"
PLAN_ONLY=${PLAN_ONLY:-false}
FORCE=${FORCE:-false}
DELETE_SECRETS=${DELETE_SECRETS:-false}

require_variable "Environment (-e)" "${ENV:-}"
require_variable "Customer (-c)" "${CUSTOMER:-}"
require_commands terraform yq

CONFIG=$(validate_config_exists "$ENV" "$CUSTOMER")

PROJECT=$(get_config "$CONFIG" '.project_id')
REGION=$(get_config "$CONFIG" '.region')
ZONE=$(get_config "$CONFIG" '.zone')
DB_TYPE=$(get_config "$CONFIG" '.db.type' 'postgres')

require_variable "project_id" "$PROJECT"
require_variable "region" "$REGION"
require_variable "zone" "$ZONE"

if [ "$DB_TYPE" != "postgres" ]; then
    exit_error "Invalid db.type '$DB_TYPE'. This project is PostgreSQL-only; use 'postgres'."
fi

INSTANCE=$(build_instance_name "$DB_TYPE" "$REGION" "$CUSTOMER" "$ENV")

title "Destroying Database VM and Resources"
warning "DESTRUCTIVE OPERATION - PERMANENT DELETION"
info "Instance: $INSTANCE"
info "Data Disk: ${INSTANCE}-data"
info "Firewall Rules: db-allow-ssh-* and db-allow-ports-*"
info "Ansible Inventory: ansible/inventory/hosts_${ENV}_${CUSTOMER}.yml"

if [ "$DELETE_SECRETS" = true ]; then
    info "GCP Secrets: will be deleted (with -s flag)"
fi

warning "ALL DATA WILL BE LOST"

if [ "$FORCE" != true ] && [ "$PLAN_ONLY" != true ]; then
    if ! confirm "Type 'yes' to confirm destruction"; then
        success "Destruction cancelled"
        exit 0
    fi
fi

TF_VARS=(
    "-var=project_id=${PROJECT}"
    "-var=region=${REGION}"
    "-var=zone=${ZONE}"
    "-var=machine_type=e2-standard-4"
    "-var=boot_disk_size=50"
    "-var=data_disk_size=100"
    "-var=image=projects/centos-cloud/global/images/family/centos-stream-9"
    "-var=db_type=${DB_TYPE}"
    "-var=environment=${ENV}"
    "-var=customer=${CUSTOMER}"
    "-var=ssh_user=$(whoami)"
    "-var=ssh_public_key_path=$HOME/.ssh/id_rsa.pub"
    "-var=ssh_private_key_path=$HOME/.ssh/id_rsa"
)

terraform_init

if [ "$PLAN_ONLY" = true ]; then
    info "Generating destroy plan..."
    terraform_destroy_plan "${TF_VARS[@]}"
    info "To execute destruction: $0 -e $ENV -c $CUSTOMER"
    exit 0
fi

info "Destroying infrastructure..."
terraform_destroy "${TF_VARS[@]}"

success "Infrastructure destroyed"

INVENTORY="ansible/inventory/hosts_${ENV}_${CUSTOMER}.yml"
if [ -f "$INVENTORY" ]; then
    info "Removing inventory: $INVENTORY"
    rm -f "$INVENTORY"
    success "Inventory removed"
fi

if [ "$DELETE_SECRETS" = true ]; then
    title "Deleting GCP Secrets"

    COMMON_CONFIG="env/${ENV}/common-config.yml"
    REGION_SHORT=$REGION
    if [ -f "$COMMON_CONFIG" ]; then
        REGION_SHORT=$(get_config "$COMMON_CONFIG" ".region_short_names.\"${REGION}\"" "$REGION")
    fi

    DB_TYPE_LOWER=$(to_lowercase "$DB_TYPE")
    CUSTOMER_LOWER=$(to_lowercase "$CUSTOMER")

    SECRETS=(
        "${DB_TYPE_LOWER}-master-pwd-${REGION_SHORT}-${ENV}-${CUSTOMER_LOWER}"
        "${DB_TYPE_LOWER}-user-pwd-${REGION_SHORT}-${ENV}-${CUSTOMER_LOWER}"
    )

    DELETED=0
    NOT_FOUND=0

    for SECRET_NAME in "${SECRETS[@]}"; do
        if gcloud secrets describe "$SECRET_NAME" --project="$PROJECT" >/dev/null 2>&1; then
            if gcloud secrets delete "$SECRET_NAME" --project="$PROJECT" --quiet; then
                success "Secret deleted: $SECRET_NAME"
                ((DELETED++))
            else
                error "Failed to delete: $SECRET_NAME"
            fi
        else
            info "Secret not found: $SECRET_NAME"
            ((NOT_FOUND++))
        fi
    done

    info "Deleted: $DELETED, Not Found: $NOT_FOUND"
fi

title "Destruction Complete"
success "Resources removed:"
info "  Instance: $INSTANCE"
info "  Data Disk: ${INSTANCE}-data"
info "  Firewall Rules"
info "  Ansible Inventory: $INVENTORY"

if [ "$DELETE_SECRETS" = true ]; then
    info "  GCP Secrets"
fi

warning "Password files in env/${ENV}/${CUSTOMER}/*.pass are preserved"
info "To re-provision: ./provision-db.sh -e $ENV -c $CUSTOMER"
