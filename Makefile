SHELL    := /bin/bash
.DEFAULT_GOAL := help

APPS_DIR   := $(HOME)/acme-apps-azure
MODULE_DIR := $(HOME)/terraform-azurerm-static-site
DEV_TF     := $(APPS_DIR)/envs/dev/azure/main.tf
STG_TF     := $(APPS_DIR)/envs/staging/azure/main.tf
SSH        := GIT_SSH_COMMAND='ssh -i $(HOME)/.ssh/github-ngphban00 -o StrictHostKeyChecking=no'

TFC_DEV  := https://app.terraform.io/app/ngphban/acme-apps-azure-dev/runs
TFC_STG  := https://app.terraform.io/app/ngphban/acme-apps-azure-staging/runs

C := \033[36m
R := \033[0m

.PHONY: help status \
        sentinel-fail sentinel-pass \
        module-publish app-upgrade \
        cli-plan-dev cli-plan-staging \
        reset

help: ## Danh sách demo scenarios
	@printf "\n  $(C)ACME TFC Demo Runbook$(R)\n\n"
	@grep -E '^[a-zA-Z_-]+:.*## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS=":.*## "}; {printf "  $(C)make %-20s$(R) %s\n", $$1, $$2}'
	@printf "\n"

status: ## Git log + module tags của cả 2 repos
	@printf "\n$(C)=== acme-apps-azure ===$(R)\n"
	@cd $(APPS_DIR) && git log --oneline -4
	@printf "\n$(C)=== terraform-azurerm-static-site ===$(R)\n"
	@cd $(MODULE_DIR) && git log --oneline -4
	@printf "Tags: " && cd $(MODULE_DIR) && git tag --sort=-v:refname | tr '\n' ' '
	@printf "\n\n"

# ── Sentinel ─────────────────────────────────────────────────────────────────

sentinel-fail: ## [Sentinel] Đổi access_tier=Hot → Sentinel FAIL, apply bị block
	@printf "$(C)>>> Đổi access_tier=Hot để vi phạm Sentinel policy...$(R)\n"
	@python3 -c "\
import re; f='$(DEV_TF)'; c=open(f).read(); \
c=re.sub(r'access_tier\s*=\s*\"Cool\"','access_tier      = \"Hot\"',c); \
open(f,'w').write(c)"
	@cd $(APPS_DIR) && git add -A && \
	 git commit -m 'demo: set access_tier=Hot — should trigger Sentinel FAIL' && \
	 $(SSH) git push origin main
	@printf "\n  → $(TFC_DEV)\n\n"

sentinel-pass: ## [Sentinel] Revert access_tier=Cool → Sentinel PASS, apply tiếp tục
	@printf "$(C)>>> Revert access_tier=Cool để fix Sentinel violation...$(R)\n"
	@python3 -c "\
import re; f='$(DEV_TF)'; c=open(f).read(); \
c=re.sub(r'access_tier\s*=\s*\"Hot\"','access_tier      = \"Cool\"',c); \
open(f,'w').write(c)"
	@cd $(APPS_DIR) && git add -A && \
	 git commit -m 'fix: revert access_tier=Cool — Sentinel compliant' && \
	 $(SSH) git push origin main
	@printf "\n  → $(TFC_DEV)\n\n"

# ── Module Registry ───────────────────────────────────────────────────────────

module-publish: ## [Module] Platform team publish v1.3.0 — thêm min_tls_version
	@printf "$(C)>>> Platform team: patch module + publish v1.3.0...$(R)\n"
	@python3 $(APPS_DIR)/demo-scripts/patch_module_v1_3.py
	@cd $(MODULE_DIR) && git add -A && \
	 git commit -m 'feat: add min_tls_version variable (default TLS1_2) — non-breaking' && \
	 git tag v1.3.0 && \
	 $(SSH) git push origin main && \
	 $(SSH) git push origin v1.3.0
	@printf "\n  → v1.3.0 tagged. TFC Registry sẽ detect qua webhook.\n\n"

app-upgrade: ## [App] Application team upgrade lên module v1.3
	@printf "$(C)>>> Application team: upgrade version constraint lên v1.3...$(R)\n"
	@python3 -c "\
import re; f='$(DEV_TF)'; c=open(f).read(); \
c=re.sub(r'version = \"~> 1\.\d+\"','version = \"~> 1.3\"',c); \
open(f,'w').write(c)"
	@cd $(APPS_DIR) && git add -A && \
	 git commit -m 'feat: upgrade to module v1.3' && \
	 $(SSH) git push origin main
	@printf "\n  → $(TFC_DEV)\n\n"

# ── CLI Workflow ──────────────────────────────────────────────────────────────

cli-plan-dev: ## [CLI] terraform plan từ local → chạy remote trên TFC Dev
	@printf "$(C)>>> terraform plan (executes on TFC, output streams locally)...$(R)\n"
	@cd $(APPS_DIR)/envs/dev/azure && terraform plan

cli-plan-staging: ## [CLI] terraform plan từ local → chạy remote trên TFC Staging
	@printf "$(C)>>> terraform plan staging (executes on TFC, output streams locally)...$(R)\n"
	@cd $(APPS_DIR)/envs/staging/azure && \
	 terraform init -upgrade -input=false 2>&1 | grep -E '(module|provider|initialized|Error)' && \
	 terraform plan

# ── Reset ─────────────────────────────────────────────────────────────────────

reset: ## Reset dev về clean state (Cool tier, module v1.2)
	@printf "$(C)>>> Reset dev về clean state...$(R)\n"
	@python3 -c "\
import re; f='$(DEV_TF)'; c=open(f).read(); \
c=re.sub(r'access_tier\s*=\s*\"Hot\"','access_tier      = \"Cool\"',c); \
c=re.sub(r'version = \"~> 1\.\d+\"','version = \"~> 1.2\"',c); \
open(f,'w').write(c)"
	@cd $(APPS_DIR) && \
	 git diff --quiet HEAD || ( \
	   git add -A && \
	   git commit -m 'chore: reset to clean demo state (Cool, v1.2)' && \
	   $(SSH) git push origin main)
	@printf "  ✓ Dev: access_tier=Cool, module version ~> 1.2\n\n"
