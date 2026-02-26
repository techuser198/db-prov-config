#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib.sh"

parse_args "$@" || exit_error "Usage: $0 -e <environment> -c <customer>"

require_variable "Environment (-e)" "${ENV:-}"
require_variable "Customer (-c)" "${CUSTOMER:-}"
require_commands yq ansible ansible-inventory python3 grep

CONFIG=$(validate_config_exists "$ENV" "$CUSTOMER")
INVENTORY=$(validate_inventory_exists "$ENV" "$CUSTOMER")

REGION=$(get_config "$CONFIG" '.region')
DB_TYPE=$(get_config "$CONFIG" '.db.type' 'postgres')

if [ "$DB_TYPE" != "postgres" ]; then
    exit_error "Invalid db.type '$DB_TYPE'. This project is PostgreSQL-only; use 'postgres'."
fi

INSTANCE_NAME=$(build_instance_name "$DB_TYPE" "$REGION" "$CUSTOMER" "$ENV")

title "Testing Database Connection"
info "Instance: $INSTANCE_NAME"
info "Environment: $ENV"
info "Customer: $CUSTOMER"

info "Inventory file:"
cat "$INVENTORY"
echo ""

info "Validating YAML syntax..."
if ! python3 -c "import yaml; yaml.safe_load(open('$INVENTORY'))" 2>/dev/null; then
    error "Inventory has YAML errors"
    python3 -c "import yaml; yaml.safe_load(open('$INVENTORY'))"
    exit 1
fi
success "YAML syntax valid"

info "Checking instance in inventory..."
if ! grep -q "$INSTANCE_NAME" "$INVENTORY"; then
    exit_error "Instance '$INSTANCE_NAME' not found in inventory"
fi
success "Instance found"

INSTANCE_IP=$(yq ".all.children.postgres_databases.hosts.${INSTANCE_NAME}.ansible_host" "$INVENTORY" -r 2>/dev/null || echo "N/A")
info "External IP: ${INSTANCE_IP}"
echo ""

info "Testing Ansible inventory parsing..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY_FULL="${SCRIPT_DIR}/${INVENTORY}"

cd "${SCRIPT_DIR}/ansible" || exit_error "Cannot change to ansible directory"

if ansible-inventory -i "$INVENTORY_FULL" --list >/dev/null 2>&1; then
    success "Ansible inventory valid"
else
    error "Ansible cannot parse inventory"
    ansible-inventory -i "$INVENTORY_FULL" --list
    exit 1
fi
echo ""

info "Testing SSH connectivity..."
if ansible "$INSTANCE_NAME" -i "$INVENTORY_FULL" -m ping 2>&1 | grep -q "SUCCESS"; then
    success "Ansible ping successful"
else
    error "Ansible ping failed"
    warning "Troubleshooting:"
    info "  1. Verify instance is running in GCP"
    info "  2. Check SSH key: $HOME/.ssh/id_rsa"
    info "  3. Test SSH: ssh -i $HOME/.ssh/id_rsa devops@${INSTANCE_IP}"
    info "  4. Check GCP firewall (port 22)"
    ansible "$INSTANCE_NAME" -i "$INVENTORY_FULL" -m ping -vvv
    exit 1
fi

info "Testing command execution..."
if HOSTNAME=$(ansible "$INSTANCE_NAME" -i "$INVENTORY_FULL" -m shell -a "hostname" 2>/dev/null | grep -v ">>>" | tail -1); then
    success "Command execution successful"
    info "Remote hostname: ${HOSTNAME}"
else
    error "Command execution failed"
    exit 1
fi

title "Connection Tests Complete"
success "All tests passed"
info ""
info "Next: ./configuration-db.sh -e $ENV -c $CUSTOMER"
