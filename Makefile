# ROSA HCP Cluster with Routable Pod CIDR - Makefile
# This Makefile provides targets for each major deployment step

.PHONY: help clean setup-cluster deploy-cilium test-pods status logs cluster-status cluster-logs cluster-delete network-cleanup tf-init tf-plan tf-apply tf-destroy tf-outputs cilium-deploy cilium-status cilium-logs cilium-test cilium-uninstall

# Default target
.DEFAULT_GOAL := help

# Variables
MANIFESTS_DIR := manifests
SCRIPTS_DIR := scripts
CLUSTER_NAME ?= rosa-hcp
ENVIRONMENT ?= dev
AWS_REGION ?= us-east-2

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[0;33m
BLUE := \033[0;34m
NC := \033[0m # No Color

help: ## Show this help message
	@echo "$(BLUE)ROSA HCP Cluster with Routable Pod CIDR - Available Targets$(NC)"
	@echo ""
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(YELLOW)Environment Variables:$(NC)"
	@echo "  CLUSTER_NAME    - Name of the cluster (default: rosa-hcp)"
	@echo "  ENVIRONMENT     - Environment name (default: dev)"
	@echo "  AWS_REGION      - AWS region (default: us-east-2)"
	@echo ""

## Cluster Management
setup-cluster: ## Setup ROSA HCP cluster using the automated script
	@echo "$(BLUE)Setting up ROSA HCP cluster...$(NC)"
	@echo "$(YELLOW)This will create a ROSA HCP cluster with no CNI mode$(NC)"
	@echo ""
	@echo "$(GREEN)Prerequisites:$(NC)"
	@echo "  - ROSA CLI installed and logged in (rosa login)"
	@echo "  - AWS CLI installed and configured"
	@echo "  - Proper AWS permissions for ROSA HCP"
	@echo ""
	@echo "$(GREEN)Creating cluster with script...$(NC)"
	chmod +x $(SCRIPTS_DIR)/create-rosa-cluster.sh
	CLUSTER_NAME=$(CLUSTER_NAME) $(SCRIPTS_DIR)/create-rosa-cluster.sh
	@echo ""
	@echo "$(GREEN)Next steps:$(NC)"
	@echo "  1. Deploy Cilium CNI: make deploy-cilium"
	@echo "  2. Test pod networking: make test-pods"

cluster-status: ## Check ROSA HCP cluster status
	@echo "$(BLUE)Checking cluster status...$(NC)"
	@if command -v rosa >/dev/null 2>&1; then \
		rosa describe cluster --cluster $(CLUSTER_NAME) 2>/dev/null || echo "Cluster not found or not accessible"; \
	else \
		echo "ROSA CLI not installed"; \
	fi

cluster-logs: ## Show ROSA HCP cluster logs
	@echo "$(BLUE)Showing cluster logs...$(NC)"
	@if command -v rosa >/dev/null 2>&1; then \
		rosa logs install --cluster=$(CLUSTER_NAME) --tail=50; \
	else \
		echo "ROSA CLI not installed"; \
	fi

cluster-delete: ## Delete ROSA HCP cluster
	@echo "$(RED)Deleting ROSA HCP cluster...$(NC)"
	@read -p "Are you sure you want to delete cluster '$(CLUSTER_NAME)'? [y/N]: " confirm && [ "$$confirm" = "y" ]
	@if command -v rosa >/dev/null 2>&1; then \
		rosa delete cluster --cluster=$(CLUSTER_NAME) --yes; \
	else \
		echo "ROSA CLI not installed"; \
	fi

## Network Management (Terraform)
tf-init: ## Initialize Terraform for network infrastructure
	@echo "$(BLUE)Initializing Terraform...$(NC)"
	cd terraform-vpc && terraform init

tf-plan: ## Plan Terraform network infrastructure
	@echo "$(BLUE)Planning Terraform deployment...$(NC)"
	cd terraform-vpc && terraform plan -out rosa.tfplan

tf-apply: ## Apply Terraform network infrastructure
	@echo "$(GREEN)Applying Terraform configuration...$(NC)"
	cd terraform-vpc && terraform apply rosa.tfplan

tf-destroy: ## Destroy Terraform network infrastructure
	@echo "$(RED)Destroying Terraform infrastructure...$(NC)"
	@read -p "Are you sure you want to destroy network infrastructure for '$(CLUSTER_NAME)'? [y/N]: " confirm && [ "$$confirm" = "y" ]
	cd terraform-vpc && terraform destroy -auto-approve

tf-outputs: ## Show Terraform outputs
	@echo "$(BLUE)Terraform outputs:$(NC)"
	cd terraform-vpc && terraform output

network: tf-init tf-plan tf-apply ## Create network infrastructure (init + plan + apply)

network-cleanup: tf-destroy ## Clean up network resources using Terraform

## CNI Deployment
deploy-cilium: ## Deploy Cilium CNI with AWS ENI mode using Helm
	@echo "$(BLUE)Deploying Cilium CNI using Helm...$(NC)"
	@echo "$(YELLOW)Make sure your cluster is ready and you're connected to it$(NC)"
	@echo ""
	$(SCRIPTS_DIR)/deploy-cilium.sh
	@echo ""
	@echo "$(GREEN)Cilium CNI deployment completed!$(NC)"

cilium-deploy: deploy-cilium ## Alias for deploy-cilium

cilium-status: ## Check Cilium CNI status
	@echo "$(BLUE)Checking Cilium CNI status...$(NC)"
	@echo ""
	@echo "$(GREEN)Cilium pods:$(NC)"
	oc get pods -n kube-system -l k8s-app=cilium
	@echo ""
	@echo "$(GREEN)Cilium operator pods:$(NC)"
	oc get pods -n kube-system -l name=cilium-operator
	@echo ""
	@echo "$(GREEN)Cilium status:$(NC)"
	@CILIUM_POD=$$(oc get pods -n kube-system -l k8s-app=cilium --no-headers | head -1 | awk '{print $$1}'); \
	if [ -n "$$CILIUM_POD" ]; then \
		oc exec -n kube-system "$$CILIUM_POD" -- cilium status --wait; \
	else \
		echo "No Cilium pods found"; \
	fi

cilium-logs: ## Show Cilium CNI logs
	@echo "$(BLUE)Showing Cilium CNI logs...$(NC)"
	oc logs -n kube-system -l k8s-app=cilium --tail=50

cilium-test: ## Run Cilium connectivity test
	@echo "$(BLUE)Running Cilium connectivity test...$(NC)"
	@CILIUM_POD=$$(oc get pods -n kube-system -l k8s-app=cilium --no-headers | head -1 | awk '{print $$1}'); \
	if [ -n "$$CILIUM_POD" ]; then \
		oc exec -n kube-system "$$CILIUM_POD" -- cilium connectivity test; \
	else \
		echo "No Cilium pods found"; \
	fi

cilium-uninstall: ## Uninstall Cilium CNI and clean up AWS IAM resources
	@echo "$(RED)Uninstalling Cilium CNI and cleaning up AWS resources...$(NC)"
	@echo "$(YELLOW)This will remove Cilium and all associated AWS IAM resources$(NC)"
	@read -p "Are you sure you want to uninstall Cilium? [y/N]: " confirm && [ "$$confirm" = "y" ]
	$(SCRIPTS_DIR)/uninstall-cilium.sh
	@echo ""
	@echo "$(GREEN)Cilium uninstall completed!$(NC)"

## Testing and Validation
test-pods: ## Test pod networking with sample applications
	@echo "$(BLUE)Testing pod networking...$(NC)"
	@echo "$(GREEN)1. Creating test namespace...$(NC)"
	kubectl create namespace test-pods --dry-run=client -o yaml | kubectl apply -f -
	@echo ""
	@echo "$(GREEN)2. Deploying test pod...$(NC)"
	kubectl run test-pod --image=nginx:alpine -n test-pods
	kubectl wait --for=condition=ready pod test-pod -n test-pods --timeout=60s
	@echo ""
	@echo "$(GREEN)3. Getting pod IP...$(NC)"
	kubectl get pod test-pod -n test-pods -o jsonpath='{.status.podIP}'
	@echo ""
	@echo "$(GREEN)4. Testing connectivity...$(NC)"
	kubectl exec test-pod -n test-pods -- curl -s http://localhost
	@echo ""
	@echo "$(GREEN)5. Cleaning up test pod...$(NC)"
	kubectl delete pod test-pod -n test-pods
	kubectl delete namespace test-pods
	@echo "$(GREEN)Pod networking test completed$(NC)"

## Monitoring and Status
status: ## Show cluster and CNI status
	@echo "$(BLUE)Cluster Status$(NC)"
	@echo "$(GREEN)ROSA HCP Cluster:$(NC)"
	@if command -v rosa >/dev/null 2>&1; then \
		rosa describe cluster --cluster $(CLUSTER_NAME) 2>/dev/null || echo "Cluster not found or not accessible"; \
	else \
		echo "ROSA CLI not installed"; \
	fi
	@echo ""
	@echo "$(GREEN)Cilium CNI Status:$(NC)"
	@if kubectl get pods -n kube-system -l k8s-app=cilium >/dev/null 2>&1; then \
		kubectl get pods -n kube-system -l k8s-app=cilium; \
	else \
		echo "Cilium not deployed or cluster not accessible"; \
	fi

logs: ## Show logs from Cilium pods
	@echo "$(BLUE)Showing Cilium logs...$(NC)"
	kubectl logs -n kube-system -l k8s-app=cilium --tail=50

## Cleanup
clean: ## Clean up temporary files
	@echo "$(BLUE)Cleaning up temporary files...$(NC)"
	rm -f *.json
	rm -f *.log
	@echo "$(GREEN)Cleanup completed$(NC)"

clean-all: ## Clean up everything (cluster + network + files)
	@echo "$(RED)This will delete the cluster, network, and clean up files$(NC)"
	@read -p "Are you sure? [y/N]: " confirm && [ "$$confirm" = "y" ]
	$(MAKE) cluster-delete
	$(MAKE) network-cleanup
	$(MAKE) clean
	@echo "$(GREEN)Complete cleanup finished$(NC)"

## Development and Maintenance

## Documentation
docs: ## Generate documentation
	@echo "$(BLUE)Generating documentation...$(NC)"
	@echo "$(GREEN)Documentation is available in:$(NC)"
	@echo "  - README.md - Project overview"
	@echo "  - design.md - Architecture and design"
	@echo "  - manifests/ - Kubernetes manifests"
	@echo "  - scripts/ - Deployment scripts"

## Quick Start
quick-start: ## Quick start deployment (network + cluster + CNI)
	@echo "$(BLUE)Starting quick deployment...$(NC)"
	$(MAKE) network
	$(MAKE) setup-cluster
	$(MAKE) deploy-cilium
	@echo "$(GREEN)Quick start completed$(NC)"

## Full Deployment
deploy-all: ## Full deployment (network + cluster + CNI + testing)
	@echo "$(BLUE)Starting full deployment...$(NC)"
	@echo "$(GREEN)Step 1: Create network infrastructure$(NC)"
	$(MAKE) network
	@echo ""
	@echo "$(GREEN)Step 2: Create ROSA HCP cluster$(NC)"
	$(MAKE) setup-cluster
	@echo ""
	@echo "$(GREEN)Step 3: Deploy Cilium CNI$(NC)"
	$(MAKE) deploy-cilium
	@echo ""
	@echo "$(GREEN)Step 4: Test pod networking$(NC)"
	$(MAKE) test-pods
	@echo ""
	@echo "$(GREEN)Full deployment completed successfully!$(NC)"
