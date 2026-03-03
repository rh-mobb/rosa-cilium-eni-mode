#!/bin/bash

# Cilium CNI Uninstall Script for ROSA HCP
# This script removes Cilium CNI and cleans up all AWS IAM resources

set -eox  # Exit on any error

# Disable AWS CLI pager to prevent interactive prompts in scripts
export AWS_PAGER=""

# Configuration variables
CLUSTER_NAME="${CLUSTER_NAME:-$(whoami)}"
CILIUM_VERSION="${CILIUM_VERSION:-1.19.1}"
CILIUM_NAMESPACE="kube-system"
CILIUM_OPERATOR_NAMESPACE="kube-system"

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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if oc is installed
    if ! command -v oc &> /dev/null; then
        log_error "OpenShift CLI (oc) is not installed or not in PATH"
        exit 1
    fi

    # Check if helm is installed
    if ! command -v helm &> /dev/null; then
        log_error "Helm is not installed or not in PATH"
        exit 1
    fi

    # Check if aws is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed or not in PATH"
        exit 1
    fi

    # Check if we're connected to a cluster
    if ! oc whoami &> /dev/null; then
        log_error "Not connected to any OpenShift cluster"
        log_info "Please login to your cluster first:"
        log_info "  oc login <cluster-api-url> -u admin -p <password>"
        exit 1
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        exit 1
    fi

    # Get cluster info
    local cluster_name=$(oc config current-context | cut -d'/' -f2)
    log_success "Connected to cluster: $cluster_name"
    log_success "Prerequisites check passed"
}

# Function to check if Cilium is installed
check_cilium_installed() {
    log_info "Checking if Cilium is installed..."

    if helm list -n "$CILIUM_NAMESPACE" | grep -q cilium; then
        log_info "Cilium Helm release found"
        return 0
    else
        log_warning "Cilium Helm release not found"
        return 1
    fi
}

# Function to uninstall Cilium using Helm
uninstall_cilium() {
    log_info "Uninstalling Cilium CNI..."

    if check_cilium_installed; then
        log_info "Uninstalling Cilium Helm release..."
        helm uninstall cilium -n "$CILIUM_NAMESPACE" --wait --timeout=5m
        log_success "Cilium Helm release uninstalled"
    else
        log_warning "Cilium Helm release not found, skipping Helm uninstall"
    fi

    # Wait for pods to be removed
    log_info "Waiting for Cilium pods to be removed..."
    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        local cilium_pods=$(oc get pods -n "$CILIUM_NAMESPACE" -l k8s-app=cilium --no-headers | wc -l)
        local operator_pods=$(oc get pods -n "$CILIUM_NAMESPACE" -l name=cilium-operator --no-headers | wc -l)

        if [ "$cilium_pods" -eq 0 ] && [ "$operator_pods" -eq 0 ]; then
            log_success "All Cilium pods removed"
            break
        else
            log_info "Waiting for pods to be removed... (Cilium: $cilium_pods, Operator: $operator_pods) (attempt $attempt/$max_attempts)"
            sleep 10
            attempt=$((attempt + 1))
        fi
    done

    if [ $attempt -gt $max_attempts ]; then
        log_warning "Some Cilium pods may still exist after timeout"
        log_info "Remaining Cilium pods:"
        oc get pods -n "$CILIUM_NAMESPACE" -l k8s-app=cilium
        log_info "Remaining operator pods:"
        oc get pods -n "$CILIUM_NAMESPACE" -l name=cilium-operator
    fi
}

# Function to clean up Cilium CRDs
cleanup_cilium_crds() {
    log_info "Cleaning up Cilium CRDs..."

    # List of Cilium CRDs to remove
    local crds=(
        "ciliumidentities.cilium.io"
        "ciliumnodes.cilium.io"
        "ciliumendpoints.cilium.io"
        "ciliumnetworkpolicies.cilium.io"
        "ciliumclusterwidenetworkpolicies.cilium.io"
        "ciliumegressgatewaypolicies.cilium.io"
        "ciliumexternalworkloads.cilium.io"
        "ciliumlocalredirectpolicies.cilium.io"
        "ciliumendpointslices.cilium.io"
        "ciliumbgppeeringpolicies.cilium.io"
        "ciliumbgpconfigs.cilium.io"
        "ciliumbgpadvertisements.cilium.io"
        "ciliumloadbalancerippools.cilium.io"
        "ciliumcidrgroups.cilium.io"
        "ciliuml2announcementpolicies.cilium.io"
        "ciliuml2announcements.cilium.io"
    )

    for crd in "${crds[@]}"; do
        if oc get crd "$crd" &> /dev/null; then
            log_info "Removing CRD: $crd"
            oc delete crd "$crd" --ignore-not-found=true
        fi
    done

    log_success "Cilium CRDs cleanup completed"
}

