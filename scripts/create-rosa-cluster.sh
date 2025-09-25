#!/bin/bash

# ROSA HCP Cluster Deployment Script
# This script creates a ROSA HCP cluster with no CNI mode using the CLI

set -eox  # Exit on any error

# Configuration variables
REGION="us-east-2"
CLUSTER_NAME="${CLUSTER_NAME:-$(whoami)}"
VPC_CIDR="10.0.0.0/16"
AZ_COUNT=3
MACHINE_TYPE="m5.xlarge"
REPLICAS=3
MULTI_AZ=true
ADMIN_PASSWORD="${ADMIN_PASSWORD:-$(openssl rand -base64 12)}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command_exists rosa; then
        log_error "ROSA CLI is not installed. Please install it first."
        exit 1
    fi

    if ! command_exists aws; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi

    # Check if logged into ROSA
    if ! rosa whoami >/dev/null 2>&1; then
        log_error "Not logged into ROSA CLI. Please run 'rosa login' first."
        exit 1
    fi

    # Check if logged into AWS
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "Not logged into AWS CLI. Please run 'aws configure' first."
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Function to create network using Terraform
create_network() {
    log_info "Creating VPC and subnets using Terraform..."

    local terraform_dir="terraform-vpc"

    # Check if terraform is installed
    if ! command_exists terraform; then
        log_error "Terraform is not installed. Please install it first."
        exit 1
    fi

    # Create terraform.tfvars file
    cat > "$terraform_dir/terraform.tfvars" << EOF
region = "$REGION"
cluster_name = "$CLUSTER_NAME"
vpc_cidr = "$VPC_CIDR"
subnet_azs = []
single_az_only = false
private_subnets_only = false
EOF

    # Change to terraform directory
    cd "$terraform_dir"

    # Initialize Terraform
    log_info "Initializing Terraform..."
    terraform init

    # Plan the deployment
    log_info "Planning Terraform deployment..."
    terraform plan -out rosa.tfplan

    # Apply the configuration
    log_info "Applying Terraform configuration..."
    terraform apply rosa.tfplan

    # Get outputs
    log_info "Getting Terraform outputs..."
    SUBNET_IDS=$(terraform output -raw cluster-subnets-string)
    VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "unknown")

    # Return to original directory
    cd ..

    log_success "Network infrastructure created successfully"
    log_info "VPC ID: $VPC_ID"
    log_info "Subnet IDs: $SUBNET_IDS"
}

# Function to check if cluster already exists
check_existing_cluster() {
    log_info "Checking if cluster '$CLUSTER_NAME' already exists..."

    log_info "Running: rosa describe cluster --cluster=$CLUSTER_NAME"
    local cluster_info
    cluster_info=$(rosa describe cluster --cluster="$CLUSTER_NAME" 2>/dev/null)
    local cluster_exit_code=$?

    if [ $cluster_exit_code -eq 0 ]; then
        log_success "Cluster '$CLUSTER_NAME' already exists!"
        log_info "Skipping creation and displaying cluster information..."
        display_cluster_info
        exit 0
    else
        log_info "Cluster '$CLUSTER_NAME' does not exist, proceeding with creation..."
    fi
}

# Function to check for existing operator roles
check_existing_operator_roles() {
    log_info "Checking for existing operator roles with prefix: $CLUSTER_NAME"

    local existing_roles=$(rosa list operator-roles 2>/dev/null | grep "$CLUSTER_NAME" || true)

    if [ -n "$existing_roles" ]; then
        log_error "Found existing operator roles with prefix '$CLUSTER_NAME':"
        echo "$existing_roles"
        echo ""
        log_error "Operator roles are tied to a specific OIDC configuration."
        log_error "You must delete the existing operator roles before creating a new OIDC config."
        log_info "To delete existing operator roles, run:"
        log_info "  rosa delete operator-roles --prefix $CLUSTER_NAME --yes"
        log_info "Then run this script again."
        exit 1
    else
        log_success "No existing operator roles found with prefix: $CLUSTER_NAME"
    fi
}

