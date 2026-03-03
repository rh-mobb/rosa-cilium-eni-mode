#!/bin/bash

# delete-rosa-cluster.sh
# This script deletes a ROSA HCP cluster and cleans up all associated resources

set -eox #ox  # Exit on any error

# Disable AWS CLI pager to prevent interactive prompts in scripts
export AWS_PAGER=""

# Configuration variables
CLUSTER_NAME="${CLUSTER_NAME:-pczarkow}"
AWS_REGION="${AWS_REGION:-us-east-2}"
PREFIX="${PREFIX:-pczarkow}"

# Color codes for output
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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if rosa CLI is installed
    if ! command -v rosa &> /dev/null; then
        log_error "ROSA CLI is not installed. Please install it first."
        exit 1
    fi

    # Check if oc CLI is installed
    if ! command -v oc &> /dev/null; then
        log_error "OpenShift CLI (oc) is not installed. Please install it first."
        exit 1
    fi

    # Check if aws CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi

    # Check if helm is installed
    if ! command -v helm &> /dev/null; then
        log_error "Helm is not installed. Please install it first."
        exit 1
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi

    # Check ROSA login
    if ! rosa whoami &> /dev/null; then
        log_error "Not logged in to ROSA. Please run 'rosa login' first."
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Function to check if cluster exists
check_cluster_exists() {
    log_info "Checking if cluster '$CLUSTER_NAME' exists..."

    if rosa list clusters | grep -q "$CLUSTER_NAME"; then
        log_info "Cluster '$CLUSTER_NAME' found"
        return 0
    else
        log_warning "Cluster '$CLUSTER_NAME' not found"
        return 1
    fi
}

# Function to check if cluster info file exists
check_cluster_info_file() {
    if [[ -f ".cluster-info-file" ]]; then
        local cluster_info_file=$(cat .cluster-info-file 2>/dev/null)
        if [[ -f "$cluster_info_file" ]]; then
            log_info "Found existing cluster info file: $cluster_info_file"
            return 0
        fi
    fi
    return 1
}

# Function to get cluster status
get_cluster_status() {
    local status=$(rosa describe cluster -c "$CLUSTER_NAME" -o json | jq -r '.state' 2>/dev/null || echo "unknown")
    echo "$status"
}

# Function to wait for cluster to be ready for deletion
wait_for_cluster_ready() {
    log_info "Waiting for cluster to be ready for deletion..."

    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        local status=$(get_cluster_status)

        case "$status" in
            "ready"|"installing"|"error"|"uninstalling")
                log_info "Cluster status: $status - ready for deletion"
                return 0
                ;;
            "waiting")
                log_info "Cluster status: $status - waiting for it to be ready..."
                ;;
            *)
                log_warning "Cluster status: $status - proceeding with deletion"
                return 0
                ;;
        esac

        log_info "Attempt $attempt/$max_attempts - waiting 30 seconds..."
        sleep 30
        ((attempt++))
    done

    log_warning "Timeout waiting for cluster to be ready, proceeding with deletion"
}

# Function to save cluster information before deletion
save_cluster_info() {
    log_info "Saving cluster information before deletion..."

    local cluster_info_file="cluster-info-${CLUSTER_NAME}-$(date +%Y%m%d-%H%M%S).json"

    # Get cluster information
    if rosa describe cluster -c "$CLUSTER_NAME" -o json > "$cluster_info_file" 2>/dev/null; then
        log_success "Cluster information saved to: $cluster_info_file"

        # Extract key information for display
        local cluster_id=$(jq -r '.id' "$cluster_info_file" 2>/dev/null || echo "unknown")
        local oidc_config_id=$(jq -r '.aws.sts.oidc_config.id' "$cluster_info_file" 2>/dev/null || echo "unknown")
        local region=$(jq -r '.region.id' "$cluster_info_file" 2>/dev/null || echo "unknown")

        log_info "Cluster ID: $cluster_id"
        log_info "OIDC Config ID: $oidc_config_id"
        log_info "Region: $region"

        # Store the file path for later use
        echo "$cluster_info_file" > ".cluster-info-file"

        return 0
    else
        log_warning "Failed to save cluster information, proceeding with deletion"
        return 1
    fi
}

