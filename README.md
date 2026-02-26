# Database Infrastructure Automation (GCP + Terraform + Ansible)

This repository provisions and configures PostgreSQL database VMs on Google Cloud.

It uses:
- Terraform for infrastructure provisioning
- Ansible for OS and PostgreSQL configuration
- GCP KMS + Secret Manager for credential handling

## Project Layout

- `provision-db.sh`: Provision GCP VM and generate inventory
- `configuration-db.sh`: Configure PostgreSQL and upload credentials
- `destroy-db.sh`: Destroy infrastructure and optional secrets
- `validate.sh`: Pre-flight environment validation
- `test-connection.sh`: Inventory and connectivity validation
- `create-password-files.sh`: Generate encrypted password files
- `upload-secrets.sh`: Push `.pass` values to Secret Manager
- `encrypt.sh` / `decrypt.sh`: KMS-based encryption helpers
- `terraform/`: Infrastructure definitions
- `ansible/`: Playbooks, roles, and inventories
- `env/<env>/<customer>/`: Per-environment/customer config and encrypted passwords

## Prerequisites

Required tools:
- `terraform`
- `ansible`, `ansible-playbook`, `ansible-inventory`
- `gcloud`
- `yq`
- `python3`

## Quick Start

1. First-time setup:
```bash
./setup.sh
```

2. Validate local environment:
```bash
./validate.sh
```

3. Create encrypted passwords:
```bash
./setup-secrets.sh -e dev -c AM
```

4. Provision infrastructure:
```bash
./provision-db.sh -e dev -c AM
```

5. Configure database:
```bash
./configuration-db.sh -e dev -c AM
```

## Operations

Plan-only operations:
```bash
./provision-db.sh -e dev -c AM -p
./destroy-db.sh -e dev -c AM -p
```

Connectivity testing:
```bash
./test-connection.sh -e dev -c AM
```

Destroy infrastructure:
```bash
./destroy-db.sh -e dev -c AM
```

Destroy infrastructure and related secrets:
```bash
./destroy-db.sh -e dev -c AM -s
```

## Security Notes

- Password files in `env/*/*/*.pass` are expected to contain encrypted values.
- Encryption/decryption relies on `secrets/kms-config.yml` and `env/<env>/common-config.yml`.
- Do not store plaintext credentials in this repository.

## Production Expectations

- Run `./validate.sh` before provisioning changes.
- Run shell syntax validation before commit (`make lint`).
- Prefer plan (`-p`) before apply/destroy in controlled environments.
