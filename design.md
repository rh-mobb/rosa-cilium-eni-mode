# ROSA HCP Cluster with Routable Pod CIDR - Design Document

## Overview
This project implements a Red Hat OpenShift Service on AWS (ROSA) Hosted Control Plane (HCP) cluster with routable pod CIDR configuration. This design enables direct routing to pods without NAT, providing better network performance and simplified network troubleshooting.

## Architecture Overview

### Core Components
1. **ROSA HCP Cluster**: Red Hat managed control plane with customer-managed worker nodes
2. **Routable Pod CIDR**: Pod IPs are directly routable from external networks
3. **Custom CNI**: Bring Your Own CNI (BYO-CNI) with Cilium AWS ENI mode for pod networking
4. **AWS Infrastructure**: VPC, subnets, route tables, and security groups

### Network Architecture

#### Pod CIDR Configuration
- **VPC CIDR Range**: `10.0.0.0/16` (configurable)
- **Pod IP Assignment**: Direct ENI IP assignment (no traditional Pod CIDR)
- **Node CIDR**: Uses VPC CIDR for node management
- **Service CIDR**: `172.30.0.0/16` (OpenShift default)
- **Cluster CIDR**: `10.128.0.0/14` (OpenShift default)

#### Routing Strategy
- Pod IPs are directly routable within the VPC using AWS ENI IPs
- No NAT translation for pod-to-external communication
- Cilium AWS ENI mode assigns ENI IPs to pods
- Direct routing through AWS ENI interfaces
- Pods appear as first-class citizens in the VPC

### Infrastructure Components

#### AWS Resources
1. **VPC Configuration**
   - Dedicated VPC for ROSA HCP cluster
   - Multiple availability zones for high availability
   - Pod CIDR as subset of VPC CIDR for simplified routing

2. **Subnet Design**
   - Management subnets for control plane components
   - Worker node subnets for compute resources
   - Pod IPs assigned directly from AWS ENI interfaces
   - Multus CNI integration for ROSA compatibility

3. **Security Groups**
   - Cluster-wide security policies
   - Pod-to-pod communication rules
   - External access controls

#### CNI Configuration
- **Cilium CNI**: AWS ENI mode (`ipam.mode: eni`) for directly routable pods
- **Multus Integration**: Chaining mode with portmap for ROSA compatibility
- **ENI IP Assignment**: Pods get IPs directly from AWS ENI interfaces
- **IRSA Authentication**: IAM Roles for Service Accounts for AWS API access
- **Security Group Auto-Configuration**: Automatic worker security group configuration for ENI mode
- **Network policies**: Implemented through Cilium NetworkPolicy
- **Service mesh integration**: Cilium native service mesh or Istio
- **Kube-proxy Replacement**: Full kube-proxy replacement with eBPF for high performance

### Deployment Strategy

#### Phase 1: Infrastructure Setup
1. Create AWS VPC and networking components
2. Configure route tables for pod CIDR
3. Set up security groups and NACLs
4. Validate network connectivity

#### Phase 2: ROSA HCP Cluster Creation
1. Deploy ROSA HCP cluster with `--no-cni` mode
2. Configure OIDC and IAM roles for cluster
3. Validate cluster functionality
4. Test basic cluster operations

#### Phase 3: Cilium CNI Deployment
1. Deploy Cilium using Helm with ENI mode configuration
2. Configure IRSA for AWS API access
3. Auto-configure worker security groups for ENI mode
4. Set up Multus CNI integration
5. Test pod-to-pod communication with ENI IPs
6. Verify DNS resolution and service connectivity

#### Phase 4: Production Readiness
1. Implement monitoring and logging
2. Set up backup and disaster recovery
3. Configure security scanning
4. Document operational procedures

### Security Considerations

#### Network Security
- Network segmentation between management and workload networks
- Pod-to-pod communication policies
- External access controls and firewalling
- Encryption in transit for all communications

#### Cluster Security
- RBAC policies for cluster access
- Pod security standards enforcement
- Image scanning and vulnerability management
- Secrets management and encryption

### Monitoring and Observability

#### Metrics Collection
- Cluster health and performance metrics
- Network traffic and connectivity metrics
- Application performance monitoring
- Security event logging

#### Logging Strategy
- Centralized logging for all components
- Network flow logging for troubleshooting
- Audit logging for security compliance
- Application logs aggregation

### Disaster Recovery

#### Backup Strategy
- Cluster configuration backup
- Application data backup
- Network configuration backup
- Disaster recovery procedures

