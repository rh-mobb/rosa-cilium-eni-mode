# ROSA HCP Cluster with Routable Pod CIDR

This project implements a Red Hat OpenShift Service on AWS (ROSA) Hosted Control Plane (HCP) cluster with routable pod CIDR configuration using Bring Your Own CNI (BYO-CNI) with MacVLAN.

## Overview

This solution enables direct routing to pods without NAT, providing:
- Better network performance
- Simplified network troubleshooting
- Direct external access to pods
- Integration with existing enterprise network infrastructure

## Project Structure

```
├── .cursorrules          # Project development rules and guidelines
├── design.md            # Architecture and design documentation
├── README.md            # This file
├── terraform/           # Infrastructure as Code definitions
├── manifests/           # Kubernetes manifests and configurations
├── scripts/             # Automation and utility scripts
├── docs/                # Additional documentation and guides
└── tests/               # Test configurations and validation scripts
```

## Prerequisites

- AWS account with appropriate permissions
- Red Hat OpenShift subscription
- AWS CLI configured
- Terraform installed
- OpenShift CLI (oc) installed
- Git for version control

## Quick Start

1. **Review the Design**: Start by reading [design.md](design.md) to understand the architecture
2. **Configure AWS**: Set up your AWS credentials and permissions
3. **Deploy Infrastructure**: Use Terraform to create the required AWS resources
4. **Create ROSA HCP Cluster**: Deploy the cluster with custom networking
5. **Configure CNI**: Set up MacVLAN CNI for routable pod networking
6. **Validate Deployment**: Test cluster functionality and network connectivity

## Key Features

- **Routable Pod CIDR**: Pod IPs are directly accessible from external networks
- **MacVLAN CNI**: Provides L2 connectivity for pods
- **High Availability**: Multi-AZ deployment for resilience
- **Security**: Comprehensive security policies and network segmentation
- **Monitoring**: Built-in observability and logging

## Documentation

- [Design Document](design.md) - Complete architecture and implementation details
- [Development Guidelines](.cursorrules) - Project rules and best practices
- [Additional Docs](docs/) - Detailed guides and procedures

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
