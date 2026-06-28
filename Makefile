SHELL    := /bin/bash
.DEFAULT_GOAL := help

APPS_DIR   := $(HOME)/acme-apps-azure
MODULE_DIR := $(HOME)/terraform-azurerm-static-site
DEV_TF     := $(APPS_DIR)/envs/dev/azure/main.tf
STG_TF     := $(APPS_DIR)/envs/staging/azure/main.tf
SSH        := GIT_SSH_COMMAND='ssh -i $(HOME)/.ssh/github-ngphban00 -o StrictHostKeyChecking=no'

TFC_DEV  := https://app.terraform.io/app/ngphban/acme-apps-azure-dev/runs
TFC_STG  := https://app.terraform.io/app/ngphban/acme-apps-azure-staging/runs

# Auto-detect next semver tag from module repo
LATEST_TAG   := $(shell cd $(MODULE_DIR) && git tag --sort=-v:refname | grep '^v' | head -1)
NEXT_TAG     := $(shell cd $(MODULE_DIR) && git tag --sort=-v:refname | grep '^v' | head -1 | \
                  awk -F'[v.]' '{printf "v%d.%d.%d", $$2, $$3, $$4+1}')
NEXT_MINOR   := $(shell cd $(MODULE_DIR) && git tag --sort=-v:refname | grep '^v' | head -1 | \
                  awk -F'[v.]' '{printf "~> %d.%d", $$2, $$3+1}')

C := \033[36m
R := \033[0m

.PHONY: help status \
        sentinel-fail sentinel-pass \
        module-publish app-upgrade \
        cli-plan-dev cli-plan-staging \
        reset

help: ## List all demo scenarios
	@printf "\n  $(C)ACME TFC Demo Runbook$(R)\n\n"
	@grep -E '^[a-zA-Z_-]+:.*## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS=":.*## "}; {printf "  $(C)make %-20s$(R) %s\n", $$1, $$2}'
	@printf "\n  Current module: $(C)$(LATEST_TAG)$(R)  →  next publish: $(C)$(NEXT_TAG)$(R)\n\n"

status: ## Show git log + module tags for both repos
	@printf "\n$(C)=== acme-apps-azure ===$(R)\n"
	@cd $(APPS_DIR) && git log --oneline -4
	@printf "\n$(C)=== terraform-azurerm-static-site ===$(R)\n"
	@cd $(MODULE_DIR) && git log --oneline -4
	@printf "Tags: " && cd $(MODULE_DIR) && git tag --sort=-v:refname | tr '\n' ' '
	@printf "\n\n"

# ── Sentinel ─────────────────────────────────────────────────────────────────

sentinel-fail: ## [Sentinel] Set access_tier=Hot → policy FAIL, apply blocked
	@printf "$(C)>>> Setting access_tier=Hot to violate Sentinel policy...$(R)\n"
	@python3 -c "\
import re; f='$(DEV_TF)'; c=open(f).read(); \
c=re.sub(r'access_tier\s*=\s*\"Cool\"','access_tier      = \"Hot\"',c); \
open(f,'w').write(c)"
	@cd $(APPS_DIR) && git add -A && \
	 git commit -m 'demo: set access_tier=Hot — should trigger Sentinel FAIL' && \
	 $(SSH) git push origin main
	@printf "\n  → $(TFC_DEV)\n\n"

sentinel-pass: ## [Sentinel] Revert access_tier=Cool → policy PASS, apply resumes
	@printf "$(C)>>> Reverting access_tier=Cool to fix Sentinel violation...$(R)\n"
	@python3 -c "\
import re; f='$(DEV_TF)'; c=open(f).read(); \
c=re.sub(r'access_tier\s*=\s*\"Hot\"','access_tier      = \"Cool\"',c); \
open(f,'w').write(c)"
	@cd $(APPS_DIR) && git add -A && \
	 git commit -m 'fix: revert access_tier=Cool — Sentinel compliant' && \
	 $(SSH) git push origin main
	@printf "\n  → $(TFC_DEV)\n\n"

# ── Module Registry ───────────────────────────────────────────────────────────

module-publish: ## [Module] Platform team publishes next version — adds new feature
	@printf "$(C)>>> Platform team: publishing module $(NEXT_TAG)...$(R)\n"
	@python3 $(APPS_DIR)/demo-scripts/patch_module_v1_3.py
	@cd $(MODULE_DIR) && git add -A && \
	 git commit -m 'feat: add new module feature — non-breaking' && \
	 git tag $(NEXT_TAG) && \
	 $(SSH) git push origin main && \
	 $(SSH) git push origin $(NEXT_TAG)
	@printf "\n  → $(NEXT_TAG) published. TFC Registry will detect via webhook.\n\n"

app-upgrade: ## [App] Application team upgrades to latest module version
	@printf "$(C)>>> Application team: upgrading to module $(NEXT_MINOR)...$(R)\n"
	@python3 -c "\
import re; f='$(DEV_TF)'; c=open(f).read(); \
c=re.sub(r'version = \"~> \d+\.\d+\"','version = \"$(NEXT_MINOR)\"',c); \
open(f,'w').write(c)"
	@cd $(APPS_DIR) && git add -A && \
	 git commit -m 'feat: upgrade to module $(NEXT_MINOR)' && \
	 $(SSH) git push origin main
	@printf "\n  → $(TFC_DEV)\n\n"

# ── CLI Workflow ──────────────────────────────────────────────────────────────

cli-plan-dev: ## [CLI] Run terraform plan locally — executes remotely on TFC Dev
	@printf "$(C)>>> Running terraform plan on dev (executes on TFC, streams locally)...$(R)\n"
	@cd $(APPS_DIR)/envs/dev/azure && terraform plan

cli-plan-staging: ## [CLI] Run terraform plan locally — executes remotely on TFC Staging
	@printf "$(C)>>> Running terraform plan on staging (executes on TFC, streams locally)...$(R)\n"
	@cd $(APPS_DIR)/envs/staging/azure && \
	 terraform init -upgrade -input=false 2>&1 | grep -E '(module|provider|initialized|Error)' && \
	 terraform plan

# ── Reset ─────────────────────────────────────────────────────────────────────

reset: ## Reset dev to clean state (Cool tier, module v1.0)
	@printf "$(C)>>> Resetting dev to clean state (v1.0)...$(R)\n"
	@python3 -c "\
import re; f='$(DEV_TF)'; c=open(f).read(); \
c=re.sub(r'access_tier\s*=\s*\"Hot\"','access_tier      = \"Cool\"',c); \
c=re.sub(r'version = \"~> \d+\.\d+\"','version = \"~> 1.0\"',c); \
open(f,'w').write(c)"
	@cd $(APPS_DIR) && \
	 git diff --quiet HEAD || ( \
	   git add -A && \
	   git commit -m 'chore: reset to clean demo state (Cool, v1.0)' && \
	   $(SSH) git push origin main)
	@printf "  ✓ Dev: access_tier=Cool, module version ~> 1.0\n\n"
