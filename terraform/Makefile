# Usage: make <target> ENV=dev|uat|prod
#
#   make init ENV=dev          # terraform init with dev's backend config
#   make plan ENV=dev          # terraform plan (zips app/ and agent/, builds the layer)
#   make apply ENV=dev         # terraform apply
#   make destroy ENV=dev       # terraform destroy (asks for confirmation)
#   make fmt                   # terraform fmt -recursive
#   make validate ENV=dev      # terraform validate
#   make alarm-ok ENV=dev      # reset the errors alarm to OK
#   make alarm-test ENV=dev    # OK -> ALARM: real event through EventBridge to the agent

SHELL := /bin/bash

ENV ?= dev
ALARM := $(shell grep '^function_name' tfvars/$(ENV).tfvars | cut -d'"' -f2)-$(ENV)-errors

ENVS := dev uat prod
ifneq ($(filter $(ENV),$(ENVS)),$(ENV))
$(error ENV must be one of: $(ENVS) — got "$(ENV)")
endif

.PHONY: init plan apply destroy fmt validate alarm-ok alarm-test

init:
	terraform init -backend-config=backend/$(ENV).tfbackend -reconfigure

plan: init
	terraform plan -var-file=tfvars/$(ENV).tfvars

apply: init
	terraform apply -var-file=tfvars/$(ENV).tfvars

destroy: init
	terraform destroy -var-file=tfvars/$(ENV).tfvars

fmt:
	terraform fmt -recursive

validate: init
	terraform validate

alarm-ok:
	aws cloudwatch set-alarm-state --alarm-name $(ALARM) \
		--state-value OK --state-reason "manual reset"

# Only a state change emits an event, so go through OK first.
alarm-test: alarm-ok
	aws cloudwatch set-alarm-state --alarm-name $(ALARM) \
		--state-value ALARM --state-reason "manual end-to-end test"
	@echo "Agent triggered. Follow it with:"
	@echo "  aws logs tail /aws/lambda/$(subst -errors,-agent,$(ALARM)) --follow"