# Function to delete Cilium CNI
delete_cilium_cni() {
    log_info "Deleting Cilium CNI..."

    # Check if Cilium is deployed
    if helm list -n kube-system | grep -q cilium; then
        log_info "Cilium found, uninstalling..."

        # Run the uninstall script if it exists
        if [[ -f "scripts/uninstall-cilium.sh" ]]; then
            log_info "Running Cilium uninstall script..."
            if bash scripts/uninstall-cilium.sh; then
                log_success "Cilium uninstall script completed successfully"
            else
                log_warning "Cilium uninstall script failed, but continuing with cluster deletion"
            fi
        else
            log_info "Uninstalling Cilium with Helm..."
            if helm uninstall cilium -n kube-system; then
                log_success "Cilium Helm uninstall completed successfully"
            else
                log_warning "Cilium Helm uninstall failed, but continuing with cluster deletion"
            fi
        fi

        # Clean up any remaining Cilium resources (non-blocking)
        log_info "Cleaning up remaining Cilium resources..."
        oc delete pods -n kube-system -l k8s-app=cilium --ignore-not-found=true || log_warning "Failed to delete Cilium pods"
        oc delete pods -n kube-system -l name=cilium-operator --ignore-not-found=true || log_warning "Failed to delete Cilium operator pods"
        oc delete serviceaccounts -n kube-system cilium cilium-operator cilium-envoy --ignore-not-found=true || log_warning "Failed to delete Cilium service accounts"

        log_info "Cilium CNI cleanup attempted (cluster deletion will clean up any remaining resources)"
    else
        log_info "Cilium not found, skipping deletion"
    fi
}

# Function to delete cluster
delete_cluster() {
    log_info "Deleting ROSA HCP cluster '$CLUSTER_NAME'..."

    # Delete the cluster
    rosa delete cluster -c "$CLUSTER_NAME" --yes

    log_success "Cluster deletion initiated"

    # Tail the uninstall logs
    log_info "Tailing cluster uninstall logs..."
    log_info "Press Ctrl+C to stop following logs (deletion will continue in background)"
    echo ""

    # Tail logs with timeout to avoid hanging indefinitely
    # Use a more portable approach for timeout
    local log_pid=""

    # Start log tailing in background
    rosa logs uninstall --cluster="$CLUSTER_NAME" --watch &
    log_pid=$!

    # Wait for either the process to complete or timeout (5 minutes)
    local count=0
    while kill -0 $log_pid 2>/dev/null && [ $count -lt 300 ]; do
        sleep 1
        ((count++))
    done

    # Kill the process if it's still running (timeout)
    if kill -0 $log_pid 2>/dev/null; then
        log_info "Log tailing timed out after 5 minutes (deletion continues in background)"
        kill $log_pid 2>/dev/null || true
    else
        log_info "Log tailing completed (deletion continues in background)"
    fi
}

# Function to wait for cluster deletion
wait_for_cluster_deletion() {
    log_info "Waiting for cluster deletion to complete..."

    local max_attempts=60  # 30 minutes
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if ! rosa list clusters | grep -q "$CLUSTER_NAME"; then
            log_success "Cluster '$CLUSTER_NAME' has been deleted"
            return 0
        fi

        log_info "Attempt $attempt/$max_attempts - cluster still exists, waiting 30 seconds..."
        sleep 30
        ((attempt++))
    done

    log_error "Timeout waiting for cluster deletion"
    return 1
}

# Function to delete operator roles
delete_operator_roles() {
    local cluster_id=""

    # Get cluster ID from saved cluster info (preferred - cluster-specific roles)
    if [[ -f ".cluster-info-file" ]]; then
        local cluster_info_file
        cluster_info_file=$(cat ".cluster-info-file" 2>/dev/null)
        if [[ -f "$cluster_info_file" ]]; then
            cluster_id=$(jq -r '.id' "$cluster_info_file" 2>/dev/null | grep -v "^null$" || echo "")
        fi
    fi

    # Try cluster-specific deletion first (requires cluster ID - works even after cluster is deleted)
    if [[ -n "$cluster_id" && "$cluster_id" != "null" ]]; then
        log_info "Deleting operator roles for cluster ID '$cluster_id'..."
        if rosa delete operator-roles --cluster "$cluster_id" --yes --mode auto; then
            log_success "Operator roles deleted"
            return 0
        else
            log_warning "Cluster-based operator role deletion failed, trying prefix fallback..."
        fi
    fi

    # Fallback: delete by prefix (for reusable OIDC or when cluster info unavailable)
    log_info "Deleting operator roles for prefix '$PREFIX'..."

    local operator_roles_json
    operator_roles_json=$(rosa list operator-roles --prefix "$PREFIX" -o json 2>/dev/null || echo "[]")

    if echo "$operator_roles_json" | jq -e '. | length > 0' >/dev/null 2>&1; then
        local operator_roles
        operator_roles=$(echo "$operator_roles_json" | jq -r '.[].role_name' 2>/dev/null | grep -v "^null$" | grep -v "^$" || echo "")

        if [[ -n "$operator_roles" ]]; then
            log_info "Found operator roles:"
            echo "$operator_roles" | while read -r role; do
                if [[ -n "$role" && "$role" != "null" ]]; then
                    log_info "  - $role"
                fi
            done

            log_info "Deleting operator roles for prefix '$PREFIX'..."
            if rosa delete operator-roles --prefix "$PREFIX" --yes --mode auto; then
                log_success "Operator roles deleted"
            else
                log_warning "Failed to delete operator roles for prefix '$PREFIX'"
            fi
        else
            log_info "No operator roles found for prefix '$PREFIX'"
        fi
    else
        log_info "No operator roles found for prefix '$PREFIX'"
    fi
}

