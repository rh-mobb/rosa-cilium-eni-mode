#!/bin/bash

# Cilium CNI Deployment Script for ROSA HCP
# This script deploys and configures Cilium CNI in AWS ENI mode

set -eox  # Exit on any error

# Configuration variables
CLUSTER_NAME="${CLUSTER_NAME:-$(whoami)}"
CILIUM_VERSION="${CILIUM_VERSION:-1.18.2}"
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
        log_info "Please install the OpenShift CLI: https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html"
        exit 1
    fi

    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        log_info "Please install kubectl: https://kubernetes.io/docs/tasks/tools/"
        exit 1
    fi

    # Check if helm is installed
    if ! command -v helm &> /dev/null; then
        log_error "Helm is not installed or not in PATH"
        log_info "Please install Helm: https://helm.sh/docs/intro/install/"
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
        log_info "Please configure AWS credentials:"
        log_info "  aws configure"
        log_info "  or set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
        exit 1
    fi

    # Get cluster info
    local cluster_name=$(oc config current-context | cut -d'/' -f2)
    log_success "Connected to cluster: $cluster_name"

    # Check if cluster is ready
    local cluster_status=$(oc get nodes --no-headers | wc -l)
    if [ "$cluster_status" -eq 0 ]; then
        log_error "No worker nodes found in cluster"
        log_info "Please ensure the cluster is fully provisioned and has worker nodes"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Function to create Cilium namespace
create_cilium_namespace() {
    log_info "Ensuring Cilium namespace exists: $CILIUM_NAMESPACE"

    if oc get namespace "$CILIUM_NAMESPACE" &> /dev/null; then
        log_info "Namespace $CILIUM_NAMESPACE already exists"
    else
        log_info "Creating namespace: $CILIUM_NAMESPACE"
        oc create namespace "$CILIUM_NAMESPACE"
        log_success "Created namespace: $CILIUM_NAMESPACE"
    fi
}

# Function to create Cilium operator namespace
create_cilium_operator_namespace() {
    log_info "Using kube-system namespace for Cilium operator"
    log_success "Cilium operator will be deployed to kube-system namespace"
}

# Function to add Cilium Helm repository
add_cilium_helm_repo() {
    log_info "Setting up Cilium Helm repository..."

    # Check if repository already exists
    if helm repo list | grep -q cilium; then
        log_info "Cilium Helm repository already exists, updating..."
        helm repo update cilium
    else
        log_info "Adding Cilium Helm repository..."
        helm repo add cilium https://helm.cilium.io/
        helm repo update cilium
    fi

    log_success "Cilium Helm repository ready"
}


# Function to check if IRSA role exists and is correct
check_existing_irsa_role() {
    log_info "Checking for existing IRSA role..."

    local role_name="cilium-operator-${CLUSTER_NAME}"

    if aws iam get-role --role-name "$role_name" &> /dev/null; then
        log_info "Found existing IAM role: $role_name"

        # Get current trust policy
        local current_trust_policy=$(aws iam get-role --role-name "$role_name" --query 'Role.AssumeRolePolicyDocument' --output json)

        # Get current cluster OIDC info
        local account_id=$(aws sts get-caller-identity --query Account --output text)
        local oidc_issuer=$(oc get authentication.config.openshift.io cluster -o json | jq -r '.spec.serviceAccountIssuer' 2>/dev/null || echo "")
        local oidc_url=$(echo "$oidc_issuer" | sed -e "s/^https:\/\///")

        # Check if trust policy matches current cluster
        local expected_subject="system:serviceaccount:${CILIUM_NAMESPACE}:cilium-operator"
        if echo "$current_trust_policy" | jq -r '.Statement[0].Condition.StringEquals."'${oidc_url}':sub"' | grep -q "$expected_subject"; then
            log_success "IRSA role trust policy matches current cluster"
            CILIUM_ROLE_ARN="arn:aws:iam::${account_id}:role/${role_name}"
            return 0
        else
            log_warning "IRSA role trust policy doesn't match current cluster"
            log_info "Will update trust policy to match current cluster"
            return 1
        fi
    else
        log_info "No existing IAM role found: $role_name"
        return 1
    fi
}

