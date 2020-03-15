output "vpc_id" {
  description = "ID of the VPC"
  value = module.vpc.vpc_id
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane."
  value = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ids attached to the cluster control plane."
  value = module.eks.cluster_security_group_id
}

output "kubectl_config" {
  description = "kubectl config as generated by the module"
  value = module.eks.kubeconfig
}

locals {
  config_map_aws_auth = <<CONFIGMAPAWSAUTH

apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: ${module.eks.worker_iam_role_arn}
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
CONFIGMAPAWSAUTH

}

output "config_map_aws_auth" {
  value = local.config_map_aws_auth
}

output "bastion_public_ip" {
  description = "Public IP of Bastion Host"
  value = module.bastion.public_ip
}

output "internal_cert_arn" {
  description = "Internal certificate ARN"
  value = aws_iam_server_certificate.internal_cert.arn
}

output "efs_id" {
  description = "EFS filesystem id"
  value = aws_efs_file_system.cluster_pv.id
}

output "efs_dns" {
  description = "EFS DNS"
  value = aws_efs_file_system.cluster_pv.dns_name
}
