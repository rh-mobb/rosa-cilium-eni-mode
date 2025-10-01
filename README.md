# ROSA HCP Cluster with Routable Pod CIDR

This project implements a Red Hat OpenShift Service on AWS (ROSA) Hosted Control Plane (HCP) cluster with routable pod CIDR configuration using Bring Your Own CNI (BYO-CNI) with Cilium AWS ENI mode.

## Overview

This solution enables direct routing to pods without NAT, providing:
- Better network performance with eBPF-based networking
- Simplified network troubleshooting with directly routable pod IPs
- Direct external access to pods via AWS ENI interfaces
- Integration with existing enterprise network infrastructure
- Automatic security group configuration for ENI mode

## Prerequisites

- AWS account with appropriate permissions
- Red Hat OpenShift subscription
- AWS CLI configured
- ROSA CLI installed and logged in
- Terraform installed
- OpenShift CLI (oc) installed
- Helm installed
- Git for version control

## Quick Start

1. **Review the Design**: Start by reading [design.md](design.md) to understand the architecture
2. **Follow Quick Start**: Use [QUICKSTART.md](QUICKSTART.md) for step-by-step deployment
3. **Automated Deployment**: Run `make deploy-all` for full automated deployment
4. **Manual Deployment**: Use individual `make` targets for step-by-step control
5. **Validate Deployment**: Test cluster functionality and network connectivity

## Automated Deployment (`make deploy-all`)

The `make deploy-all` command provides a complete automated deployment that:

### Infrastructure Provisioning
- **Terraform**: Creates VPC, subnets, and networking infrastructure in AWS
- **Multi-AZ Setup**: Deploys across multiple availability zones for high availability
- **Tag Preservation**: Respects existing AWS resource tags to avoid conflicts

### ROSA Cluster Deployment
- **ROSA CLI**: Creates the ROSA HCP cluster with BYO-CNI configuration
- **Account Roles**: Sets up required AWS IAM roles for cluster operations
- **Operator Roles**: Creates operator-specific IAM roles for cluster components
- **OIDC Configuration**: Establishes OpenID Connect integration for secure authentication

### CNI Configuration
- **Helm Deployment**: Installs Cilium CNI in AWS ENI mode using Helm charts
- **ENI Mode**: Configures pods to use AWS Elastic Network Interfaces for direct routing
- **Kube-proxy Replacement**: Enables eBPF-based service mesh and load balancing
- **Security Group Auto-configuration**: Automatically modifies worker node security groups

### Infrastructure Modifications
The deployment automatically modifies AWS infrastructure:

- **Security Groups**: Adds ingress rules to worker node security groups to allow inter-pod communication required for ENI mode
- **IAM Roles**: Creates and configures IRSA (IAM Roles for Service Accounts) for Cilium components
- **Network Policies**: Establishes proper routing between pod CIDR and service CIDR

### What Gets Created
- VPC with public/private subnets across multiple AZs
- ROSA HCP cluster with routable pod CIDR
- Cilium CNI with AWS ENI mode configuration
- Required IAM roles and policies
- Security group rules for pod-to-pod communication
- Hubble observability stack

## Key Features

- **Routable Pod CIDR**: Pod IPs are directly accessible from external networks via AWS ENI interfaces
- **Cilium CNI**: AWS ENI mode with eBPF-based networking for high performance
- **Kube-proxy Replacement**: Full kube-proxy replacement with eBPF
- **Automatic Security Groups**: Auto-configuration of worker security groups for ENI mode
- **High Availability**: Multi-AZ deployment for resilience
- **Security**: Comprehensive security policies and network segmentation
- **Monitoring**: Built-in observability with Hubble

## Documentation

- [Design Document](design.md) - Complete architecture and implementation details
- [Quick Start Guide](QUICKSTART.md) - Step-by-step deployment instructions
- [Development Guidelines](.cursorrules) - Project rules and best practices
- [Scripts Documentation](scripts/) - Individual script documentation

## Contributing

Please read the [development guidelines](.cursorrules) before contributing. Key points:
- Always consult design.md before making architectural decisions
- Ask before making any design changes
- Keep documentation up to date
- Follow security best practices

## Support

For issues and questions:
1. Check the [design document](design.md) for architecture details
2. Review the [troubleshooting guide](docs/troubleshooting.md)
3. Create an issue with detailed information

## License

This project follows Red Hat and AWS licensing requirements.