# Function to update IRSA role trust policy
update_irsa_role_trust_policy() {
    log_info "Updating IRSA role trust policy..."

    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local role_name="cilium-operator-${CLUSTER_NAME}"

    # Get OIDC issuer from OpenShift cluster authentication config
    local oidc_issuer=$(oc get authentication.config.openshift.io cluster -o json | jq -r '.spec.serviceAccountIssuer' 2>/dev/null || echo "")
    local oidc_url=$(echo "$oidc_issuer" | sed -e "s/^https:\/\///")

    # Create updated trust policy
    cat <<EOF > /tmp/cilium-trust-policy-updated.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${account_id}:oidc-provider/${oidc_url}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${oidc_url}:sub": "system:serviceaccount:${CILIUM_NAMESPACE}:cilium-operator"
        }
      }
    },
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${account_id}:oidc-provider/${oidc_url}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${oidc_url}:sub": "system:serviceaccount:${CILIUM_NAMESPACE}:cilium"
        }
      }
    }
  ]
}
EOF

    # Update trust policy
    aws iam update-assume-role-policy \
        --role-name "$role_name" \
        --policy-document file:///tmp/cilium-trust-policy-updated.json

    log_success "Updated trust policy for role: $role_name"

    # Cleanup temp file
    rm -f /tmp/cilium-trust-policy-updated.json
}

# Function to create IRSA role for Cilium
create_cilium_irsa_role() {
    log_info "Setting up IRSA role for Cilium..."

    # Check if role already exists and is correct
    if check_existing_irsa_role; then
        log_success "IRSA role is already correctly configured"
        return 0
    fi

    # Role doesn't exist or needs updating
    local account_id=$(aws sts get-caller-identity --query Account --output text)

    # Get OIDC issuer from OpenShift cluster authentication config
    log_info "Getting OIDC issuer from OpenShift cluster..."
    local oidc_issuer=$(oc get authentication.config.openshift.io cluster -o json | jq -r '.spec.serviceAccountIssuer' 2>/dev/null || echo "")

    if [ -z "$oidc_issuer" ] || [ "$oidc_issuer" = "null" ]; then
        log_error "Could not get OIDC issuer from OpenShift cluster"
        log_info "Make sure you're connected to the cluster and have proper permissions"
        exit 1
    fi

    local oidc_url=$(echo "$oidc_issuer" | sed -e "s/^https:\/\///")

    log_info "Cluster: $CLUSTER_NAME"
    log_info "Account ID: $account_id"
    log_info "OIDC Issuer: $oidc_issuer"

    # Create trust policy for IRSA
    cat <<EOF > /tmp/cilium-trust-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${account_id}:oidc-provider/${oidc_url}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${oidc_url}:sub": "system:serviceaccount:${CILIUM_NAMESPACE}:cilium-operator"
        }
      }
    },
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${account_id}:oidc-provider/${oidc_url}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${oidc_url}:sub": "system:serviceaccount:${CILIUM_NAMESPACE}:cilium"
        }
      }
    }
  ]
}
EOF

    # Create or update IAM role for Cilium
    local role_name="cilium-operator-${CLUSTER_NAME}"

    if aws iam get-role --role-name "$role_name" &> /dev/null; then
        log_info "Updating existing IAM role: $role_name"
        update_irsa_role_trust_policy
    else
        log_info "Creating new IAM role: $role_name"
        aws iam create-role \
            --role-name "$role_name" \
            --assume-role-policy-document file:///tmp/cilium-trust-policy.json \
            --description "IRSA role for Cilium operator in cluster ${CLUSTER_NAME}"
    fi

    # Attach required policies
    log_info "Attaching AWS managed policies..."
    aws iam attach-role-policy \
        --role-name "cilium-operator-${CLUSTER_NAME}" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy" \
        2>/dev/null || log_warning "Policy may already be attached"

    # Create custom policy for additional permissions
    cat <<EOF > /tmp/cilium-custom-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeNetworkInterfaces",
        "ec2:AttachNetworkInterface",
        "ec2:DetachNetworkInterface",
        "ec2:CreateNetworkInterface",
        "ec2:DeleteNetworkInterface",
        "ec2:ModifyNetworkInterfaceAttribute",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeRouteTables",
        "ec2:DescribeVpcs",
        "ec2:DescribeAvailabilityZones",
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "ec2:DescribeImages",
        "ec2:DescribeVolumes",
        "ec2:DescribeSnapshots"
      ],
      "Resource": "*"
    }
  ]
}
EOF

    # Create and attach custom policy
    aws iam create-policy \
        --policy-name "cilium-custom-${CLUSTER_NAME}" \
        --policy-document file:///tmp/cilium-custom-policy.json \
        --description "Custom policy for Cilium operator in cluster ${CLUSTER_NAME}" \
        2>/dev/null || log_warning "Custom policy may already exist"

    aws iam attach-role-policy \
        --role-name "cilium-operator-${CLUSTER_NAME}" \
        --policy-arn "arn:aws:iam::${account_id}:policy/cilium-custom-${CLUSTER_NAME}" \
        2>/dev/null || log_warning "Custom policy may already be attached"

    # Set the role ARN for use in Helm deployment
    CILIUM_ROLE_ARN="arn:aws:iam::${account_id}:role/cilium-operator-${CLUSTER_NAME}"
    log_success "IRSA role created: $CILIUM_ROLE_ARN"

    # Cleanup temp files
    rm -f /tmp/cilium-trust-policy.json /tmp/cilium-custom-policy.json
}