#### High Availability
- Multi-AZ deployment for worker nodes
- Control plane high availability (managed by Red Hat)
- Network redundancy and failover
- Application-level resilience

### Operational Procedures

#### Day 1 Operations
- Cluster provisioning and initial configuration
- Network connectivity validation
- Basic application deployment
- Monitoring setup

#### Day 2 Operations
- Performance optimization
- Security hardening
- Backup implementation
- Documentation updates

### Configuration Management

#### Infrastructure as Code
- Terraform for AWS VPC resource management
- Helm for Cilium CNI deployment
- Shell scripts for cluster and CNI automation
- GitOps for cluster configuration
- Version control for all configurations
- Automated testing and validation

#### Environment Management
- Development environment for testing
- Staging environment for validation
- Production environment for live workloads
- Environment promotion procedures

## Implementation Details

### Current Implementation
The project uses the following components and approaches:

#### Cluster Creation
- **ROSA CLI**: `rosa create cluster` with `--no-cni` mode
- **OIDC Configuration**: Two-step process (create config, then provider)
- **IAM Roles**: Account roles and operator roles for cluster management
- **Admin Access**: Auto-generated admin password for cluster access
- **Status**: ✅ Successfully deployed and operational

#### CNI Deployment
- **Helm-based**: Cilium deployed using Helm charts
- **Values File**: Configuration in `helm/cilium-values.yaml`
- **IRSA Integration**: IAM roles for Cilium operator and agent
- **Multus Compatibility**: Chaining mode with portmap for ROSA
- **Security Group Auto-Config**: Automatic worker security group configuration
- **Status**: ✅ Successfully deployed and operational

#### Automation Scripts
- **Cluster Creation**: `scripts/create-rosa-cluster.sh`
- **CNI Deployment**: `scripts/deploy-cilium.sh`
- **CNI Uninstall**: `scripts/uninstall-cilium.sh`
- **OIDC Management**: `scripts/list-oidc-status.sh`
- **Makefile**: `make` targets for common operations
- **Status**: ✅ All scripts tested and working

#### Configuration Management
- **Helm Values**: Centralized in `helm/cilium-values.yaml`
- **Cluster Overrides**: Cluster-specific settings via `--set` parameters
- **Environment Variables**: Cluster-specific settings in scripts
- **Git Integration**: Comprehensive `.gitignore` for sensitive data protection

### Deployment Status

#### ✅ Successfully Deployed Components
1. **ROSA HCP Cluster**: 3 worker nodes, all Ready status
2. **Cilium CNI**: Version 1.18.2 with ENI mode
3. **IRSA Authentication**: Cilium operator has AWS API access
4. **Multus Integration**: CNI chaining with portmap working
5. **Direct Pod Access**: Pods get ENI IPs (e.g., 10.0.0.70)
6. **Security Groups**: Configured for direct pod access
7. **LoadBalancer Services**: External access via AWS ELB

#### ✅ Verified Functionality
- **Pod Networking**: Pods receive directly routable ENI IPs
- **Service Discovery**: Internal service communication working
- **DNS Resolution**: CoreDNS and service discovery working properly
- **External Access**: LoadBalancer services accessible externally
- **Direct Pod Access**: Pods accessible directly via ENI IPs from VPC
- **Pod-to-Pod Communication**: Direct pod-to-pod connectivity working
- **CNI Health**: All Cilium components healthy and operational
- **eBPF Mode**: Kube-proxy replacement active
- **Hubble**: Network observability enabled
- **Security Groups**: Auto-configured for ENI mode compatibility

#### ✅ Test Results
- **Test Pod**: nginx-unprivileged running on ENI IP 10.0.0.70
- **Internal Access**: HTTP 200 OK responses
- **External Access**: LoadBalancer accessible from internet
- **Direct Access**: Pod accessible directly from VPC resources
- **Security Groups**: Port 8080 access configured

