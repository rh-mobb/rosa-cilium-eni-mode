# ROSA HCP Cluster Deletion

This document describes how to safely delete a ROSA HCP cluster and all associated resources.

## Overview

The `delete-rosa-cluster.sh` script provides a comprehensive way to delete a ROSA HCP cluster and clean up all associated AWS resources. It handles the deletion in the correct order to avoid dependency issues.

## Usage

### Using Makefile (Recommended)

```bash
# Delete the cluster with all associated resources
make cluster-delete

# Or specify a different cluster name
CLUSTER_NAME=my-cluster make cluster-delete
```

### Using Script Directly

```bash
# Basic usage
./scripts/delete-rosa-cluster.sh

# With custom parameters
CLUSTER_NAME=my-cluster PREFIX=my-prefix ./scripts/delete-rosa-cluster.sh
```

## What Gets Deleted

The script deletes the following resources in order:

### 1. Cilium CNI (if deployed)
- Uninstalls Cilium Helm release
- Deletes Cilium pods and service accounts
- Cleans up Cilium resources

### 2. ROSA HCP Cluster
- Deletes the main cluster
- Waits for deletion to complete

### 3. IAM Roles
- **Operator Roles**: Roles used by the cluster operators
- **Account Roles**: Roles used by the cluster account
- **Cilium IAM Role**: Custom role created for Cilium IRSA

### 4. OIDC Configuration
- Deletes OIDC config (only if not used by other clusters)
- Checks for dependencies before deletion

### 5. AWS Resources
- **LoadBalancers**: Any LoadBalancers created by the cluster
- **IAM Roles**: Cilium-specific IAM roles and policies

## Configuration

The script uses the following environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `CLUSTER_NAME` | `pczarkow` | Name of the cluster to delete |
| `AWS_REGION` | `us-east-2` | AWS region where cluster is deployed |
| `PREFIX` | `pczarkow` | Prefix used for IAM roles |

## Prerequisites

Before running the deletion script, ensure you have:

1. **ROSA CLI**: Installed and logged in (`rosa login`)
2. **AWS CLI**: Installed and configured with appropriate permissions
3. **OpenShift CLI**: Installed (`oc`)
4. **Helm**: Installed for Cilium cleanup
5. **jq**: Installed for JSON parsing

## Safety Features

### Confirmation Prompts
- The script asks for confirmation before proceeding
- The Makefile target requires typing "yes" to confirm
- Multiple safety checks throughout the process

### Dependency Checks
- Checks if cluster exists before attempting deletion
- Verifies OIDC config is not used by other clusters
- Waits for cluster to be ready for deletion

### Error Handling
- Continues with cleanup even if some steps fail
- Provides detailed logging of all operations
- Graceful handling of missing resources

## Deletion Process

### Phase 1: Pre-deletion Checks
1. Verify prerequisites are met
2. Check if cluster exists
3. Get current cluster status
4. Wait for cluster to be ready for deletion

### Phase 2: CNI Cleanup
1. Check if Cilium is deployed
2. Uninstall Cilium using Helm or uninstall script
3. Clean up remaining Cilium resources

### Phase 3: Cluster Deletion
1. Delete the ROSA HCP cluster
2. Wait for deletion to complete
3. Verify cluster is fully deleted

### Phase 4: Resource Cleanup
1. Delete operator roles
2. Delete account roles
3. Delete OIDC configuration (if safe)
4. Clean up AWS resources (IAM roles, LoadBalancers)

### Phase 5: Verification
1. Display deletion summary
2. Confirm all resources are cleaned up

## Troubleshooting

### Common Issues

#### Cluster Stuck in "Deleting" State
```bash
# Check cluster status
rosa describe cluster -c <cluster-name>

# If stuck, you may need to wait or contact Red Hat support
```

#### IAM Roles Not Deleted
```bash
# Manually delete remaining roles
rosa list operator-roles --prefix <prefix>
rosa list account-roles --prefix <prefix>

# Delete each role individually
rosa delete operator-role --role-name <role-name> --yes
rosa delete account-role --role-name <role-name> --yes
```

#### OIDC Config Still Exists
```bash
# Check if OIDC config is used by other clusters
rosa list clusters -o json | jq '.[] | select(.aws.sts.oidc_config.id == "<oidc-config-id>")'

# If not used, delete manually
rosa delete oidc-config --oidc-config-id <oidc-config-id> --yes
```

### Manual Cleanup

If the script fails or times out, you may need to manually clean up:

1. **Check cluster status**:
   ```bash
   rosa list clusters
   ```

2. **Delete remaining IAM roles**:
   ```bash
   aws iam list-roles --query 'Roles[?contains(RoleName, `pczarkow`)].RoleName'
   ```

3. **Delete LoadBalancers**:
   ```bash
   aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `pczarkow`)].LoadBalancerArn'
   ```

## Example Output

```
[INFO] Starting ROSA HCP cluster deletion process
[INFO] Cluster: pczarkow
[INFO] Region: us-east-2
[INFO] Prefix: pczarkow

[INFO] Checking prerequisites...
[SUCCESS] Prerequisites check passed
[INFO] Checking if cluster 'pczarkow' exists...
[INFO] Cluster 'pczarkow' found
[INFO] Current cluster status: ready
[INFO] Waiting for cluster to be ready for deletion...
[INFO] Cluster status: ready - ready for deletion
[INFO] Deleting Cilium CNI...
[INFO] Cilium found, uninstalling...
[SUCCESS] Cilium CNI deleted
[INFO] Deleting ROSA HCP cluster 'pczarkow'...
[SUCCESS] Cluster deletion initiated
[INFO] Waiting for cluster deletion to complete...
[SUCCESS] Cluster 'pczarkow' has been deleted
[INFO] Deleting operator roles for prefix 'pczarkow'...
[SUCCESS] Operator roles deleted
[INFO] Deleting account roles for prefix 'pczarkow'...
[SUCCESS] Account roles deleted
[INFO] Deleting OIDC configuration...
[SUCCESS] OIDC config deleted
[INFO] Cleaning up AWS resources...
[SUCCESS] AWS resources cleaned up
[SUCCESS] Cluster deletion completed successfully!
```

## Security Considerations

- **IAM Permissions**: Ensure your AWS credentials have sufficient permissions to delete all resources
- **OIDC Safety**: The script checks for OIDC config dependencies before deletion
- **Data Loss**: This operation is irreversible - ensure you have backups of important data
- **Dependencies**: Check if other clusters or resources depend on the roles being deleted

## Best Practices

1. **Test First**: Test the deletion process in a non-production environment
2. **Backup Data**: Ensure important data is backed up before deletion
3. **Check Dependencies**: Verify no other resources depend on the cluster
4. **Monitor Costs**: Deletion should stop most AWS charges immediately
5. **Document Changes**: Keep track of any manual cleanup steps required

## Support

If you encounter issues during deletion:

1. Check the script logs for specific error messages
2. Verify all prerequisites are met
3. Check AWS CloudTrail for permission issues
4. Contact Red Hat support for ROSA-specific issues
5. Review the troubleshooting section above
