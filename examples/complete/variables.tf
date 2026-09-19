variable "aws_region" {
  description = "AWS region with at least three standard availability zones."
  type        = string
  default     = "eu-west-2"
}

variable "cluster_name" {
  description = "Name for this EKS cluster."
  type        = string
  default     = "three-node-eks"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes minor version."
  type        = string
  default     = "1.36"
}

variable "cluster_admin_principal_arns" {
  description = "Existing IAM roles or users that will administer Kubernetes."
  type        = set(string)
}

variable "node_subnet_type" {
  description = "Worker placement: private or public."
  type        = string
  default     = "private"
}

variable "endpoint_public_access" {
  description = "Enable public API access restricted to endpoint_public_access_cidrs."
  type        = bool
  default     = false
}

variable "endpoint_public_access_cidrs" {
  description = "Allowed public client IPv4 CIDRs."
  type        = list(string)
  default     = []
}

variable "endpoint_private_access_cidrs" {
  description = "Allowed private client IPv4 CIDRs; clients need a routed connection to the VPC."
  type        = set(string)
  default     = []
}

variable "single_nat_gateway" {
  description = "Use one NAT gateway instead of three when workers are private."
  type        = bool
  default     = false
}
