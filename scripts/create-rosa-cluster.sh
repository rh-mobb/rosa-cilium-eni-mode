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
ADMIN_PASSWORD="${ADMIN_PASSWORD:-'Passw0rd12345!'}"

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

# Progress tracking with environment variables
PROGRESS_FILE="cluster-creation-progress.env"

# Load existing progress if available
if [ -f "$PROGRESS_FILE" ]; then
    log_info "Loading existing progress from $PROGRESS_FILE"
    source "$PROGRESS_FILE"
fi

# Initialize progress variables with defaults
export PREREQUISITES_COMPLETE="${PREREQUISITES_COMPLETE:-false}"
export NETWORK_COMPLETE="${NETWORK_COMPLETE:-false}"
export OIDC_CONFIG_COMPLETE="${OIDC_CONFIG_COMPLETE:-false}"
export ACCOUNT_ROLES_COMPLETE="${ACCOUNT_ROLES_COMPLETE:-false}"
export OPERATOR_ROLES_COMPLETE="${OPERATOR_ROLES_COMPLETE:-false}"
export CLUSTER_COMPLETE="${CLUSTER_COMPLETE:-false}"

# Data storage (still need some data)
export VPC_ID="${VPC_ID:-}"
export SUBNET_IDS="${SUBNET_IDS:-}"
export OIDC_CONFIG_ID="${OIDC_CONFIG_ID:-}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-}"
export CLUSTER_ID="${CLUSTER_ID:-}"

# Progress tracking functions
init_progress() {
    log_info "Initializing progress tracking with environment variables..."
    # Environment variables are already set with defaults above
}

save_progress() {
    log_info "Saving progress to $PROGRESS_FILE"
    cat > "$PROGRESS_FILE" << EOF
# ROSA Cluster Creation Progress
# Generated on $(date)
# Cluster: $CLUSTER_NAME
# Region: $REGION

# Step completion status
export PREREQUISITES_COMPLETE="$PREREQUISITES_COMPLETE"
export NETWORK_COMPLETE="$NETWORK_COMPLETE"
export OIDC_CONFIG_COMPLETE="$OIDC_CONFIG_COMPLETE"
export ACCOUNT_ROLES_COMPLETE="$ACCOUNT_ROLES_COMPLETE"
export OPERATOR_ROLES_COMPLETE="$OPERATOR_ROLES_COMPLETE"
export CLUSTER_COMPLETE="$CLUSTER_COMPLETE"

# Data storage
export VPC_ID="$VPC_ID"
export SUBNET_IDS="$SUBNET_IDS"
export OIDC_CONFIG_ID="$OIDC_CONFIG_ID"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export CLUSTER_ID="$CLUSTER_ID"
EOF
}

mark_step_complete() {
    local step="$1"
    local data="$2"

    case "$step" in
        "prerequisites")
            export PREREQUISITES_COMPLETE="true"
            ;;
        "network")
            export NETWORK_COMPLETE="true"
            if [ -n "$data" ]; then
                export VPC_ID=$(echo "$data" | jq -r '.vpc_id // empty')
                export SUBNET_IDS=$(echo "$data" | jq -r '.subnet_ids // empty')
            fi
            ;;
        "oidc_config")
            export OIDC_CONFIG_COMPLETE="true"
            if [ -n "$data" ]; then
                export OIDC_CONFIG_ID=$(echo "$data" | jq -r '.oidc_config_id // empty')
            fi
            ;;
        "account_roles")
            export ACCOUNT_ROLES_COMPLETE="true"
            if [ -n "$data" ]; then
                export AWS_ACCOUNT_ID=$(echo "$data" | jq -r '.aws_account_id // empty')
            fi
            ;;
        "operator_roles")
            export OPERATOR_ROLES_COMPLETE="true"
            ;;
        "cluster")
            export CLUSTER_COMPLETE="true"
            if [ -n "$data" ]; then
                export CLUSTER_ID=$(echo "$data" | jq -r '.cluster_id // empty')
            fi
            ;;
    esac

    # Save progress after each step
    save_progress
}

is_step_complete() {
    local step="$1"
    case "$step" in
        "prerequisites")
            echo "$PREREQUISITES_COMPLETE"
            ;;
        "network")
            echo "$NETWORK_COMPLETE"
            ;;
        "oidc_config")
            echo "$OIDC_CONFIG_COMPLETE"
            ;;
        "account_roles")
            echo "$ACCOUNT_ROLES_COMPLETE"
            ;;
        "operator_roles")
            echo "$OPERATOR_ROLES_COMPLETE"
            ;;
        "cluster")
            echo "$CLUSTER_COMPLETE"
            ;;
    esac
}

