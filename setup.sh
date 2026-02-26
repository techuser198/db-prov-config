#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib.sh"

title "Database Automation Setup"

require_commands ssh-keygen sed

info "Making scripts executable..."
chmod +x \
    provision-db.sh \
    configuration-db.sh \
    destroy-db.sh \
    validate.sh \
    upload-secrets.sh \
    test-connection.sh \
    encrypt.sh \
    decrypt.sh \
    create-password-files.sh
success "Scripts are executable"

info "Creating directories..."
for env in dev cert prod; do
    for customer in AM AV CP NN; do
        mkdir -p "env/${env}/${customer}"
    done
done
mkdir -p ansible/files
success "Directory structure created"

info "Checking SSH keys..."
if [ ! -f "$HOME/.ssh/id_rsa" ]; then
    info "Generating SSH keys..."
    ssh-keygen -t rsa -b 4096 -C "postgres-automation@gcp" -f "$HOME/.ssh/id_rsa" -N ""
    success "SSH keys generated"
else
    success "SSH keys exist"
fi

title "Configuration Setup"
read -r -p "Enter GCP Project ID (or press Enter to skip): " PROJECT_ID

if [ -n "$PROJECT_ID" ]; then
    info "Updating config files with project: $PROJECT_ID"

    for file in env/*/*/db-config.yml; do
        if [ -f "$file" ]; then
            sed -i "s/YOUR_PROJECT_ID/$PROJECT_ID/g" "$file"
        fi
    done

    if [ -f "ansible/inventory/gcp.yml" ]; then
        sed -i "s/YOUR_PROJECT_ID/$PROJECT_ID/g" "ansible/inventory/gcp.yml"
    fi

    success "Config files updated"
else
    warning "Skipped project configuration"
    info "Update YOUR_PROJECT_ID manually in config files"
fi

title "Setup Complete"
success "Ready to use"
info ""
info "1. Authenticate with GCP:"
info "   gcloud auth login"
if [ -n "${PROJECT_ID:-}" ]; then
    info "   gcloud config set project $PROJECT_ID"
else
    info "   gcloud config set project <your-project-id>"
fi
info "   gcloud auth application-default login"
info ""
info "2. Run validation:"
info "   ./validate.sh"
info ""
info "3. Provision database:"
info "   ./provision-db.sh -e dev -c AM"
info "   ./configuration-db.sh -e dev -c AM"