# Function to create OIDC config and provider
create_oidc_config() {
    log_info "Creating new OIDC configuration using two-step approach..."

    # Step 1: Create OIDC config
    log_info "Step 1: Creating OIDC config..."
    log_info "Running: rosa create oidc-config --managed --yes --mode auto -o json"
    local oidc_config_output
    oidc_config_output=$(rosa create oidc-config --managed --yes --mode auto -o json 2>&1)
    local oidc_config_exit_code=$?

    log_info "OIDC config creation output:"
    echo "$oidc_config_output"

    if [ $oidc_config_exit_code -eq 0 ]; then
        # Extract OIDC config ID from JSON output
        OIDC_CONFIG_ID=$(echo "$oidc_config_output" | jq -r '.id')
        if [ -n "$OIDC_CONFIG_ID" ] && [ "$OIDC_CONFIG_ID" != "null" ]; then
            log_success "Created OIDC config: $OIDC_CONFIG_ID"
        else
            log_error "Failed to extract OIDC config ID from JSON output"
            log_error "Output: $oidc_config_output"
            exit 1
        fi
    else
        log_error "Failed to create OIDC config"
        log_error "Error: $oidc_config_output"
        exit 1
    fi

    # Step 2: Create OIDC provider
    log_info "Step 2: Creating OIDC provider..."
    log_info "Running: rosa create oidc-provider --oidc-config-id $OIDC_CONFIG_ID --mode auto --yes"
    local oidc_provider_output
    oidc_provider_output=$(rosa create oidc-provider --oidc-config-id "$OIDC_CONFIG_ID" --mode auto --yes 2>&1)
    local oidc_provider_exit_code=$?

    log_info "OIDC provider creation output:"
    echo "$oidc_provider_output"

    if [ $oidc_provider_exit_code -eq 0 ]; then
        log_success "Created OIDC provider for config: $OIDC_CONFIG_ID"
    else
        log_error "Failed to create OIDC provider"
        log_error "Error: $oidc_provider_output"
        exit 1
    fi

    # Verify the provider was created
    log_info "Verifying OIDC provider was created..."
    log_info "Running: rosa list oidc-providers -o json | jq -r '.[] | select(.arn | contains(\"$OIDC_CONFIG_ID\"))'"
    local provider_check
    provider_check=$(rosa list oidc-providers -o json | jq -r ".[] | select(.arn | contains(\"$OIDC_CONFIG_ID\"))" 2>&1)

    if [ -n "$provider_check" ] && [ "$provider_check" != "null" ]; then
        log_success "OIDC provider verified: $OIDC_CONFIG_ID"
    else
        log_error "OIDC provider verification failed for: $OIDC_CONFIG_ID"
        log_error "Provider check output: $provider_check"
        exit 1
    fi
}


# Function to create account roles
create_account_roles() {
    log_info "Creating account roles for HCP cluster..."

    local role_prefix="${CLUSTER_NAME}"

    # Check if roles already exist
    log_info "Running: rosa list account-roles | grep $role_prefix"
    if rosa list account-roles | grep -q "$role_prefix"; then
        log_warning "Account roles with prefix '$role_prefix' already exist, skipping creation"
        log_info "Using existing account roles with prefix: $role_prefix"
    else
        log_info "Running: rosa create account-roles --mode auto --prefix $role_prefix --hosted-cp"
        rosa create account-roles \
            --mode auto \
            --prefix "$role_prefix" \
            --hosted-cp

        log_success "Account roles created successfully"
    fi
}

# Function to create operator roles
create_operator_roles() {
    log_info "Creating operator roles for HCP cluster..."

    # Check if operator roles already exist for this cluster
    log_info "Running: rosa list operator-roles | grep $CLUSTER_NAME"
    if rosa list operator-roles | grep -q "$CLUSTER_NAME"; then
        log_warning "Operator roles for cluster '$CLUSTER_NAME' already exist, skipping creation"
        log_info "Using existing operator roles for cluster: $CLUSTER_NAME"
    else
        # Create operator roles using the prefix approach (before cluster exists)
        local role_prefix="${CLUSTER_NAME}"
        log_info "Running: aws sts get-caller-identity --query Account --output text"
        local installer_role_arn="arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/${role_prefix}-HCP-ROSA-Installer-Role"
        log_info "Installer role ARN: $installer_role_arn"

        log_info "Running: rosa create operator-roles --mode auto --prefix $role_prefix --oidc-config-id $OIDC_CONFIG_ID --role-arn $installer_role_arn --hosted-cp"
        rosa create operator-roles \
            --mode auto \
            --prefix "$role_prefix" \
            --oidc-config-id "$OIDC_CONFIG_ID" \
            --role-arn "$installer_role_arn" \
            --hosted-cp
        log_success "Operator roles created successfully"
    fi
}