skip_if_complete() {
    local step="$1"
    if [ "$(is_step_complete "$step")" = "true" ]; then
        log_success "Step '$step' already completed, skipping..."
        return 0
    else
        return 1
    fi
}

# Function to show progress status
show_progress() {
    log_info "Current deployment progress:"
    echo "  prerequisites: $(if [ "$PREREQUISITES_COMPLETE" = "true" ]; then echo "✅ Completed"; else echo "⏳ Pending"; fi)"
    echo "  network: $(if [ "$NETWORK_COMPLETE" = "true" ]; then echo "✅ Completed"; else echo "⏳ Pending"; fi)"
    echo "  oidc_config: $(if [ "$OIDC_CONFIG_COMPLETE" = "true" ]; then echo "✅ Completed"; else echo "⏳ Pending"; fi)"
    echo "  account_roles: $(if [ "$ACCOUNT_ROLES_COMPLETE" = "true" ]; then echo "✅ Completed"; else echo "⏳ Pending"; fi)"
    echo "  operator_roles: $(if [ "$OPERATOR_ROLES_COMPLETE" = "true" ]; then echo "✅ Completed"; else echo "⏳ Pending"; fi)"
    echo "  cluster: $(if [ "$CLUSTER_COMPLETE" = "true" ]; then echo "✅ Completed"; else echo "⏳ Pending"; fi)"
    echo ""
    log_info "Progress tracked via environment variables"
}

