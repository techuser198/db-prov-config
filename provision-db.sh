#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib.sh"

parse_args "$@" || exit_error "Usage: $0 -e <environment> -c <customer> [-p]"
PLAN_ONLY=${PLAN_ONLY:-false}

require_variable "Environment (-e)" "${ENV:-}"
require_variable "Customer (-c)" "${CUSTOMER:-}"
require_commands terraform yq

CONFIG=$(validate_config_exists "$ENV" "$CUSTOMER")

PROJECT=$(get_config "$CONFIG" '.project_id')
REGION=$(get_config "$CONFIG" '.region')
ZONE=$(get_config "$CONFIG" '.zone')
MACHINE=$(get_config "$CONFIG" '.instance.machine_type')
BOOT_DISK=$(get_config "$CONFIG" '.instance.disk_size')
DATA_DISK=$(get_config "$CONFIG" '.instance.data_disk_size' '100')
IMAGE=$(get_config "$CONFIG" '.instance.image')
DB_TYPE=$(get_config "$CONFIG" '.db.type' 'postgres')

require_variable "project_id" "$PROJECT"
require_variable "region" "$REGION"
require_variable "zone" "$ZONE"
require_variable "machine_type" "$MACHINE"
require_variable "disk_size" "$BOOT_DISK"
require_variable "db.type" "$DB_TYPE"

if [ "$DB_TYPE" != "postgres" ]; then
    exit_error "Invalid db.type '$DB_TYPE'. This project is PostgreSQL-only; use 'postgres'."
fi

INSTANCE=$(build_instance_name "$DB_TYPE" "$REGION" "$CUSTOMER" "$ENV")

title "Provisioning Database VM"
info "Environment: $ENV"
info "Customer: $CUSTOMER"
info "Database Type: $DB_TYPE"
info "Instance: $INSTANCE"
info "Project: $PROJECT"
info "Region: $REGION"
info "Zone: $ZONE"
info "Machine: $MACHINE"
info "Boot Disk: ${BOOT_DISK}GB"
info "Data Disk: ${DATA_DISK}GB"

TF_VARS=(
    "-var=project_id=${PROJECT}"
    "-var=region=${REGION}"
    "-var=zone=${ZONE}"
    "-var=machine_type=${MACHINE}"
    "-var=boot_disk_size=${BOOT_DISK}"
    "-var=data_disk_size=${DATA_DISK}"
    "-var=image=${IMAGE}"
    "-var=db_type=${DB_TYPE}"
    "-var=environment=${ENV}"
    "-var=customer=${CUSTOMER}"
    "-var=ssh_user=$(whoami)"
    "-var=ssh_public_key_path=$HOME/.ssh/id_rsa.pub"
    "-var=ssh_private_key_path=$HOME/.ssh/id_rsa"
)

terraform_init

if [ "$PLAN_ONLY" = true ]; then
    info "Running terraform plan..."
    terraform_plan "${TF_VARS[@]}"
    success "Plan completed"
else
    info "Provisioning VM..."
    terraform_apply "${TF_VARS[@]}"

    INSTANCE_IP=$(cd terraform && terraform output -raw instance_external_ip)

    success "VM provisioned"
    info "Instance: $INSTANCE"
    info "IP: $INSTANCE_IP"
    info "SSH: ssh -i $HOME/.ssh/id_rsa $(whoami)@$INSTANCE_IP"
    info "Ansible inventory: ansible/inventory/hosts_${ENV}_${CUSTOMER}.yml"

    title "Uploading Database Secrets"
    if [ -f "./upload-secrets.sh" ]; then
        chmod +x ./upload-secrets.sh
        if ./upload-secrets.sh "$ENV" "$CUSTOMER"; then
            success "Secrets uploaded"
        else
            warning "Secret upload skipped"
        fi
    else
        warning "upload-secrets.sh not found"
    fi

    info "Next: ./configuration-db.sh -e $ENV -c $CUSTOMER"
fi