# Function to clean up Cilium namespaces
cleanup_cilium_namespaces() {
    log_info "Cleaning up Cilium namespaces..."

    # All Cilium resources are in kube-system, no separate namespaces to clean up
    log_info "All Cilium resources are deployed in kube-system namespace"
    log_success "Namespace cleanup completed (no separate namespaces to remove)"
}

# Function to clean up AWS IAM resources
cleanup_aws_iam_resources() {
    log_info "Cleaning up AWS IAM resources..."

    local account_id=$(aws sts get-caller-identity --query Account --output text)

    log_info "Cluster: $CLUSTER_NAME"
    log_info "Account ID: $account_id"

    # Clean up IAM role
    local role_name="cilium-operator-${CLUSTER_NAME}"
    log_info "Checking for IAM role: $role_name"

    if aws iam get-role --role-name "$role_name" &> /dev/null; then
        log_info "Found IAM role: $role_name"

        # Detach policies
        log_info "Detaching policies from role..."

        # Detach AWS managed policy
        aws iam detach-role-policy \
            --role-name "$role_name" \
            --policy-arn "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy" \
            2>/dev/null || log_warning "AmazonEKS_CNI_Policy may not be attached"

        # Detach custom policy
        local custom_policy_name="cilium-custom-${CLUSTER_NAME}"
        aws iam detach-role-policy \
            --role-name "$role_name" \
            --policy-arn "arn:aws:iam::${account_id}:policy/${custom_policy_name}" \
            2>/dev/null || log_warning "Custom policy may not be attached"

        # Delete custom policy
        log_info "Deleting custom policy: $custom_policy_name"
        aws iam delete-policy \
            --policy-arn "arn:aws:iam::${account_id}:policy/${custom_policy_name}" \
            2>/dev/null || log_warning "Custom policy may not exist"

        # Delete role
        log_info "Deleting IAM role: $role_name"
        aws iam delete-role --role-name "$role_name"

        log_success "IAM role deleted: $role_name"
    else
        log_warning "IAM role not found: $role_name"
    fi

    log_success "AWS IAM resources cleanup completed"
}

# Function to restore kube-proxy (optional)
restore_kube_proxy() {
    log_info "Checking if kube-proxy needs to be restored..."

    local kube_proxy_pods=$(oc get pods -n kube-system -l k8s-app=kube-proxy --no-headers | wc -l)

    if [ "$kube_proxy_pods" -eq 0 ]; then
        log_warning "kube-proxy is not running"
        log_info "You may need to restore kube-proxy for networking to work properly"
        log_info "This depends on your cluster configuration and other CNI plugins"
    else
        log_success "kube-proxy is already running"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_info "Cilium Uninstall Summary:"
    echo "=========================="
    echo "Cluster: $CLUSTER_NAME"
    echo "Cilium Version: $CILIUM_VERSION"
    echo "Namespace: $CILIUM_NAMESPACE (all components)"
    echo ""
    echo "Cleaned up:"
    echo "  ✅ Cilium Helm release"
    echo "  ✅ Cilium pods and deployments"
    echo "  ✅ Cilium CRDs"
    echo "  ✅ Cilium resources in kube-system"
    echo "  ✅ AWS IAM role and policies"
    echo ""
    echo "Next steps:"
    echo "  1. Install a new CNI plugin if needed"
    echo "  2. Restore kube-proxy if required"
    echo "  3. Test pod networking"
    echo ""
    echo "Useful commands:"
    echo "  Check remaining Cilium resources: oc get all -n kube-system | grep cilium"
    echo "  Check kube-proxy status: oc get pods -n kube-system -l k8s-app=kube-proxy"
    echo "  List IAM roles: aws iam list-roles --query 'Roles[?contains(RoleName, \"cilium\")]'"
}

# Function to cleanup on exit
cleanup() {
    log_info "Cleaning up temporary files..."
    # Add any cleanup tasks here if needed
}

# Main execution
main() {
    log_info "Starting Cilium CNI uninstall for ROSA HCP cluster"
    log_info "Cluster: $CLUSTER_NAME"
    log_info "Cilium Version: $CILIUM_VERSION"

    # Set trap for cleanup
    trap cleanup EXIT

    # Execute uninstall steps
    check_prerequisites
    uninstall_cilium
    cleanup_cilium_crds
    cleanup_cilium_namespaces
    cleanup_aws_iam_resources
    restore_kube_proxy
    display_cleanup_summary

    log_success "Cilium CNI uninstall completed successfully!"
    log_warning "Make sure to install a new CNI plugin or restore kube-proxy for networking to work"
}

# Run main function
main "$@"