# Function to reset progress
reset_progress() {
    export PREREQUISITES_COMPLETE="false"
    export NETWORK_COMPLETE="false"
    export OIDC_CONFIG_COMPLETE="false"
    export ACCOUNT_ROLES_COMPLETE="false"
    export OPERATOR_ROLES_COMPLETE="false"
    export CLUSTER_COMPLETE="false"
    export VPC_ID=""
    export SUBNET_IDS=""
    export OIDC_CONFIG_ID=""
    export AWS_ACCOUNT_ID=""
    export CLUSTER_ID=""

    # Remove progress file
    if [ -f "$PROGRESS_FILE" ]; then
        rm -f "$PROGRESS_FILE"
        log_info "Removed progress file: $PROGRESS_FILE"
    fi

    log_success "Progress reset. Starting fresh deployment."
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

    if ! command_exists oc; then
        log_error "OpenShift CLI (oc) is not installed. Please install it first."
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

# Function to check if VPC already exists
check_vpc_exists() {
    log_info "Checking if VPC already exists for cluster '$CLUSTER_NAME'..."

    # Check if VPC exists by name
    local vpc_id=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Name,Values=${CLUSTER_NAME}-vpc" \
        --query 'Vpcs[0].VpcId' \
        --output text 2>/dev/null || echo "None")

    if [ "$vpc_id" != "None" ] && [ "$vpc_id" != "null" ] && [ -n "$vpc_id" ]; then
        log_success "VPC already exists: $vpc_id"

        # Get subnet IDs for this VPC
        SUBNET_IDS=$(aws ec2 describe-subnets \
            --filters "Name=vpc-id,Values=$vpc_id" \
            --query 'Subnets[].SubnetId' \
            --output text | tr '\t' ',')

        VPC_ID="$vpc_id"

        log_info "Using existing VPC: $VPC_ID"
        log_info "Using existing subnets: $SUBNET_IDS"
        return 0
    else
        log_info "VPC does not exist, will create new VPC"
        return 1
    fi
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

    log_info "Running: rosa describe cluster --cluster $CLUSTER_NAME -o json"
    local cluster_exists
    # Try to describe the cluster; if it fails, output a marker ('.')
    cluster_exists=$(rosa describe cluster --cluster "$CLUSTER_NAME" -o json 2>/dev/null || echo '.')

    # Check if the output is not just the marker
    if [ "$cluster_exists" != "." ]; then
        log_success "Cluster '$CLUSTER_NAME' already exists!"
        log_info "Cluster is ready, will attempt login..."
        return 0
    else
        log_info "Cluster '$CLUSTER_NAME' does not exist, proceeding with creation..."
        return 1
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
        log_info "Using AWS account ID: $AWS_ACCOUNT_ID"
        local installer_role_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${role_prefix}-HCP-ROSA-Installer-Role"
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

    # Get account role ARNs (calculated from cluster name and AWS account ID)
    log_info "Using AWS account ID: $AWS_ACCOUNT_ID"
    local installer_role_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${role_prefix}-HCP-ROSA-Installer-Role"
    local support_role_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${role_prefix}-HCP-ROSA-Support-Role"
    local worker_role_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${role_prefix}-HCP-ROSA-Worker-Role"

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
        --cluster-admin-password "$ADMIN_PASSWORD" \
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

# Function to login to the cluster with retry logic
login_to_cluster() {
    log_info "Attempting to login to the cluster..."

    # Get cluster API URL
    local cluster_json=$(rosa describe cluster --cluster "$CLUSTER_NAME" -o json 2>/dev/null)
    if [ -z "$cluster_json" ] || [ "$cluster_json" = "null" ]; then
        log_error "Could not retrieve cluster information for login"
        return 1
    fi

    local api_url=$(echo "$cluster_json" | jq -r '.api.url // empty')
    if [ -z "$api_url" ]; then
        log_error "Could not retrieve cluster API URL"
        return 1
    fi

    log_info "Cluster API URL: $api_url"
    log_info "Attempting login with retry logic (every 10 seconds)..."

    local max_attempts=30  # 5 minutes total
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        log_info "Login attempt $attempt/$max_attempts..."

        # Attempt to login
        if oc login "$api_url" -u cluster-admin -p "$ADMIN_PASSWORD" --insecure-skip-tls-verify >/dev/null 2>&1; then
            log_success "Successfully logged into cluster!"

            # Verify login by checking cluster info
            if oc cluster-info >/dev/null 2>&1; then
                log_success "Cluster connection verified"
                log_info "Current context: $(oc config current-context 2>/dev/null || echo 'unknown')"
                return 0
            else
                log_warning "Login succeeded but cluster connection verification failed"
            fi
        else
            log_info "Login attempt $attempt failed, retrying in 10 seconds..."
        fi

        sleep 10
        attempt=$((attempt + 1))
    done

    log_error "Failed to login to cluster after $max_attempts attempts"
    log_info "You can try manually: oc login $api_url -u cluster-admin -p $ADMIN_PASSWORD --insecure-skip-tls-verify"
    return 1
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

    # Fetch cluster info directly from ROSA CLI
    cluster_json=$(rosa describe cluster --cluster "$CLUSTER_NAME" -o json 2>/dev/null)
    if [ -n "$cluster_json" ] && [ "$cluster_json" != "null" ]; then
        console_url=$(echo "$cluster_json" | jq -r '.console.url // empty')
        api_url=$(echo "$cluster_json" | jq -r '.api.url // empty')
        if [ -n "$console_url" ]; then
            echo "Cluster Console URL: $console_url"
        fi
        if [ -n "$api_url" ]; then
            echo "Cluster API URL: $api_url"
            echo ""
            echo "Login Command:"
            echo "oc login $api_url -u cluster-admin -p $ADMIN_PASSWORD --insecure-skip-tls-verify"
        fi
    else
        log_warning "Could not retrieve cluster information from ROSA CLI."
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
    # Note: Progress file is kept for resuming failed deployments
}

# Main execution
main() {
    # Check for command line options
    case "$1" in
        "--cleanup-network")
            cleanup_network
            exit 0
            ;;
        "--show-progress")
            show_progress
            exit 0
            ;;
        "--reset-progress")
            reset_progress
            exit 0
            ;;
        "--network-only")
            log_info "Running network creation only..."
            if ! skip_if_complete "network"; then
                # Check if VPC already exists before running Terraform
                if check_vpc_exists; then
                    log_success "Using existing VPC infrastructure, skipping Terraform"
                    mark_step_complete "network" '{"vpc_id": "'"$VPC_ID"'", "subnet_ids": "'"$SUBNET_IDS"'"}'
                else
                    create_network
                    mark_step_complete "network" '{"vpc_id": "'"$VPC_ID"'", "subnet_ids": "'"$SUBNET_IDS"'"}'
                fi
            else
                # Load network data from environment variables
                log_info "Using existing network: VPC=$VPC_ID, Subnets=$SUBNET_IDS"
            fi
            log_success "Network creation completed!"
            exit 0
            ;;
        "--help"|"-h")
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --cleanup-network    Clean up network resources"
            echo "  --show-progress      Show current deployment progress"
            echo "  --reset-progress     Reset progress and start fresh"
            echo "  --network-only       Create network infrastructure only"
            echo "  --help, -h           Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                  # Start/resume cluster deployment"
            echo "  $0 --show-progress  # Check current progress"
            echo "  $0 --reset-progress # Start fresh deployment"
            echo "  $0 --network-only   # Create network only"
            exit 0
            ;;
    esac

    log_info "Starting ROSA HCP cluster deployment with no CNI mode"
    log_info "Cluster name: $CLUSTER_NAME"
    log_info "Region: $REGION"

    # Initialize progress tracking
    init_progress

    # Show current progress
    show_progress

    # Set trap for cleanup
    trap cleanup EXIT

    # Execute deployment steps with progress tracking
    if ! skip_if_complete "prerequisites"; then
        check_prerequisites
        mark_step_complete "prerequisites"
    fi

    # Check if cluster already exists
    if check_existing_cluster; then
        log_info "Cluster already exists, using progress file to determine what steps to skip..."

        # Get network info for existing cluster (no creation, just discovery)
        log_info "Getting network information for existing cluster..."
        if check_vpc_exists; then
            log_success "Found existing VPC infrastructure"
        else
            log_warning "Could not find VPC for existing cluster, but continuing with login attempt"
        fi
    fi

    # Execute deployment steps with progress tracking (works for both new and existing clusters)
    if ! skip_if_complete "network"; then
        # Check if VPC already exists before running Terraform
        if check_vpc_exists; then
            log_success "Using existing VPC infrastructure, skipping Terraform"
            mark_step_complete "network" '{"vpc_id": "'"$VPC_ID"'", "subnet_ids": "'"$SUBNET_IDS"'"}'
        else
            create_network
            mark_step_complete "network" '{"vpc_id": "'"$VPC_ID"'", "subnet_ids": "'"$SUBNET_IDS"'"}'
        fi
    else
        # Load network data from environment variables
        log_info "Using existing network: VPC=$VPC_ID, Subnets=$SUBNET_IDS"
    fi

    if ! skip_if_complete "oidc_config"; then
        create_oidc_config
        mark_step_complete "oidc_config" '{"oidc_config_id": "'"$OIDC_CONFIG_ID"'"}'
    else
        # Load OIDC config data from environment variables
        log_info "Using existing OIDC config: $OIDC_CONFIG_ID"
    fi

    if ! skip_if_complete "account_roles"; then
        create_account_roles
        # Save AWS account ID for future use
        local aws_account_id=$(aws sts get-caller-identity --query Account --output text)
        mark_step_complete "account_roles" '{"aws_account_id": "'"$aws_account_id"'"}'
    else
        # Load AWS account ID from environment variables
        log_info "Using existing AWS account ID: $AWS_ACCOUNT_ID"
    fi

    if ! skip_if_complete "operator_roles"; then
        check_existing_operator_roles
        create_operator_roles
        mark_step_complete "operator_roles"
    else
        log_info "Using existing operator roles for cluster: $CLUSTER_NAME"
    fi

    if ! skip_if_complete "cluster"; then
        create_cluster
        # Save cluster ID if cluster was created
        if [ -f "cluster-info.json" ]; then
            local cluster_id=$(jq -r '.id' cluster-info.json)
            mark_step_complete "cluster" '{"cluster_id": "'"$cluster_id"'"}'
        else
            mark_step_complete "cluster"
        fi
    else
        # Load cluster ID from environment variables
        if [ -n "$CLUSTER_ID" ]; then
            log_info "Using existing cluster ID: $CLUSTER_ID"
        fi
    fi

    # Attempt to login to the cluster
    if login_to_cluster; then
        log_success "Cluster login completed successfully!"
    else
        log_warning "Cluster login failed, but cluster is ready for manual login"
    fi

    display_cluster_info

    log_success "ROSA HCP cluster deployment completed successfully!"
    log_warning "Remember: Nodes will be in 'NotReady' state until you install a CNI plugin"
    echo ""
    echo "Next steps:"
    echo "1. Install CNI plugin: ./scripts/deploy-cilium.sh"
    echo "2. Verify cluster: oc get nodes"
    echo "3. Access cluster console: rosa describe cluster --cluster $CLUSTER_NAME --output json | jq -r '.console.url'"
    echo ""
    log_info "To clean up network resources later, run: $0 --cleanup-network"
    log_info "Progress saved in: $PROGRESS_FILE"
}

# Run main function
main "$@"
