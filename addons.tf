locals {
  addon_names = toset(["vpc-cni", "kube-proxy", "coredns"])
  addon_versions = {
    for name in local.addon_names : name => coalesce(
      lookup(var.addon_versions, name, null),
      try(data.aws_eks_addon_version.default[name].version, null)
    )
  }
}

data "aws_eks_addon_version" "default" {
  for_each = setsubtract(local.addon_names, toset(keys(var.addon_versions)))

  addon_name         = each.value
  kubernetes_version = var.kubernetes_version
  most_recent        = false
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  addon_version               = local.addon_versions["vpc-cni"]
  service_account_role_arn    = aws_iam_role.vpc_cni.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  tags                        = local.tags

  depends_on = [aws_iam_role_policy_attachment.vpc_cni]
}

resource "aws_eks_addon" "after_nodes" {
  for_each = toset(["kube-proxy", "coredns"])

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.value
  addon_version               = local.addon_versions[each.value]
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  tags                        = local.tags

  depends_on = [aws_eks_node_group.this]
}
