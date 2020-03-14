## mobe-infrastructure

Test building a private EKS cluster w/in VPC for DS stuff


### Build Infrastructure

Use the following to create a self-signed cert:
```
openssl req -x509 -nodes -newkey rsa -config openssl.cnf \
  -keyout cert/mobe-ds-internal-cert.key \
  -out cert/mobe-ds-internal-cert.crt \
  -extensions 'v3_req'

openssl x509 -in cert/mobe-ds-internal-cert.crt -noout -text
```

Build infrastructure with Terraform:
```
terraform init
terraform plan -var "bastion_key=$(cat ~/.ssh/id_rsa.pub)"
terraform apply -var "bastion_key=$(cat ~/.ssh/id_rsa.pub)"
terraform output config_map_aws_auth > config_map_aws_auth.yaml
```


### Setup Bastion Host

First, follow [these instructions](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ebs-using-volumes.html) to permanently mount the attached EBS volume.

Upload AWS credentials to bastion:
```
ssh ubuntu@$MOBE_BASTION "mkdir -p ~/.aws" && scp ~/.aws/credentials ubuntu@$MOBE_BASTION:~/.aws/credentials
ssh ubuntu@$MOBE_BASTION "mkdir -p ~/.kube" && scp ./kubeconfig_ds-cluster ubuntu@$MOBE_BASTION:~/.kube/config
scp ./config_map_aws_auth.yaml ubuntu@$MOBE_BASTION:~/config_map_aws_auth.yaml
```

Next, add `aws-iam-authenticator`, and `kubectl` executables to bastion host: 
```
sudo curl -o /usr/local/bin/kubectl https://amazon-eks.s3-us-west-2.amazonaws.com/1.14.6/2019-08-22/bin/linux/amd64/kubectl
sudo curl -o /usr/local/bin/aws-iam-authenticator https://amazon-eks.s3-us-west-2.amazonaws.com/1.14.6/2019-08-22/bin/linux/amd64/aws-iam-authenticator
sudo chmod -R +x /usr/local/bin/
```

Finally, apply AWS auth config (from bastion):
```
kubectl apply -f config_map_aws_auth.yaml
```


### Setup Helm

```
wget https://get.helm.sh/helm-v3.0.1-linux-amd64.tar.gz
tar -zxvf helm-v3.0.1-linux-amd64.tar.gz
sudo mv linux-amd64/helm /usr/local/bin/helm
chmod +x /usr/local/bin/helm
helm repo add stable https://kubernetes-charts.storage.googleapis.com
```

NOTE: Tiller is gone as of Helm 3!  Helm's permissions are not evaluated based on the user's kubeconfig.


### Setup EFS CSI Driver for PV


### Setup Autoscaler


### Setup Nginx Ingress Controller

```
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.30.0/deploy/static/mandatory.yaml
kubectl apply -f k8s/nginx_load_balancer.yaml
```

Sources: 
- [https://kubernetes.github.io/ingress-nginx/deploy/](https://kubernetes.github.io/ingress-nginx/deploy/)
- [https://docs.aws.amazon.com/eks/latest/userguide/load-balancing.html](https://docs.aws.amazon.com/eks/latest/userguide/load-balancing.html)

Lastly, set up Route 53 record which maps wildcard domain to the NLB created by above process.