# Function to check if Cilium is already deployed

# Function to deploy Cilium using Helm
deploy_cilium() {
    log_info "Deploying Cilium CNI using Helm with IRSA..."

    # Deploy Cilium with AWS ENI configuration and IRSA
    log_info "Installing/upgrading Cilium Helm release..."

    # Get the directory of this script to find the helm values file
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local values_file="${script_dir}/../helm/cilium-values.yaml"

    # Verify the values file exists
    if [[ ! -f "$values_file" ]]; then
        log_error "Cilium values file not found: $values_file"
        return 1
    fi

    log_info "Using Cilium values file: $values_file"

    helm upgrade --install cilium cilium/cilium \
        --version "$CILIUM_VERSION" \
        --namespace "$CILIUM_NAMESPACE" \
        --values "$values_file" \
        --set cluster.name="$CLUSTER_NAME" \
        --set serviceAccounts.cilium.annotations."eks\.amazonaws\.com/role-arn"="$CILIUM_ROLE_ARN" \
        --set serviceAccounts.operator.annotations."eks\.amazonaws\.com/role-arn"="$CILIUM_ROLE_ARN" \
        --wait \
        --timeout=10m

    log_success "Cilium installation completed with IRSA"
}

# Function to wait for Cilium to be ready
wait_for_cilium() {
    log_info "Waiting for Cilium to be ready..."

    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        local cilium_pods=$(oc get pods -n "$CILIUM_NAMESPACE" -l k8s-app=cilium --no-headers | wc -l)
        local ready_pods=$(oc get pods -n "$CILIUM_NAMESPACE" -l k8s-app=cilium --no-headers | grep "Running" | wc -l)

        if [ "$cilium_pods" -gt 0 ] && [ "$ready_pods" -eq "$cilium_pods" ]; then
            log_success "Cilium pods are ready ($ready_pods/$cilium_pods)"
            break
        else
            log_info "Waiting for Cilium pods... ($ready_pods/$cilium_pods ready) (attempt $attempt/$max_attempts)"
            sleep 30
            attempt=$((attempt + 1))
        fi
    done

    if [ $attempt -gt $max_attempts ]; then
        log_error "Cilium pods did not become ready within expected time"
        log_info "Checking pod status:"
        oc get pods -n "$CILIUM_NAMESPACE" -l k8s-app=cilium
        exit 1
    fi
}

# Function to verify Cilium installation
verify_cilium() {
    log_info "Verifying Cilium installation..."

    # Check Cilium pods
    log_info "Cilium pods status:"
    oc get pods -n "$CILIUM_NAMESPACE" -l k8s-app=cilium

    # Check Cilium operator pods
    log_info "Cilium operator pods status:"
    oc get pods -n "$CILIUM_NAMESPACE" -l name=cilium-operator

    # Check operator logs if there are issues
    local operator_pods=$(oc get pods -n "$CILIUM_NAMESPACE" -l name=cilium-operator --no-headers | grep -v Running | wc -l)
    if [ "$operator_pods" -gt 0 ]; then
        log_warning "Some Cilium operator pods are not running. Checking logs..."
        oc logs -n "$CILIUM_NAMESPACE" -l name=cilium-operator --tail=20
    fi

    # Check Cilium status
    log_info "Checking Cilium status..."
    local cilium_pod=$(oc get pods -n "$CILIUM_NAMESPACE" -l k8s-app=cilium --no-headers | head -1 | awk '{print $1}')
    if [ -n "$cilium_pod" ]; then
        oc exec -n "$CILIUM_NAMESPACE" "$cilium_pod" -- cilium status
    else
        log_warning "No Cilium pods found to check status"
    fi

    # Check if kube-proxy is disabled
    log_info "Checking kube-proxy status..."
    local kube_proxy_pods=$(oc get pods -n kube-system -l k8s-app=kube-proxy --no-headers | wc -l)
    if [ "$kube_proxy_pods" -eq 0 ]; then
        log_success "kube-proxy is disabled (expected with Cilium)"
    else
        log_warning "kube-proxy pods still exist: $kube_proxy_pods"
    fi

    # Check IRSA configuration
    log_info "Checking IRSA configuration..."
    local cilium_sa=$(oc get serviceaccount cilium -n "$CILIUM_NAMESPACE" -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null || echo "")
    local operator_sa=$(oc get serviceaccount cilium-operator -n "$CILIUM_NAMESPACE" -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null || echo "")

    if [ -n "$cilium_sa" ] && [ -n "$operator_sa" ]; then
        log_success "IRSA configured for both service accounts"
        log_info "Cilium SA role: $cilium_sa"
        log_info "Operator SA role: $operator_sa"
    else
        log_warning "IRSA may not be properly configured"
        log_info "Cilium SA role: ${cilium_sa:-'Not set'}"
        log_info "Operator SA role: ${operator_sa:-'Not set'}"
    fi

    log_success "Cilium verification completed"
}

