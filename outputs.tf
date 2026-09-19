output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "EKS cluster ARN."
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded Kubernetes API CA certificate."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "EKS-managed security group attached to the control plane and workers."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "vpc_id" {
  description = "ID of the dedicated VPC."
  value       = aws_vpc.this.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs in availability zone order."
  value       = [for subnet in aws_subnet.private : subnet.id]
}

output "public_subnet_ids" {
  description = "Public subnet IDs in availability zone order."
  value       = [for subnet in aws_subnet.public : subnet.id]
}

output "availability_zones" {
  description = "The three selected availability zones."
  value       = local.availability_zones
}

output "nat_gateway_public_ips" {
  description = "Outbound IP addresses for private subnet traffic."
  value       = [for address in aws_eip.nat : address.public_ip]
}

output "node_group_name" {
  description = "Managed node group name."
  value       = aws_eks_node_group.this.node_group_name
}

output "node_role_arn" {
  description = "Worker node IAM role ARN."
  value       = aws_iam_role.nodes.arn
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN for additional IAM roles for service accounts (IRSA)."
  value       = aws_iam_openid_connect_provider.this.arn
}

output "oidc_issuer_url" {
  description = "Cluster OIDC issuer URL."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "configure_kubectl" {
  description = "Run with credentials for one of the configured cluster administrators."
  value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${aws_eks_cluster.this.name}"
}