# Function to delete account roles
delete_account_roles() {
    log_info "Deleting account roles for prefix '$PREFIX'..."

    # List account roles to check if any exist
    local account_roles_json=$(rosa list account-roles --prefix "$PREFIX" -o json 2>/dev/null || echo "[]")

    # Check if we got valid JSON and extract role names
    if echo "$account_roles_json" | jq -e '. | length > 0' >/dev/null 2>&1; then
        local account_roles=$(echo "$account_roles_json" | jq -r '.[].role_name' 2>/dev/null | grep -v "^null$" | grep -v "^$" || echo "")

        if [[ -n "$account_roles" ]]; then
            log_info "Found account roles:"
            echo "$account_roles" | while read -r role; do
                if [[ -n "$role" && "$role" != "null" ]]; then
                    log_info "  - $role"
                fi
            done

            # Delete account roles by prefix
            log_info "Deleting account roles for prefix '$PREFIX'..."
            if rosa delete account-roles --prefix "$PREFIX" --yes --mode auto; then
                log_success "Account roles deleted"
            else
                log_warning "Failed to delete account roles for prefix '$PREFIX'"
            fi
        else
            log_info "No account roles found for prefix '$PREFIX'"
        fi
    else
        log_info "No account roles found for prefix '$PREFIX'"
    fi
}

# Function to delete OIDC config
delete_oidc_config() {
    log_info "Deleting OIDC configuration..."

    local oidc_config_id=""

    # Try to get OIDC config ID from saved cluster info first
    if [[ -f ".cluster-info-file" ]]; then
        local cluster_info_file=$(cat ".cluster-info-file")
        if [[ -f "$cluster_info_file" ]]; then
            oidc_config_id=$(jq -r '.aws.sts.oidc_config.id' "$cluster_info_file" 2>/dev/null || echo "")
            log_info "Using OIDC config ID from saved cluster info: $oidc_config_id"
        fi
    fi

    # Fallback to live cluster query if not found in saved info
    if [[ -z "$oidc_config_id" || "$oidc_config_id" == "null" ]]; then
        oidc_config_id=$(rosa describe cluster -c "$CLUSTER_NAME" -o json 2>/dev/null | jq -r '.aws.sts.oidc_config.id' 2>/dev/null || echo "")
        log_info "Using OIDC config ID from live cluster query: $oidc_config_id"
    fi

    if [[ -n "$oidc_config_id" && "$oidc_config_id" != "null" ]]; then
        log_info "Found OIDC config ID: $oidc_config_id"

        # Check if OIDC config is in use by other clusters
        local in_use=$(rosa list clusters -o json | jq -r '.[] | select(.aws.sts.oidc_config.id == "'"$oidc_config_id"'") | .name' 2>/dev/null | grep -v "$CLUSTER_NAME" || echo "")

        if [[ -n "$in_use" ]]; then
            log_warning "OIDC config $oidc_config_id is still in use by other clusters: $in_use"
            log_info "Skipping OIDC config deletion"
        else
            log_info "Deleting OIDC config: $oidc_config_id"
            rosa delete oidc-config --oidc-config-id "$oidc_config_id" --yes --mode auto || log_warning "Failed to delete OIDC config: $oidc_config_id"
            log_success "OIDC config deleted"
        fi
    else
        log_info "No OIDC config found for cluster '$CLUSTER_NAME'"
    fi
}

