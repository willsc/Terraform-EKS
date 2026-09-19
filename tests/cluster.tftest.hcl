# AWS reads and resources are mocked; no cloud resources are created.
mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }
  mock_data "aws_region" {
    defaults = { region = "eu-west-2" }
  }
  mock_data "aws_availability_zones" {
    defaults = { names = ["eu-west-2c", "eu-west-2a", "eu-west-2b"] }
  }
  mock_data "aws_eks_addon_version" {
    defaults = { version = "v1.0.0-eksbuild.1" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/mock-eks-role" }
  }
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.eu-west-2.amazonaws.com/id/EXAMPLE" }
  }
  mock_resource "aws_launch_template" {
    defaults = {
      id             = "lt-0123456789abcdef0"
      latest_version = 1
    }
  }
  mock_resource "aws_eks_cluster" {
    defaults = {
      arn                   = "arn:aws:eks:eu-west-2:123456789012:cluster/test-eks"
      endpoint              = "https://example.eks.amazonaws.com"
      identity              = [{ oidc = [{ issuer = "https://oidc.eks.eu-west-2.amazonaws.com/id/EXAMPLE" }] }]
      certificate_authority = [{ data = "bW9jay1jZXJ0aWZpY2F0ZQ==" }]
    }
  }
}

variables {
  cluster_name                 = "test-eks"
  cluster_admin_principal_arns = ["arn:aws:iam::123456789012:role/EKSAdministrator"]
}

run "private_cluster" {
  command = apply

  assert {
    condition = (
      aws_eks_node_group.this.scaling_config[0].desired_size == 3 &&
      aws_eks_node_group.this.scaling_config[0].min_size == 3 &&
      aws_eks_node_group.this.scaling_config[0].max_size == 3 &&
      toset(aws_eks_node_group.this.subnet_ids) == toset(values(aws_subnet.private)[*].id)
    )
    error_message = "Private mode must maintain three workers in private subnets."
  }
  assert {
    condition = (
      length(aws_nat_gateway.this) == 3 &&
      length(aws_subnet.private) == 3 && length(aws_subnet.public) == 3 &&
      length(toset(concat(values(aws_subnet.private)[*].cidr_block, values(aws_subnet.public)[*].cidr_block))) == 6 &&
      alltrue([for key, route in aws_route.private_internet : route.nat_gateway_id == aws_nat_gateway.this[key].id]) &&
      alltrue([for key, gateway in aws_nat_gateway.this : gateway.subnet_id == aws_subnet.public[key].id])
    )
    error_message = "Private subnets must use same-AZ NAT gateways and distinct subnet CIDRs."
  }
  assert {
    condition = (
      aws_eks_cluster.this.vpc_config[0].endpoint_private_access &&
      !aws_eks_cluster.this.vpc_config[0].endpoint_public_access &&
      alltrue([for subnet in aws_subnet.private : !subnet.map_public_ip_on_launch]) &&
      one(aws_launch_template.nodes.block_device_mappings).ebs[0].encrypted &&
      aws_launch_template.nodes.metadata_options[0].http_tokens == "required"
    )
    error_message = "Defaults must keep the API/workers private, encrypt disks, and require IMDSv2."
  }
  assert {
    condition = (
      !contains(keys(aws_iam_role_policy_attachment.nodes), "AmazonEKS_CNI_Policy") &&
      aws_eks_cluster.this.access_config[0].authentication_mode == "API" &&
      !aws_eks_cluster.this.access_config[0].bootstrap_cluster_creator_admin_permissions &&
      length(aws_eks_access_policy_association.admin) == 1 &&
      jsondecode(aws_iam_role.vpc_cni.assume_role_policy).Statement[0].Condition.StringEquals["${local.oidc_issuer}:sub"] == "system:serviceaccount:kube-system:aws-node"
    )
    error_message = "Admin access must be explicit and CNI permissions restricted to its service account."
  }
}