### Project Structure
```
byo-cni-cillium-eni/
├── .cursorrules                 # Development guidelines and rules
├── .gitignore                  # Git ignore patterns for sensitive data
├── design.md                   # This design document
├── README.md                   # Project overview and quick start
├── QUICKSTART.md               # Quick start guide
├── Makefile                    # Automation targets for common operations
├── cluster-creation-progress.env # Progress tracking for cluster creation
├── helm/
│   ├── cilium-values.yaml      # Cilium Helm chart values
│   └── cilium-values.yaml.backup # Backup of previous values
├── manifests/                  # Kubernetes manifests (legacy)
│   ├── cilium-configmap.yaml
│   ├── cilium-daemonset.yaml
│   └── cilium-rbac.yaml
├── scripts/
│   ├── create-rosa-cluster.sh  # ROSA HCP cluster creation with progress tracking
│   ├── deploy-cilium.sh        # Cilium CNI deployment with security group config
│   ├── uninstall-cilium.sh     # Cilium CNI cleanup
│   ├── delete-rosa-cluster.sh  # Cluster deletion script
│   ├── list-oidc-status.sh     # OIDC configuration management
│   ├── README-cilium.md        # Cilium deployment documentation
│   ├── README-delete.md        # Cluster deletion documentation
│   └── README-uninstall.md     # Uninstall documentation
├── terraform-vpc/              # VPC infrastructure (cloned module)
│   ├── main.tf                 # VPC and subnet definitions
│   ├── variables.tf            # Terraform variables
│   ├── outputs.tf              # Terraform outputs
│   ├── terraform.tfvars        # Variable values
│   └── zero-egress/            # Zero-egress VPC variant
├── hacking/                    # Reference files for validation
│   ├── cilium-values-1.18.2.yaml # Official Cilium values reference
│   └── cilium-schema-1.18.2.json # Cilium Helm schema validation
└── tests/                      # Test configurations and validation scripts
```

## Implementation Notes

### Prerequisites
- AWS account with appropriate permissions
- Red Hat OpenShift subscription
- Network access to AWS services
- DNS configuration for cluster access

### Dependencies
- AWS CLI and SDK
- Terraform for VPC infrastructure management
- ROSA CLI for cluster management
- OpenShift CLI (oc) for cluster operations
- Helm for Cilium CNI deployment
- Git for version control

### Constraints and Limitations
- **ENI IP Limits**: Pod IP assignment limited by AWS ENI limits per instance type
- **Security Groups**: External access requires proper security group configuration
- **IRSA Requirements**: Cilium ENI mode requires specific AWS permissions and IRSA configuration
- **Multus Dependency**: Multus CNI integration is required for ROSA compatibility
- **Pod CIDR**: Traditional Pod CIDR not used in ENI mode (`k8s.requireIPv4PodCIDR: false`)
- **Image Registry**: Some container images may require authentication or specific registries
- **LoadBalancer**: External access via LoadBalancer requires security group rules
- **Direct Access**: Pod direct access only works within the same VPC

### Lessons Learned

#### Key Success Factors
1. **Two-Step OIDC**: Creating OIDC config then provider separately is more reliable
2. **IRSA Trust Policy**: Removing `aud` condition from trust policy resolves authentication issues
3. **Multus Integration**: Using `/var/run/multus/cni/net.d` path is critical for ROSA compatibility
4. **Security Groups**: Direct pod access requires explicit security group rules
5. **Helm Values**: Centralized values file with `--set` overrides is more maintainable
6. **Security Group Auto-Config**: Automatic worker security group configuration prevents networking issues
7. **CDI Component Health**: Restarting CDI components resolves TLS handshake errors

#### Common Issues and Solutions
- **Pod CIDR Error**: Set `k8s.requireIPv4PodCIDR: false` for ENI mode
- **CNI Path Issues**: Use Multus-specific paths for ROSA compatibility
- **IRSA Authentication**: Ensure trust policy matches service account audience
- **Image Pull Failures**: Use authenticated registries or public images
- **External Access**: Configure security groups for LoadBalancer services
- **DNS Resolution Issues**: Ensure security groups allow pod-to-pod communication
- **TLS Handshake Errors**: Restart CDI components if networking issues persist
- **PVC Provisioning Failures**: Check EBS CSI driver and CDI component health

#### Operational Insights
- **Direct Pod Access**: Pods are accessible directly via ENI IPs from VPC resources
- **LoadBalancer Services**: Work normally but require security group configuration
- **Network Policies**: Cilium NetworkPolicy works alongside ENI mode
- **Monitoring**: Hubble provides excellent network observability
- **Performance**: eBPF-based networking provides excellent performance

## Future Considerations

### Scalability
- Horizontal pod autoscaling
- Cluster autoscaling for worker nodes
- Network capacity planning
- Performance optimization

### Integration
- Service mesh implementation
- CI/CD pipeline integration
- Monitoring and alerting systems
- Backup and disaster recovery automation

### Maintenance
- Regular security updates
- Performance tuning
- Capacity planning
- Documentation updates

---

**Note**: This design document should be consulted before making any architectural decisions or significant changes. All modifications to this design must be approved and documented.
