variable "cluster_name" {
  description = "Name prefix for the EKS cluster and its resources."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,39}$", var.cluster_name))
    error_message = "cluster_name must be 1-40 characters, begin with a letter or digit, and contain only letters, digits, underscores, or hyphens."
  }
}

variable "kubernetes_version" {
  description = "EKS Kubernetes minor version. Verify regional availability before applying."
  type        = string
  default     = "1.36"
  nullable    = false

  validation {
    condition     = can(regex("^1\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must be a minor version such as 1.36."
  }
}

variable "cluster_admin_principal_arns" {
  description = "Existing IAM role or user ARNs granted cluster administrator access; use IAM ARNs, not STS session ARNs."
  type        = set(string)
  nullable    = false

  validation {
    condition = length(var.cluster_admin_principal_arns) > 0 && alltrue([
      for arn in var.cluster_admin_principal_arns : can(regex("^arn:aws(-[a-z]+)*:iam::[0-9]{12}:(role|user)/.+$", arn))
    ])
    error_message = "Provide at least one valid IAM role or user ARN for cluster administration."
  }
}

variable "vpc_cidr" {
  description = "IPv4 CIDR for a new dedicated VPC, between /16 and /20. Six subnets are derived automatically."
  type        = string
  default     = "10.0.0.0/16"
  nullable    = false

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && can(regex("/(16|17|18|19|20)$", var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR with a prefix length from /16 to /20."
  }
}

variable "availability_zones" {
  description = "Exactly three distinct standard availability zones in the provider region, or an empty list to discover the first three. Keep the order stable."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition = length(var.availability_zones) == 0 || (
      length(var.availability_zones) == 3 && length(distinct(var.availability_zones)) == 3
    )
    error_message = "availability_zones must be empty or contain exactly three distinct zones."
  }
}

variable "single_nat_gateway" {
  description = "For private workers, share one NAT gateway to reduce cost at the expense of availability and cross-AZ traffic. Ignored for public workers."
  type        = bool
  default     = false
  nullable    = false
}

variable "node_subnet_type" {
  description = "Place the three workers in private subnets with NAT egress, or public subnets with public IPv4 addresses and internet gateway egress."
  type        = string
  default     = "private"
  nullable    = false

  validation {
    condition     = contains(["private", "public"], var.node_subnet_type)
    error_message = "node_subnet_type must be private or public."
  }
}

variable "node_instance_type" {
  description = "An x86_64 EC2 instance type compatible with the AL2023 EKS AMI."
  type        = string
  default     = "t3.medium"
  nullable    = false
}

variable "node_disk_size" {
  description = "Encrypted gp3 root disk size per worker in GiB."
  type        = number
  default     = 30
  nullable    = false

  validation {
    condition     = var.node_disk_size >= 20 && var.node_disk_size <= 16384 && floor(var.node_disk_size) == var.node_disk_size
    error_message = "node_disk_size must be a whole number from 20 to 16384 GiB."
  }
}

variable "node_ami_release_version" {
  description = "Optional EKS AL2023 AMI release version to pin. Null lets EKS select the release on node group creation/version updates."
  type        = string
  default     = null
}

variable "endpoint_public_access" {
  description = "Enable the public Kubernetes API endpoint in addition to the always-enabled private endpoint."
  type        = bool
  default     = false
  nullable    = false
}

variable "endpoint_public_access_cidrs" {
  description = "IPv4 CIDRs permitted to reach the public API. Required when public access is enabled; unrestricted /0 access is rejected."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for cidr in var.endpoint_public_access_cidrs : can(cidrnetmask(cidr)) && !can(regex("/0$", cidr))
    ])
    error_message = "Public endpoint allowlists must contain valid IPv4 CIDRs narrower than /0."
  }
}

variable "endpoint_private_access_cidrs" {
  description = "Optional IPv4 CIDRs allowed HTTPS access through the cluster security group, for VPN or connected management networks. Routing must be configured separately."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for cidr in var.endpoint_private_access_cidrs : can(cidrnetmask(cidr)) && !can(regex("/0$", cidr))
    ])
    error_message = "Private API access must use valid IPv4 CIDRs narrower than /0."
  }
}

variable "addon_versions" {
  description = "Optional pinned versions for vpc-cni, kube-proxy, and coredns. Unspecified versions use the AWS default compatible with the cluster version."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition = alltrue([
      for name, version in var.addon_versions : contains(["vpc-cni", "kube-proxy", "coredns"], name) && can(regex("^v[0-9].+-eksbuild\\.[0-9]+$", version))
    ])
    error_message = "Only vpc-cni, kube-proxy, and coredns are supported; versions must be EKS build versions such as v1.20.4-eksbuild.1."
  }
}

variable "log_retention_days" {
  description = "CloudWatch retention for all five EKS control plane log types."
  type        = number
  default     = 30
  nullable    = false

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a supported finite CloudWatch Logs retention period."
  }
}

variable "tags" {
  description = "Additional tags applied to resources. Module ownership and subnet discovery tags take precedence."
  type        = map(string)
  default     = {}
  nullable    = false
}