# Function to clean up AWS resources
cleanup_aws_resources() {
    log_info "Cleaning up AWS resources..."

    # Get AWS account ID
    local account_id=$(aws sts get-caller-identity --query Account --output text)

    # Clean up Cilium IAM role if it exists
    local cilium_role_name="cilium-operator-${CLUSTER_NAME}"
    if aws iam get-role --role-name "$cilium_role_name" &> /dev/null; then
        log_info "Deleting Cilium IAM role: $cilium_role_name"

        # Detach policies
        aws iam list-attached-role-policies --role-name "$cilium_role_name" --query 'AttachedPolicies[].PolicyArn' --output text | while read -r policy_arn; do
            if [[ -n "$policy_arn" ]]; then
                aws iam detach-role-policy --role-name "$cilium_role_name" --policy-arn "$policy_arn" || true
            fi
        done

        # Delete the role
        aws iam delete-role --role-name "$cilium_role_name" || log_warning "Failed to delete IAM role: $cilium_role_name"
        log_success "Cilium IAM role deleted"
    else
        log_info "Cilium IAM role not found: $cilium_role_name"
    fi

    # Clean up any LoadBalancers created by the cluster
    log_info "Cleaning up LoadBalancers..."
    aws elbv2 describe-load-balancers --region "$AWS_REGION" --query 'LoadBalancers[?contains(LoadBalancerName, `'"$CLUSTER_NAME"'`)].LoadBalancerArn' --output text | while read -r lb_arn; do
        if [[ -n "$lb_arn" ]]; then
            log_info "Deleting LoadBalancer: $lb_arn"
            aws elbv2 delete-load-balancer --region "$AWS_REGION" --load-balancer-arn "$lb_arn" || log_warning "Failed to delete LoadBalancer: $lb_arn"
        fi
    done

    log_success "AWS resources cleaned up"
}

# Function to display deletion summary
display_deletion_summary() {
    log_info "Deletion Summary:"
    echo "=================="
    echo "Cluster Name: $CLUSTER_NAME"
    echo "AWS Region: $AWS_REGION"
    echo "Prefix: $PREFIX"
    echo ""
    echo "Resources Deleted:"
    echo "✅ Cilium CNI (if deployed)"
    echo "✅ ROSA HCP Cluster"
    echo "✅ Operator Roles"
    echo "✅ Account Roles"
    echo "✅ OIDC Configuration (if not in use by other clusters)"
    echo "✅ Cilium IAM Role"
    echo "✅ LoadBalancers"
    echo ""
    log_success "Cluster deletion completed successfully!"
}

# Function to handle cleanup on exit
cleanup() {
    log_info "Cleaning up temporary files..."

    # Clean up cluster info file
    if [[ -f ".cluster-info-file" ]]; then
        local cluster_info_file=$(cat ".cluster-info-file")
        if [[ -f "$cluster_info_file" ]]; then
            log_info "Keeping cluster info file: $cluster_info_file"
        fi
        rm -f ".cluster-info-file"
    fi
}

# Set up trap for cleanup
trap cleanup EXIT

# Main execution
main() {
    log_info "Starting ROSA HCP cluster deletion process"
    log_info "Cluster: $CLUSTER_NAME"
    log_info "Region: $AWS_REGION"
    log_info "Prefix: $PREFIX"
    echo ""

    # Check prerequisites
    check_prerequisites

    # Check if cluster exists or if we have cluster info file
    local cluster_exists=false
    local has_cluster_info=false

    if check_cluster_exists; then
        cluster_exists=true
    elif check_cluster_info_file; then
        has_cluster_info=true
        log_info "Cluster not found but cluster info file exists - proceeding with cleanup"
    else
        log_warning "Cluster '$CLUSTER_NAME' not found and no cluster info file."
        log_info "Proceeding with prefix-based cleanup (operator roles, account roles, Cilium IAM)..."
    fi

    if [[ "$cluster_exists" == "true" ]]; then
        # Get cluster status
        local status=$(get_cluster_status)
        log_info "Current cluster status: $status"

        # Wait for cluster to be ready for deletion
        wait_for_cluster_ready

        # Save cluster information before deletion
        save_cluster_info

        # Delete Cilium CNI first
        delete_cilium_cni

        # Delete the cluster
        delete_cluster

        # Wait for cluster deletion
        if wait_for_cluster_deletion; then
            log_success "Cluster deletion completed successfully"
        else
            log_warning "Cluster deletion may still be in progress"
        fi
    else
        log_info "Cluster already deleted, proceeding with resource cleanup using cluster info file"
    fi

    # Clean up associated resources (works whether cluster exists or not)
    # Delete operator roles
    delete_operator_roles

    # Delete account roles
    delete_account_roles

    # Delete OIDC config
    delete_oidc_config

    # Clean up AWS resources
    cleanup_aws_resources

    # Display summary
    display_deletion_summary
}

# Run main function
main "$@"
