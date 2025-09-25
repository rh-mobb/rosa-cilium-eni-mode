# Cilium CNI Deployment for ROSA HCP

This directory contains scripts for deploying and managing Cilium CNI on ROSA HCP clusters with AWS ENI mode.

## Overview

Cilium is deployed using Helm with AWS ENI mode enabled, providing:
- **Direct pod IP routing** within the VPC
- **kube-proxy replacement** for better performance
- **Hubble observability** for network monitoring
- **Network policies** for security
- **Idempotent deployment** - safe to run multiple times

## Idempotent Behavior

The deployment script is designed to be **idempotent**, meaning it can be run multiple times safely:

- **Existing Resources**: Checks for existing IAM roles, Helm releases, and namespaces
- **Configuration Validation**: Verifies current cluster OIDC configuration matches AWS resources
- **Smart Updates**: Only updates resources that need changes (e.g., trust policies, Helm values)
- **Safe Re-runs**: Can be executed repeatedly without causing conflicts or errors

### What Gets Checked/Updated:
- ✅ **IAM Role Trust Policy**: Updated to match current cluster OIDC endpoint
- ✅ **Helm Repository**: Added if missing, updated if exists
- ✅ **Helm Release**: Upgraded with current configuration if needed
- ✅ **Namespaces**: Created if missing, skipped if exists
- ✅ **Service Accounts**: Updated with correct IRSA annotations

## Prerequisites

Before deploying Cilium, ensure you have:

1. **ROSA HCP cluster** created with `--no-cni` mode
2. **OpenShift CLI (oc)** installed and configured
3. **kubectl** installed
4. **Helm** installed (v3.x)
5. **Cluster access** - you must be logged in to the cluster

## Quick Start

### 1. Deploy Cilium CNI
```bash
# Using Makefile
make deploy-cilium

# Or directly
./scripts/deploy-cilium.sh
```

### 2. Check Status
```bash
# Check Cilium status
make cilium-status

# Check logs
make cilium-logs

# Run connectivity test
make cilium-test
```

## Configuration

The script uses the following default configuration:

- **Cilium Version**: 1.15.4
- **IPAM Mode**: AWS ENI
- **kube-proxy Replacement**: Enabled
- **Hubble Observability**: Enabled
- **Namespace**: kube-system

### Customizing Configuration

You can customize the deployment by setting environment variables:

```bash
export CILIUM_VERSION="1.15.5"
export CLUSTER_NAME="my-cluster"
./scripts/deploy-cilium.sh
```

## What the Script Does

1. **Prerequisites Check**
   - Verifies required tools are installed
   - Checks cluster connectivity
   - Validates cluster readiness

2. **Namespace Creation**
   - Creates `kube-system` namespace for Cilium
   - Creates `cilium-operator` namespace for operator

3. **Helm Repository Setup**
   - Adds Cilium Helm repository
   - Updates repository index

4. **Cilium Deployment**
   - Deploys Cilium using Helm with AWS ENI configuration
   - Configures kube-proxy replacement
   - Enables Hubble observability

5. **Verification**
   - Waits for pods to be ready
   - Verifies Cilium status
   - Checks kube-proxy replacement

## Troubleshooting

### Common Issues

1. **Helm not found**
   ```bash
   # Install Helm
   curl https://get.helm.sh/helm-v3.12.0-linux-amd64.tar.gz | tar xz
   sudo mv linux-amd64/helm /usr/local/bin/
   ```

2. **Cluster not accessible**
   ```bash
   # Login to cluster
   oc login <cluster-api-url> -u admin -p <password>
   ```

3. **Cilium pods not starting**
   ```bash
   # Check pod logs
   oc logs -n kube-system -l k8s-app=cilium

   # Check events
   oc get events -n kube-system
   ```

### Useful Commands

```bash
# Check Cilium status
oc exec -n kube-system -l k8s-app=cilium -- cilium status

# Check Cilium configuration
oc exec -n kube-system -l k8s-app=cilium -- cilium config

# Check ENI allocation
oc exec -n kube-system -l k8s-app=cilium -- cilium status --verbose

# Access Hubble UI
oc port-forward -n kube-system svc/hubble-ui 12000:80
# Then open http://localhost:12000
```

## Network Architecture

With Cilium in AWS ENI mode:

- **Pod IPs** are directly assigned from AWS ENI IPs
- **No overlay networking** - pods get VPC IPs
- **Direct routing** - no encapsulation overhead
- **Security groups** can be used for pod-level security
- **VPC route tables** handle pod-to-pod communication

## Security Considerations

- **Network Policies** are enabled for micro-segmentation
- **Cilium Network Policies** provide advanced security features
- **Hubble** provides network observability and monitoring
- **kube-proxy replacement** reduces attack surface

## Monitoring

Cilium provides several monitoring options:

1. **Hubble UI** - Web-based network observability
2. **Cilium metrics** - Prometheus-compatible metrics
3. **Cilium CLI** - Command-line status and debugging

Access Hubble UI:
```bash
oc port-forward -n kube-system svc/hubble-ui 12000:80
```

## Cleanup

To remove Cilium:

```bash
# Uninstall Cilium
helm uninstall cilium -n kube-system

# Remove namespaces (optional)
oc delete namespace cilium-operator
```

## Support

For issues with Cilium deployment:

1. Check the [Cilium documentation](https://docs.cilium.io/)
2. Review [Cilium troubleshooting guide](https://docs.cilium.io/en/stable/operations/troubleshooting/)
3. Check cluster events and pod logs
4. Verify AWS ENI limits and permissions
