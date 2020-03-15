provider "aws" {
  region = var.region
}


###########################
# VPC
###########################

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 2.0"

  name = var.vpc_name

  cidr = "10.0.0.0/16"

  azs = ["${var.region}a", "${var.region}b", "${var.region}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  # redshift_subnets = ["10.0.41.0/24", "10.0.42.0/24", "10.0.43.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support = true

  # enable_s3_endpoint = true

  tags = {
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
  }

  public_subnet_tags = {
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb" = "1"
  }
}


###########################
# ROUTING
###########################

resource "aws_route53_zone" "internal" {
  name = var.internal_domain

  vpc {
    vpc_id = module.vpc.vpc_id
  }
}

resource "aws_iam_server_certificate" "internal_cert" {
  name_prefix = "mobe_ds"
  certificate_body = file("cert/mobe-ds-internal-cert.crt")
  private_key = file("cert/mobe-ds-internal-cert.key")

  lifecycle {
    create_before_destroy = true
  }
}


###########################
# KUBERNETES
###########################

data "aws_eks_cluster" "cluster" {
  name =  module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

provider "kubernetes" {
  host = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token = data.aws_eks_cluster_auth.cluster.token
  load_config_file = false
  version = "~> 1.10"
}

module "eks" {
  source = "terraform-aws-modules/eks/aws"
  cluster_name = var.eks_cluster_name
  cluster_version = "1.14"

  subnets = module.vpc.private_subnets
  vpc_id = module.vpc.vpc_id

  manage_aws_auth = false
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access = false

  worker_groups = [
    {
      name = "workers"
      subnets = [module.vpc.private_subnets.0]
      instance_type = "t2.medium"
      asg_min_size = 2
	  asg_desired_capacity = 2
      asg_max_size = 5
      autoscaling_enabled = true
      protect_from_scale_in = true
    }
  ]
}


###########################
# EFS FILESYSTEM
###########################

resource "aws_efs_file_system" "cluster_pv" {
  creation_token = "cluster-pv"
}

module "cluster_pv_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 3.0"

  name = "${var.eks_cluster_name}-pv-sg"
  vpc_id = module.vpc.vpc_id

  ingress_with_source_security_group_id = [
    {
	  description = "Allow EKS workers to mount EFS filesystem"
	  protocol = "tcp"
      from_port = 2049
      to_port = 2049
      source_security_group_id = module.eks.worker_security_group_id
    },
    {
	  description = "Allow bastion host to mount EFS filesystem"
	  protocol = "tcp"
      from_port = 2049
      to_port = 2049
      source_security_group_id = module.bastion_sg.this_security_group_id
    }	
  ]
}

resource "aws_efs_mount_target" "cluster_pv_mount" {
  file_system_id = aws_efs_file_system.cluster_pv.id
  subnet_id = module.vpc.private_subnets.0
  security_groups = [module.cluster_pv_sg.this_security_group_id]
}

resource "aws_iam_policy" "efs_provisioner_policy" {
  name = "EFSProvisionerIAMPolicy"
  description = "IAM Policy for EFS Provisioner"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "elasticfilesystem:DescribeFileSystems"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "efs_provisioner_policy_attach" {
  role = module.eks.worker_iam_role_name
  policy_arn = aws_iam_policy.efs_provisioner_policy.arn
}


###########################
# BASTION HOST
###########################

module "bastion_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 3.0"

  name   = "${var.bastion_name}-sg"
  vpc_id = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port = 21
      to_port = 22
      protocol = "tcp"
      description = "SSH + FTP ports"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      from_port = 0
      to_port = 65535
      protocol = "all"
      description = "All ports within VPC"
      cidr_blocks = module.vpc.vpc_cidr_block
    }
  ]
  egress_rules = ["all-all"]
}

resource "aws_key_pair" "bastion_key" {
  key_name        = "bastion-key-pair"
  public_key      = var.bastion_key
}

module "bastion" {
  source = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 2.0"

  name = var.bastion_name
  ami = "ami-04b9e92b5572fa0d1" # Ubuntu 18.04 LTS x86_64
  instance_type = "t2.micro"

  key_name = concat(aws_key_pair.bastion_key.*.key_name, [""])[0]

  vpc_security_group_ids = [module.bastion_sg.this_security_group_id]
  subnet_id = module.vpc.public_subnets.0

  associate_public_ip_address = true
}

resource "aws_security_group_rule" "bastion_eks_api" {
  description = "Allow bastion to communicate with the EKS cluster API"
  protocol = "tcp"
  security_group_id = module.eks.cluster_security_group_id
  source_security_group_id = module.bastion_sg.this_security_group_id
  from_port = 443
  to_port = 443
  type = "ingress"
}

resource "aws_volume_attachment" "bastion_ebs_attach" {
  device_name = "/dev/sdh"
  volume_id = aws_ebs_volume.bastion_ebs.id
  instance_id = module.bastion.id[0]
}

resource "aws_ebs_volume" "bastion_ebs" {
  availability_zone = module.bastion.availability_zone[0]
  size = 250
}

resource "aws_route53_record" "bastion" {
  zone_id = aws_route53_zone.internal.zone_id
  name = "bastion"
  type = "CNAME"
  ttl = "60"
  records = module.bastion.private_dns
}
