# ROSA HCP Cluster with Routable Pod CIDR - Quick Start

This guide shows you how to quickly deploy a ROSA HCP cluster with Cilium CNI in AWS ENI mode for directly routable pod IPs.

## Prerequisites

Before you begin, ensure you have:

- **AWS CLI** installed and configured with appropriate permissions
- **ROSA CLI** installed and logged in (`rosa login`)
- **OpenShift CLI (oc)** installed
- **Terraform** installed
- **Helm** installed
- **jq** installed for JSON processing
- **yq** installed for YAML processing (optional, for validation)

## Quick Deployment

### Option 1: Full Automated Deployment

Deploy everything in one command:

```bash
make deploy-all
```

This will:
1. Create network infrastructure (VPC, subnets, etc.)
2. Create ROSA HCP cluster with no CNI
3. Deploy Cilium CNI with AWS ENI mode
4. Auto-configure worker security groups for ENI mode
5. Test pod networking and connectivity

### Option 2: Step-by-Step Deployment

#### 1. Create Network Infrastructure

```bash
make network
```

This creates the VPC, subnets, and networking components needed for the cluster.

#### 2. Create ROSA HCP Cluster

```bash
make setup-cluster
```

This creates a ROSA HCP cluster with no CNI mode. The cluster will be in "NotReady" state until you install a CNI.

#### 3. Deploy Cilium CNI

```bash
make deploy-cilium
```

This deploys Cilium with AWS ENI mode, enabling directly routable pod IPs.

#### 4. Test Pod Networking

```bash
make test-pods
```

This creates a test pod and verifies that networking is working correctly.

#### 5. Test Full Network Connectivity (Optional)

```bash
make test-network
```

This runs a comprehensive connectivity test from inside a pod:
- **Internal Kubernetes API** - `kubernetes.default.svc.cluster.local`
- **External Kubernetes API** - Public API endpoint
- **OpenShift Console** - Web console URL
- **Internet** - google.com (validates egress)
- **Service discovery** - Curl second pod via Service DNS, ping pod IP directly
- **Pod-to-VM** - Pod curls VM httpd + **VM-to-pod** - VM pings pod (via SSM)

Useful after Cilium deployment to verify both in-cluster and external networking.

## Verification

### Check Cluster Status

```bash
make status
```

### Check Cilium Status

```bash
make cilium-status
```

### View Logs

```bash
make logs
```

## Configuration

You can customize the deployment using environment variables:

```bash
# Set cluster name
export CLUSTER_NAME=my-cluster

# Set AWS region
export AWS_REGION=us-west-2

# Run deployment
make deploy-all
```

## Accessing Your Cluster

After deployment, you can access your cluster:

```bash
# Get cluster info
make cluster-status

# Login to cluster (password is shown in cluster creation output)
oc login <api-url> -u cluster-admin -p <password>
```

## Cleanup

### Delete Everything

```bash
make clean-all
```

### Delete Cluster Only

```bash
make cluster-delete
```

### Delete Network Only

```bash
make network-cleanup
```

## Troubleshooting

### Check Progress

If deployment fails, you can check progress and resume:

```bash
# Check current progress
./scripts/create-rosa-cluster.sh --show-progress

# Reset progress and start fresh
./scripts/create-rosa-cluster.sh --reset-progress
```

### Common Issues

1. **Cluster in NotReady state**: This is normal until Cilium is deployed
2. **Cilium pods not starting**: Check AWS IAM permissions and IRSA configuration
3. **Network connectivity issues**: Verify security groups and VPC configuration
4. **DNS resolution failures**: Check if security groups allow pod-to-pod communication
5. **PVC provisioning stuck**: Check EBS CSI driver and CDI component health
6. **TLS handshake errors**: Restart CDI components if networking issues persist

### Advanced Troubleshooting

#### Check Cilium Configuration
```bash
# Verify Cilium values against official schema
yq eval helm/cilium-values.yaml > /dev/null

# Check deployed Cilium configuration
oc get configmap cilium-config -n kube-system -o yaml
```

#### Verify Security Groups
```bash
# Check if security group rule was added
aws ec2 describe-security-groups --group-ids <worker-sg-id> --query 'SecurityGroups[0].IpPermissions[*].[IpProtocol,FromPort,ToPort,UserIdGroupPairs[0].GroupId]' --output table
```

#### Test Pod Connectivity
```bash
# Create test pod for connectivity testing
oc run test-pod --image=busybox --rm -it --restart=Never -- sh

# Inside the pod, test connectivity
nslookup kubernetes.default.svc.cluster.local
wget -q -O- http://kubernetes.default.svc.cluster.local:443
```

### Get Help

```bash
# Show all available Make targets
make help

# Show script help
./scripts/create-rosa-cluster.sh --help
```

## What You Get

After successful deployment, you'll have:

- **ROSA HCP Cluster** with 3 worker nodes
- **Cilium CNI** with AWS ENI mode
- **Directly Routable Pod IPs** - pods get IPs directly from AWS ENI interfaces
- **No NAT Translation** - pods are first-class citizens in your VPC
- **High Performance Networking** - eBPF-based networking with kube-proxy replacement
- **Automatic Security Groups** - worker security groups auto-configured for ENI mode
- **DNS Resolution** - CoreDNS and service discovery working properly
- **Pod-to-Pod Communication** - direct connectivity between pods

## Next Steps

1. **Deploy Applications**: Your cluster is ready for workloads
2. **Configure Monitoring**: Set up monitoring and logging
3. **Security Hardening**: Implement network policies and security controls
4. **Backup Strategy**: Set up backup and disaster recovery

## Support

For detailed information:
- **Architecture**: See [design.md](design.md)
- **Scripts**: See [scripts/](scripts/) directory
- **Troubleshooting**: Check logs with `make logs`

---

**Note**: This deployment creates AWS resources that will incur costs. Remember to clean up when done testing.
