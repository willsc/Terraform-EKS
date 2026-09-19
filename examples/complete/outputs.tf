output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = module.eks.cluster_endpoint
}

output "vpc_id" {
  description = "Dedicated VPC ID."
  value       = module.eks.vpc_id
}

output "configure_kubectl" {
  description = "Run with credentials for a configured cluster administrator."
  value       = module.eks.configure_kubectl
}