# Function to create the cluster
create_cluster() {
    log_info "Creating ROSA HCP cluster with no CNI mode..."

    local role_prefix="${CLUSTER_NAME}"

    # Check if cluster already exists
    if rosa list clusters | grep -q "$CLUSTER_NAME"; then
        log_warning "Cluster '$CLUSTER_NAME' already exists, using existing one"
        # Get existing cluster info
        rosa describe cluster --cluster "$CLUSTER_NAME" --output json > cluster-info.json

        # Check if cluster is ready
        local cluster_state=$(jq -r '.state' cluster-info.json)
        if [ "$cluster_state" = "ready" ]; then
            log_success "Cluster is already ready"
            log_info "Cluster ID: $(jq -r '.id' cluster-info.json)"
            log_info "Cluster Console URL: $(jq -r '.console.url' cluster-info.json)"
            return 0
        else
            log_info "Cluster exists but is in state: $cluster_state"
            log_info "Monitoring cluster creation progress..."
            monitor_cluster_creation
            return 0
        fi
    fi

    # Get account role ARNs
    local installer_role_arn="arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/${role_prefix}-HCP-ROSA-Installer-Role"
    local support_role_arn="arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/${role_prefix}-HCP-ROSA-Support-Role"
    local worker_role_arn="arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/${role_prefix}-HCP-ROSA-Worker-Role"

    # Create the cluster
    log_info "Running: rosa create cluster with admin password"
    rosa create cluster \
        --cluster-name "$CLUSTER_NAME" \
        --region "$REGION" \
        --hosted-cp \
        --sts \
        --mode auto \
        --role-arn "$installer_role_arn" \
        --support-role-arn "$support_role_arn" \
        --worker-iam-role-arn "$worker_role_arn" \
        --operator-roles-prefix "$role_prefix" \
        --oidc-config-id "$OIDC_CONFIG_ID" \
        --subnet-ids "$SUBNET_IDS" \
        --compute-machine-type "$MACHINE_TYPE" \
        --replicas "$REPLICAS" \
        --multi-az \
        --no-cni \
        --admin-password "$ADMIN_PASSWORD" \
        --output json > cluster-info.json

    log_success "ROSA HCP cluster creation initiated successfully"
    log_info "Cluster ID: $(jq -r '.id' cluster-info.json)"
    log_info "Cluster Console URL: $(jq -r '.console.url' cluster-info.json)"

    # Start monitoring the cluster creation
    monitor_cluster_creation
}

# Function to wait for cluster to reach installing status
wait_for_installing_status() {
    log_info "Waiting for cluster to reach 'installing' status..."

    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        local status=$(rosa describe cluster --cluster="$CLUSTER_NAME" --output json 2>/dev/null | jq -r '.state' 2>/dev/null)

        if [ "$status" = "installing" ]; then
            log_success "Cluster is now installing!"
            return 0
        elif [ "$status" = "ready" ]; then
            log_success "Cluster is already ready!"
            return 0
        elif [ "$status" = "error" ] || [ "$status" = "failed" ]; then
            log_error "Cluster creation failed with status: $status"
            exit 1
        else
            log_info "Cluster status: $status (attempt $attempt/$max_attempts)"
            sleep 30
            attempt=$((attempt + 1))
        fi
    done

    log_warning "Cluster did not reach installing status within expected time"
    log_info "Current status: $(rosa describe cluster --cluster="$CLUSTER_NAME" --output json 2>/dev/null | jq -r '.state' 2>/dev/null)"
    return 1
}

