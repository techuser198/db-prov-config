SHELL := /usr/bin/env bash

.PHONY: lint validate setup

lint:
	bash -n provision-db.sh configuration-db.sh destroy-db.sh test-connection.sh validate.sh upload-secrets.sh setup.sh create-password-files.sh decrypt.sh encrypt.sh lib.sh setup-secrets.sh

validate:
	./validate.sh

setup:
	./setup.sh
