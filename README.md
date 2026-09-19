# Three-node EKS Terraform module

Deploys an AWS-managed EKS control plane and **three EC2 worker nodes** in one managed node group. The three-node count refers to workers; AWS manages the control plane.

Creates a dedicated IPv4 VPC across three availability zones, three public and three private subnets, routing, IAM roles, explicit administrator access, encrypted worker disks, and the VPC CNI, kube-proxy, and CoreDNS managed add-ons. Workers default to Amazon Linux 2023 on `t3.medium`, with 30 GiB gp3 disks. All five control plane log types go to CloudWatch with 30-day retention.

## Public and private modes

API visibility and worker placement are independent:

| Deployment | `node_subnet_type` | `endpoint_public_access` | Client access |
| --- | --- | --- | --- |
| Private (default) | `"private"` | `false` | Connected VPC/VPN network |
| Public API, private workers | `"private"` | `true` | Public CIDR allowlist or connected private network |
| Public workers and API | `"public"` | `true` | Public CIDR allowlist or connected private network |
| Public workers, private API | `"public"` | `false` | Connected VPC/VPN network |

The private API endpoint remains enabled in every mode so workers always reach it inside the VPC. Public API access requires an explicit IPv4 allowlist; `0.0.0.0/0` is rejected. See [AWS endpoint access behavior](https://docs.aws.amazon.com/eks/latest/userguide/cluster-endpoint.html).

Private workers have no public addresses and use one NAT gateway per AZ by default. Set `single_nat_gateway = true` to share a single gateway; this reduces cost but makes egress dependent on one AZ and can incur cross-AZ traffic. Public workers receive public IPv4 addresses and use the internet gateway; no NAT gateways or NAT EIPs are created in that mode. Public addresses do not create inbound SSH or application access rules.

For a private API, arrange routing into the VPC (for example, a VPN or management host) and allow the client's source CIDR with `endpoint_private_access_cidrs`, or attach the cluster security group to the management host. The module does not provision the VPN or management host. Terraform uses AWS APIs and does not itself require access to the private Kubernetes endpoint.

## Deploy the example

Requires Terraform >= 1.7, AWS provider 6.x, AWS CLI v2, and AWS credentials allowed to manage EKS, EC2/VPC, IAM, and CloudWatch Logs, including `iam:PassRole` and service-linked role creation when needed. Install `kubectl` to inspect the cluster. The region/account must expose at least three standard availability zones and have sufficient EC2, EIP, NAT, and EKS quotas.

```bash
cd examples/complete
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set your region, real admin IAM ARN, and access mode.
aws sts get-caller-identity
terraform init
terraform plan -out=tfplan
terraform apply tfplan
terraform output -raw configure_kubectl
```

Run the printed `aws eks update-kubeconfig` command with credentials for a configured administrator, then verify:

```bash
kubectl get nodes -o wide
kubectl get pods -n kube-system
```

The administrator ARN must identify an existing IAM role or user, not an STS `assumed-role` session. The identity applying Terraform is **not automatically a Kubernetes administrator**. Use an AWS profile for an allowed role, or add `--role-arn <allowed-role-arn>` to the kubeconfig command if your current identity can assume that role. That identity also needs AWS permission to call `eks:DescribeCluster` to generate kubeconfig; EKS access policies grant Kubernetes access, not AWS API permissions.

To use the example from a laptop without a VPN, set:

```hcl
node_subnet_type              = "private" # Or "public" for public workers.
endpoint_public_access       = true
endpoint_public_access_cidrs = ["203.0.113.10/32"] # Replace with your public egress IP.
```

The example IP and account ID are documentation placeholders and must be replaced. Credentials come from the standard AWS credential chain; do not put access keys in Terraform files.

## Use as a module

The repository root is the reusable module. Configure the AWS provider in the calling project:

```hcl
provider "aws" {
  region = "eu-west-2"
}

module "eks" {
  source = "./Terraform-EKS" # Path to a checkout of this repository.

  cluster_name                = "my-eks"
  cluster_admin_principal_arns = ["arn:aws:iam::123456789012:role/EKSAdministrator"]

  node_subnet_type              = "private"
  endpoint_public_access       = true
  endpoint_public_access_cidrs = ["203.0.113.10/32"]

  tags = {
    Environment = "development"
  }
}
```

## Inputs

| Input | Default | Purpose |
| --- | --- | --- |
| `cluster_name` | Required | Resource prefix; 1–40 characters |
| `cluster_admin_principal_arns` | Required | Nonempty set of existing administrator IAM role/user ARNs |
| `kubernetes_version` | `"1.36"` | EKS minor version; verify regional availability |
| `vpc_cidr` | `"10.0.0.0/16"` | New VPC IPv4 CIDR, `/16` through `/20` |
| `availability_zones` | `[]` | Auto-select three sorted AZs, or supply exactly three in a stable order |
| `node_subnet_type` | `"private"` | `"private"` or `"public"` workers |
| `single_nat_gateway` | `false` | One shared NAT instead of three; applies to private workers |
| `node_instance_type` | `"t3.medium"` | Compatible x86_64 EC2 instance type |
| `node_disk_size` | `30` | Encrypted gp3 disk size in GiB |
| `node_ami_release_version` | `null` | Optional AL2023 EKS AMI release pin |
| `endpoint_public_access` | `false` | Enable public API access in addition to the private API |
| `endpoint_public_access_cidrs` | `[]` | Public client IPv4 allowlist; required when public API is enabled |
| `endpoint_private_access_cidrs` | `[]` | Connected management network CIDRs allowed TCP 443 |
| `addon_versions` | `{}` | Optional EKS build version pins for `vpc-cni`, `kube-proxy`, `coredns` |
| `log_retention_days` | `30` | Finite supported CloudWatch retention period |
| `tags` | `{}` | Additional resource tags |

The example also accepts `aws_region`, defaulting to `eu-west-2`. The reusable module inherits its region from the caller's AWS provider.

Outputs include the cluster name, ARN, endpoint, CA certificate, security group, VPC and subnet IDs, selected AZs, NAT public IPs, node group name and IAM role, OIDC provider details, and the `configure_kubectl` command. See [outputs.tf](outputs.tf).

## Operations

- The node group's desired, minimum, and maximum sizes are all three. AWS balances across the AZs, but one worker per AZ is not a strict guarantee. Rolling updates and replacement can temporarily change the running count; updates allow one unavailable node. Application availability also requires replicas, topology constraints, and disruption budgets.
- Disks are encrypted and IMDSv2 is required with a hop limit of one. Applications needing AWS permissions should use dedicated IAM roles for service accounts (IRSA); the module exposes its OIDC provider. VPC CNI has its own IRSA role. See [AWS node IAM guidance](https://docs.aws.amazon.com/eks/latest/userguide/create-node-role.html).
- Version `1.36` was selected from the [EKS version lifecycle documentation](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html). Review support dates and upgrade regularly. Unless pinned, add-ons use AWS's compatible default at plan time, so later plans can propose updates. AMI patch releases are not automatically rolled out; update `node_ami_release_version` to roll a chosen release. Standard EKS extended-support behavior is unchanged.
- Supply explicit `availability_zones` for stable long-lived deployments. Changing their order, VPC CIDR, or worker subnet type can replace subnets or the node group. Review the plan before switching an existing deployment between public and private workers.
- This module creates its own VPC. Load balancer controllers, EBS CSI/storage classes, application ingress, autoscaling, and workloads are separate additions. Subnets are tagged for load balancer discovery, but no application is exposed automatically.
- Applying creates billable resources: the EKS control plane, three instances and disks, NAT gateways in private mode, public IPv4 addresses, logs, and network traffic. Configure a remote state backend with locking in the caller for team use. State, local variable files, and plans are gitignored; provider lock files are tracked in this repository.

To remove the example, first remove Kubernetes workloads that provision AWS resources such as load balancers or volumes, then run `terraform destroy` from `examples/complete`. This deletes the cluster and its managed infrastructure.

## Local verification

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
terraform test
```

Tests use a mocked AWS provider and create no AWS resources. They cover public/private placement, API allowlists, per-AZ and shared NAT routing, IAM configuration, explicit AZ/add-on settings, and invalid inputs. A live AWS apply and `kubectl` checks are still needed to verify deployment in your account.