# Function to monitor cluster creation
monitor_cluster_creation() {
    log_info "Monitoring cluster creation progress with real-time logs..."

    # Wait for cluster to reach installing status before tailing logs
    if wait_for_installing_status; then
        log_info "Starting real-time log monitoring..."
        log_info "This will show live installation logs and automatically complete when ready"

        # Use rosa logs install --watch which provides real-time feedback and exits when ready
        rosa logs install --cluster="$CLUSTER_NAME" --watch

        if [ $? -eq 0 ]; then
            log_success "Cluster is ready!"
        else
            log_error "Cluster creation failed or was interrupted"
            log_info "Check cluster status: rosa describe cluster --cluster $CLUSTER_NAME"
            exit 1
        fi
    else
        log_warning "Proceeding with log monitoring despite status check issues..."
        rosa logs install --cluster="$CLUSTER_NAME" --watch
    fi
}

# Function to display cluster information
display_cluster_info() {
    log_info "Cluster Information:"
    echo "===================="
    echo "Cluster Name: $CLUSTER_NAME"
    echo "Region: $REGION"
    echo "VPC CIDR: $VPC_CIDR"
    echo "Availability Zones: $AZ_COUNT"
    echo "Machine Type: $MACHINE_TYPE"
    echo "Replicas: $REPLICAS"
    echo "Multi-AZ: $MULTI_AZ"
    echo "CNI Mode: No CNI (custom CNI required)"
    echo "Admin Password: $ADMIN_PASSWORD"
    echo ""

    if [ -f "cluster-info.json" ]; then
        echo "Cluster Console URL: $(jq -r '.console.url' cluster-info.json)"
        echo "Cluster API URL: $(jq -r '.api.url' cluster-info.json)"
        echo ""
        echo "Login Command:"
        echo "oc login $(jq -r '.api.url' cluster-info.json) -u admin -p $ADMIN_PASSWORD"
    fi
}

# Function to cleanup network resources using Terraform
cleanup_network() {
    log_info "Cleaning up network resources using Terraform..."

    local terraform_dir="terraform-vpc"

    # Check if terraform is installed
    if ! command_exists terraform; then
        log_error "Terraform is not installed. Please install it first."
        exit 1
    fi

    # Check if terraform directory exists
    if [ ! -d "$terraform_dir" ]; then
        log_warning "Terraform directory '$terraform_dir' not found. Nothing to clean up."
        return 0
    fi

    # Change to terraform directory
    cd "$terraform_dir"

    # Check if terraform state exists
    if [ ! -f "terraform.tfstate" ]; then
        log_warning "No Terraform state found. Nothing to clean up."
        cd ..
        return 0
    fi

    # Destroy the infrastructure
    log_info "Destroying Terraform infrastructure..."
    terraform destroy -auto-approve

    # Clean up terraform files
    log_info "Cleaning up Terraform files..."
    rm -f terraform.tfvars rosa.tfplan
    rm -rf .terraform .terraform.lock.hcl

    # Return to original directory
    cd ..

    log_success "Network resources cleaned up successfully"
}

# Function to cleanup on exit
cleanup() {
    log_info "Cleaning up temporary files..."
    rm -f network-info.json oidc-config.json account-roles.json operator-roles.json cluster-info.json
}

# Main execution
main() {
    # Check for cleanup option
    if [ "$1" = "--cleanup-network" ]; then
        cleanup_network
        exit 0
    fi

    log_info "Starting ROSA HCP cluster deployment with no CNI mode"
    log_info "Cluster name: $CLUSTER_NAME"
    log_info "Region: $REGION"

    # Set trap for cleanup
    trap cleanup EXIT

# Execute deployment steps
check_prerequisites
check_existing_cluster
create_network
check_existing_operator_roles
create_oidc_config
create_account_roles
create_operator_roles
create_cluster
display_cluster_info

    log_success "ROSA HCP cluster deployment completed successfully!"
    log_warning "Remember: Nodes will be in 'NotReady' state until you install a CNI plugin"
    log_info "Next steps:"
    echo "1. Install your preferred CNI plugin (e.g., Calico, Cilium)"
    echo "2. Monitor cluster status: rosa describe cluster --cluster $CLUSTER_NAME"
    echo "3. Access cluster console: rosa describe cluster --cluster $CLUSTER_NAME --output json | jq -r '.console.url'"
    echo ""
    log_info "To clean up network resources later, run: $0 --cleanup-network"
}

# Run main function
main "$@"
