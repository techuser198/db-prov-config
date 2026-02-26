#!/usr/bin/env bash
# Shared utility functions for database automation.

# Logging helpers
info() {
    echo "-> $*"
}

success() {
    echo "OK: $*"
}

error() {
    echo "ERROR: $*" >&2
}

warning() {
    echo "WARN: $*"
}

title() {
    echo ""
    echo "========================================="
    echo "$*"
    echo "========================================="
    echo ""
}

# Validation helpers
require_command() {
    local cmd=$1
    if ! command -v "$cmd" >/dev/null 2>&1; then
        error "$cmd is not installed"
        exit 1
    fi
}

require_commands() {
    local cmd
    for cmd in "$@"; do
        require_command "$cmd"
    done
}

require_file() {
    local file=$1
    if [ ! -f "$file" ]; then
        error "File not found: $file"
        exit 1
    fi
}

require_variable() {
    local name=$1
    local value=${2:-}
    if [ -z "$value" ]; then
        error "$name is required"
        exit 1
    fi
}

# Configuration helpers
get_config() {
    local file=$1
    local path=$2
    local default=${3:-}
    local result

    result=$(yq "$path" "$file" -r 2>/dev/null || true)

    if [ -z "$result" ] || [ "$result" = "null" ]; then
        echo "$default"
    else
        echo "$result"
    fi
}

validate_config_exists() {
    local env=$1
    local customer=$2
    local config="env/${env}/${customer}/db-config.yml"

    if [ ! -f "$config" ]; then
        error "Config file not found: $config"
        exit 1
    fi

    echo "$config"
}

validate_inventory_exists() {
    local env=$1
    local customer=$2
    local inventory="ansible/inventory/hosts_${env}_${customer}.yml"

    if [ ! -f "$inventory" ]; then
        error "Inventory file not found: $inventory"
        error "Run provision-db.sh first to create the VM"
        exit 1
    fi

    echo "$inventory"
}

# Utility helpers
to_lowercase() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

build_instance_name() {
    local db_type=${1:-postgres}
    local region=$2
    local customer=$3
    local env=$4

    echo "db-${db_type}-${region}-$(to_lowercase "$customer")-$(to_lowercase "$env")"
}

# Argument parsing
parse_args() {
    OPTIND=1
    while getopts "e:c:pfs" opt; do
        case $opt in
            e) export ENV=$OPTARG ;;
            c) export CUSTOMER=$OPTARG ;;
            p) export PLAN_ONLY=true ;;
            f) export FORCE=true ;;
            s) export DELETE_SECRETS=true ;;
            *) return 1 ;;
        esac
    done
    return 0
}

# Confirmation prompt
confirm() {
    local prompt=$1
    local response

    echo "$prompt (type 'yes' to confirm, anything else to cancel):"
    read -r response

    [ "$response" = "yes" ]
}

exit_error() {
    error "$*"
    exit 1
}

run_or_exit() {
    if ! "$@"; then
        exit_error "Command failed: $*"
    fi
}

terraform_init() {
    info "Initializing Terraform..."
    (
        cd terraform || exit 1
        run_or_exit terraform init -upgrade
    ) || exit_error "Terraform init failed"
    success "Terraform initialized"
}

terraform_plan() {
    (
        cd terraform || exit 1
        terraform plan -input=false "$@"
    ) || exit_error "Terraform plan failed"
}

terraform_apply() {
    (
        cd terraform || exit 1
        terraform apply -auto-approve -input=false "$@"
    ) || exit_error "Terraform apply failed"
}

terraform_destroy_plan() {
    (
        cd terraform || exit 1
        terraform plan -destroy -input=false "$@"
    ) || exit_error "Terraform destroy plan failed"
}

terraform_destroy() {
    (
        cd terraform || exit 1
        terraform destroy -auto-approve -input=false "$@"
    ) || exit_error "Terraform destroy failed"
}
