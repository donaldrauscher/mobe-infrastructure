variable "region" {
  default = "us-east-1"
}

variable "vpc_name" {
  default = "ds-vpc"
}

variable "eks_cluster_name" {
  default = "ds-cluster"
}

variable "bastion_name" {
  default = "ds-bastion"
}

variable "bastion_key" {
}

variable "internal_domain" {
  default = "docker.mobecloud.net"
}