run "public_api_with_private_workers" {
  command = apply
  variables {
    endpoint_public_access       = true
    endpoint_public_access_cidrs = ["203.0.113.10/32"]
  }
  assert {
    condition = (
      aws_eks_cluster.this.vpc_config[0].endpoint_public_access &&
      aws_eks_cluster.this.vpc_config[0].endpoint_private_access &&
      toset(aws_eks_cluster.this.vpc_config[0].public_access_cidrs) == toset(["203.0.113.10/32"]) &&
      toset(aws_eks_node_group.this.subnet_ids) == toset(values(aws_subnet.private)[*].id)
    )
    error_message = "Public API access must preserve private worker connectivity and the client allowlist."
  }
}

run "public_workers" {
  command = apply
  variables {
    node_subnet_type             = "public"
    endpoint_public_access       = true
    endpoint_public_access_cidrs = ["203.0.113.10/32"]
  }
  assert {
    condition = (
      length(aws_nat_gateway.this) == 0 && length(aws_eip.nat) == 0 &&
      length(aws_route.private_internet) == 0 &&
      alltrue([for subnet in aws_subnet.public : subnet.map_public_ip_on_launch]) &&
      toset(aws_eks_node_group.this.subnet_ids) == toset(values(aws_subnet.public)[*].id) &&
      aws_route.public_internet.gateway_id == aws_internet_gateway.this.id
    )
    error_message = "Public workers must use public addresses and internet gateway egress without NAT gateways."
  }
}

run "shared_nat" {
  command = apply
  variables {
    single_nat_gateway = true
  }
  assert {
    condition = (
      length(aws_nat_gateway.this) == 1 &&
      alltrue([for route in aws_route.private_internet : route.nat_gateway_id == aws_nat_gateway.this["0"].id])
    )
    error_message = "Shared NAT mode must route all three private subnets through one gateway."
  }
}

run "explicit_configuration" {
  command = apply
  variables {
    cluster_name                  = "eks-123456789012345678901234567890123456"
    availability_zones            = ["eu-west-2c", "eu-west-2b", "eu-west-2a"]
    vpc_cidr                      = "172.16.0.0/20"
    endpoint_private_access_cidrs = ["172.16.0.0/20"]
    cluster_admin_principal_arns  = ["arn:aws:iam::123456789012:role/AdminOne", "arn:aws:iam::123456789012:user/AdminTwo"]
    addon_versions                = { vpc-cni = "v1.20.4-eksbuild.1" }
  }
  assert {
    condition = (
      output.availability_zones == tolist(["eu-west-2c", "eu-west-2b", "eu-west-2a"]) &&
      length(aws_eks_access_policy_association.admin) == 2 &&
      length(aws_vpc_security_group_ingress_rule.private_api) == 1 &&
      aws_eks_addon.vpc_cni.addon_version == "v1.20.4-eksbuild.1" &&
      !contains(keys(data.aws_eks_addon_version.default), "vpc-cni")
    )
    error_message = "Explicit AZ order, admin mappings, private API access, and pinned add-ons must be honored."
  }
}

run "reject_public_api_without_allowlist" {
  command = plan
  variables {
    endpoint_public_access = true
  }
  expect_failures = [aws_eks_cluster.this]
}

run "reject_unrestricted_public_api" {
  command = plan
  variables {
    endpoint_public_access_cidrs = ["0.0.0.0/0"]
  }
  expect_failures = [var.endpoint_public_access_cidrs]
}

run "reject_missing_administrator" {
  command = plan
  variables {
    cluster_admin_principal_arns = []
  }
  expect_failures = [var.cluster_admin_principal_arns]
}

run "reject_session_arn" {
  command = plan
  variables {
    cluster_admin_principal_arns = ["arn:aws:sts::123456789012:assumed-role/EKSAdministrator/session"]
  }
  expect_failures = [var.cluster_admin_principal_arns]
}

run "reject_duplicate_zones" {
  command = plan
  variables {
    availability_zones = ["eu-west-2a", "eu-west-2a", "eu-west-2b"]
  }
  expect_failures = [var.availability_zones]
}

run "reject_unavailable_zones" {
  command = plan
  variables {
    availability_zones = ["eu-west-2a", "eu-west-2b", "eu-west-2z"]
  }
  expect_failures = [aws_vpc.this]
}

run "reject_invalid_subnet_type" {
  command = plan
  variables {
    node_subnet_type = "isolated"
  }
  expect_failures = [var.node_subnet_type]
}
