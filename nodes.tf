resource "aws_launch_template" "nodes" {
  name_prefix = "${var.cluster_name}-nodes-"
  description = "Encrypted EKS AL2023 workers with IMDSv2"

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.node_disk_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  # Omitting security groups lets EKS attach its cluster security group.
  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "${var.cluster_name}-worker" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.tags
  }

  tags = local.tags
}

resource "aws_eks_node_group" "this" {
  cluster_name           = aws_eks_cluster.this.name
  node_group_name_prefix = "${substr(var.cluster_name, 0, 28)}-workers-"
  node_role_arn          = aws_iam_role.nodes.arn
  subnet_ids             = [for subnet in(var.node_subnet_type == "private" ? aws_subnet.private : aws_subnet.public) : subnet.id]
  version                = aws_eks_cluster.this.version
  release_version        = var.node_ami_release_version
  ami_type               = "AL2023_x86_64_STANDARD"
  capacity_type          = "ON_DEMAND"
  instance_types         = [var.node_instance_type]

  scaling_config {
    desired_size = 3
    min_size     = 3
    max_size     = 3
  }

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  update_config {
    max_unavailable = 1
  }

  tags = local.tags

  # Nodes need functioning CNI permissions and egress before bootstrap.
  # CoreDNS is installed afterwards because it needs nodes to become healthy.
  depends_on = [
    aws_iam_role_policy_attachment.nodes,
    aws_eks_addon.vpc_cni,
    aws_route.private_internet,
    aws_route_table_association.private,
    aws_route.public_internet,
    aws_route_table_association.public,
  ]
}
