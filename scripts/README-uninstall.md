# Cilium Uninstall Script

## Overview

The `uninstall-cilium.sh` script provides a comprehensive way to remove Cilium CNI from your ROSA HCP cluster and clean up all associated AWS IAM resources.

## Features

- **Complete Cilium Removal**: Uninstalls Cilium Helm release and removes all pods
- **CRD Cleanup**: Removes all Cilium Custom Resource Definitions
- **Namespace Cleanup**: Removes Cilium-specific namespaces
- **AWS IAM Cleanup**: Deletes IAM roles, policies, and attachments
- **Safety Checks**: Verifies prerequisites and provides confirmation prompts
- **Comprehensive Logging**: Detailed output with color-coded status messages

## Usage

### Via Makefile (Recommended)
```bash
make cilium-uninstall
```

### Direct Script Execution
```bash
./scripts/uninstall-cilium.sh
```

### Environment Variables
- `CLUSTER_NAME`: Name of the cluster (default: current user)
- `CILIUM_VERSION`: Version of Cilium to uninstall (default: 1.15.4)

## What Gets Removed

### Kubernetes Resources
- Cilium Helm release
- All Cilium pods and deployments
- Cilium Custom Resource Definitions (CRDs)
- Cilium resources in kube-system namespace

### AWS IAM Resources
- IAM role: `cilium-operator-<cluster-name>`
- Custom policy: `cilium-custom-<cluster-name>`
- Policy attachments to AWS managed policies

## Prerequisites

- OpenShift CLI (`oc`) installed and connected to cluster
- Helm installed
- AWS CLI installed and configured
- Proper AWS permissions to delete IAM resources

## Safety Features

- **Confirmation Prompt**: Asks for confirmation before proceeding
- **Prerequisites Check**: Verifies all required tools are available
- **Graceful Handling**: Continues cleanup even if some resources don't exist
- **Detailed Logging**: Shows exactly what's being removed

## Example Output

```
[INFO] Checking prerequisites...
[SUCCESS] Connected to cluster: api-pczarkow-ocmb-p3-openshiftapps-com:443
[SUCCESS] Prerequisites check passed
[INFO] Checking if Cilium is installed...
[INFO] Cilium Helm release found
[INFO] Uninstalling Cilium CNI...
[INFO] Uninstalling Cilium Helm release...
[SUCCESS] Cilium Helm release uninstalled
[INFO] Waiting for Cilium pods to be removed...
[SUCCESS] All Cilium pods removed
[INFO] Cleaning up Cilium CRDs...
[SUCCESS] Cilium CRDs cleanup completed
[INFO] Cleaning up Cilium namespaces...
[INFO] All Cilium resources are deployed in kube-system namespace
[SUCCESS] Namespace cleanup completed (no separate namespaces to remove)
[INFO] Cleaning up AWS IAM resources...
[INFO] Cluster: api-pczarkow-ocmb-p3-openshiftapps-com:443
[INFO] Account ID: 660250927410
[INFO] Found IAM role: cilium-operator-api-pczarkow-ocmb-p3-openshiftapps-com:443
[INFO] Detaching policies from role...
[INFO] Deleting custom policy: cilium-custom-api-pczarkow-ocmb-p3-openshiftapps-com:443
[INFO] Deleting IAM role: cilium-operator-api-pczarkow-ocmb-p3-openshiftapps-com:443
[SUCCESS] IAM role deleted: cilium-operator-api-pczarkow-ocmb-p3-openshiftapps-com:443
[SUCCESS] AWS IAM resources cleanup completed
[SUCCESS] Cilium CNI uninstall completed successfully!
```

## Post-Uninstall Considerations

### Networking
After uninstalling Cilium, your cluster will have no CNI plugin. You may need to:

1. **Install a new CNI plugin** (e.g., Calico, Flannel, or another Cilium instance)
2. **Restore kube-proxy** if it was disabled by Cilium
3. **Test pod networking** to ensure connectivity works

### Verification Commands
```bash
# Check if Cilium resources are gone
oc get all -n kube-system | grep cilium

# Check kube-proxy status
oc get pods -n kube-system -l k8s-app=kube-proxy

# List remaining IAM roles
aws iam list-roles --query 'Roles[?contains(RoleName, "cilium")]'
```

## Troubleshooting

### Common Issues

1. **Permission Denied**: Ensure AWS credentials have sufficient permissions to delete IAM resources
2. **Pods Not Removing**: Some pods may take time to terminate; the script waits up to 5 minutes
3. **CRD Removal Fails**: Some CRDs may have finalizers; check cluster events for details

### Manual Cleanup

If the script fails partway through, you can manually clean up:

```bash
# Remove remaining Cilium resources
oc delete all -n kube-system -l k8s-app=cilium
oc delete all -n cilium-operator --all

# Remove CRDs manually
oc delete crd ciliumidentities.cilium.io
oc delete crd ciliumnodes.cilium.io
# ... (list all Cilium CRDs)

# Remove IAM resources manually
aws iam detach-role-policy --role-name cilium-operator-<cluster-name> --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
aws iam delete-role --role-name cilium-operator-<cluster-name>
```

## Security Notes

- The script only removes resources it created during Cilium installation
- It won't affect other IAM roles or policies in your account
- All operations are logged for audit purposes
- The script requires explicit confirmation before proceeding

## Related Scripts

- `deploy-cilium.sh`: Install Cilium CNI
- `create-rosa-cluster.sh`: Create ROSA HCP cluster
- `list-oidc-status.sh`: Manage OIDC configurations
