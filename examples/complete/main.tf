terraform {
  required_version = ">= 1.7.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0, < 7.0.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "eks" {
  source = "../.."

  cluster_name                  = var.cluster_name
  kubernetes_version            = var.kubernetes_version
  cluster_admin_principal_arns  = var.cluster_admin_principal_arns
  node_subnet_type              = var.node_subnet_type
  endpoint_public_access        = var.endpoint_public_access
  endpoint_public_access_cidrs  = var.endpoint_public_access_cidrs
  endpoint_private_access_cidrs = var.endpoint_private_access_cidrs
  single_nat_gateway            = var.single_nat_gateway

  tags = {
    Environment = "development"
    Project     = "three-node-eks"
  }
}