# Function to display Cilium information
display_cilium_info() {
    log_info "Cilium CNI Information:"
    echo "========================"
    echo "Cilium Version: $CILIUM_VERSION"
    echo "Namespace: $CILIUM_NAMESPACE (all components)"
    echo "IPAM Mode: AWS ENI"
    echo "Kube-proxy Replacement: Enabled"
    echo "Hubble Observability: Enabled"
    echo "AWS Authentication: IRSA (IAM Roles for Service Accounts)"
    echo ""

    # Get cluster info
    echo "Cluster: $CLUSTER_NAME"

    # Get node info
    local node_count=$(oc get nodes --no-headers | wc -l)
    echo "Worker Nodes: $node_count"

    # Get Cilium pod info
    local cilium_pods=$(oc get pods -n "$CILIUM_NAMESPACE" -l k8s-app=cilium --no-headers | wc -l)
    echo "Cilium Pods: $cilium_pods"

    echo ""
    echo "Useful Commands:"
    echo "  Check Cilium status: oc exec -n $CILIUM_NAMESPACE \$(oc get pods -n $CILIUM_NAMESPACE -l k8s-app=cilium --no-headers | head -1 | awk '{print \$1}') -- cilium status"
    echo "  Check Cilium logs: oc logs -n $CILIUM_NAMESPACE -l k8s-app=cilium"
    echo "  Check Hubble UI: oc port-forward -n $CILIUM_NAMESPACE svc/hubble-ui 12000:80"
    echo "  Check Cilium connectivity: oc exec -n $CILIUM_NAMESPACE \$(oc get pods -n $CILIUM_NAMESPACE -l k8s-app=cilium --no-headers | head -1 | awk '{print \$1}') -- cilium connectivity test"
    echo ""
    echo "Troubleshooting:"
    echo "  If Cilium operator is in CrashLoopBackOff, check AWS IAM permissions:"
    echo "  - ec2:DescribeInstances"
    echo "  - ec2:DescribeNetworkInterfaces"
    echo "  - ec2:AttachNetworkInterface"
    echo "  - ec2:DetachNetworkInterface"
    echo "  - ec2:CreateNetworkInterface"
    echo "  - ec2:DeleteNetworkInterface"
    echo "  - ec2:ModifyNetworkInterfaceAttribute"
  echo "  - ec2:DescribeSubnets"
  echo "  - ec2:DescribeSecurityGroups"
  echo "  - ec2:DescribeRouteTables"
}

# Function to cleanup on exit
cleanup() {
    log_info "Cleaning up temporary files..."
    # Add any cleanup tasks here if needed
}

# Function to show deployment summary
show_deployment_summary() {
    log_info "Cilium Deployment Summary:"
    echo "=========================="
    echo "Cluster: $CLUSTER_NAME"
    echo "Cilium Version: $CILIUM_VERSION"
    echo "Namespace: $CILIUM_NAMESPACE (all components)"
    echo "IPAM Mode: AWS ENI"
    echo "Authentication: IRSA (IAM Roles for Service Accounts)"
    echo ""
    echo "This script is idempotent and will:"
    echo "  ✅ Check prerequisites"
    echo "  ✅ Ensure namespaces exist"
    echo "  ✅ Set up Helm repository"
    echo "  ✅ Create/update IRSA role with current cluster OIDC"
    echo "  ✅ Deploy/update Cilium with correct configuration"
    echo "  ✅ Verify deployment"
    echo ""
}

# Main execution
main() {
    log_info "Starting Cilium CNI deployment for ROSA HCP cluster"
    show_deployment_summary

    # Set trap for cleanup
    trap cleanup EXIT

    # Execute deployment steps
    check_prerequisites
    create_cilium_namespace
    create_cilium_operator_namespace
    add_cilium_helm_repo
    create_cilium_irsa_role
    deploy_cilium
    wait_for_cilium
    verify_cilium
    display_cilium_info

    log_success "Cilium CNI deployment completed successfully!"
    log_info "Your ROSA HCP cluster now has Cilium CNI with AWS ENI mode enabled"
}

# Run main function
main "$@"
