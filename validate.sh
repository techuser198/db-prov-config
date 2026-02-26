#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib.sh"

title "Pre-flight Validation Check"

ERRORS=0
WARNINGS=0

check_cmd() {
    local cmd=$1
    local name=$2
    local version_cmd=$3

    echo -n "-> $name... "
    if command -v "$cmd" >/dev/null 2>&1; then
        local version
        version=$(eval "$version_cmd" 2>/dev/null || echo "installed")
        echo "OK: $version"
        return 0
    fi

    echo "MISSING"
    ((ERRORS++))
    return 1
}

check_exists() {
    local file=$1
    local name=$2

    echo -n "-> $name... "
    if [ -f "$file" ]; then
        echo "OK"
        return 0
    fi

    echo "MISSING"
    ((ERRORS++))
    return 1
}

has_placeholder() {
    local file=$1
    local pattern=$2
    local name=$3

    if [ -f "$file" ] && grep -q "$pattern" "$file"; then
        echo "  WARN: $name still has placeholder"
        ((WARNINGS++))
        return 0
    fi

    return 1
}

info "Checking required commands..."
check_cmd "terraform" "Terraform" "terraform version | head -n1"
check_cmd "ansible" "Ansible" "ansible --version | head -n1"
check_cmd "ansible-playbook" "Ansible Playbook" "echo installed"
check_cmd "gcloud" "Google Cloud SDK" "gcloud version 2>&1 | head -n1"
check_cmd "yq" "yq YAML processor" "yq --version"
check_cmd "python3" "Python 3" "python3 --version"
echo ""

info "Checking SSH configuration..."
check_exists "$HOME/.ssh/id_rsa" "SSH private key"
check_exists "$HOME/.ssh/id_rsa.pub" "SSH public key"
echo ""

info "Checking GCP authentication..."
echo -n "-> GCP authentication... "
if gcloud auth application-default print-access-token >/dev/null 2>&1; then
    PROJECT=$(gcloud config get-value project 2>/dev/null || true)
    echo "OK ($PROJECT)"
else
    echo "FAILED"
    echo "  Run: gcloud auth application-default login"
    ((ERRORS++))
fi
echo ""

info "Checking Ansible dependencies..."
echo -n "-> Ansible GCP collection... "
if ansible-galaxy collection list 2>/dev/null | grep -q "google.cloud"; then
    echo "OK"
else
    echo "WARN: Installing..."
    ansible-galaxy collection install google.cloud
    ((WARNINGS++))
fi

echo -n "-> Python GCP libraries... "
if python3 -c "import google.auth" >/dev/null 2>&1; then
    echo "OK"
else
    echo "MISSING"
    echo "  Run: pip3 install google-auth google-auth-oauthlib"
    ((ERRORS++))
fi
echo ""

info "Checking PostgreSQL configuration..."

echo -n "-> Configuration files... "
CONFIG_FOUND=0
for env in dev cert prod; do
    for customer in AM AV CP NN; do
        [ -f "env/$env/$customer/db-config.yml" ] && ((CONFIG_FOUND++))
    done
done

if [ "$CONFIG_FOUND" -gt 0 ]; then
    echo "OK: Found $CONFIG_FOUND"
else
    echo "MISSING"
    ((ERRORS++))
fi

info "Checking for placeholders..."
has_placeholder "env/dev/AM/db-config.yml" "YOUR_PROJECT_ID" "env/dev/AM/db-config.yml"
has_placeholder "ansible/inventory/gcp.yml" "YOUR_PROJECT_ID" "ansible/inventory/gcp.yml"

echo ""
title "Validation Report"

if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    success "All checks passed. Ready to go"
    info ""
    info "Next steps:"
    info "  1. ./provision-db.sh -e dev -c AM"
    info "  2. ./configuration-db.sh -e dev -c AM"
elif [ "$ERRORS" -eq 0 ]; then
    warning "Found $WARNINGS warning(s) - can proceed"
    info ""
    info "Next steps:"
    info "  1. Address warnings above"
    info "  2. ./provision-db.sh -e dev -c AM"
    info "  3. ./configuration-db.sh -e dev -c AM"
else
    error "Found $ERRORS error(s) - please fix before proceeding"
    if [ "$WARNINGS" -gt 0 ]; then
        warning "Also found $WARNINGS warning(s)"
    fi
    exit 1
fi
