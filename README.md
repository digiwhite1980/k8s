# K8s 100% through Terraform

## History

## Good to know
This repo tries to use branch tagging which match the versions of Kubernetes:
Kubernetes version | repo version
* v1.5.7 | v1.5
* v1.9.7 | v1.9

At the moment of writing all infrastructure is provisioned within the eu-west-1 region. 

## Preparing
We first need to clone the repo.
```
cd /data/github
git clone https://github.com/digiwhite1980/k8s.git
```
After cloning, the shared/aws_credentials.tf needs to be created. Copy the example file from the directory and provide the key and secret credentials.
```
cd shared/
cp -p aws_credentials.tf.example aws_credentials.tf
```

## Running
To make things easy a run.sh script is made available which allows the deployment of your kubernetes environment in stages.
The repo contains numbered folders starting at 01 and ends with 06.

All terraform and kubectl command are done through the default hashicorp/terraform docker container.

```
docker run -ti --name terraform_k8s -v ~{path to rootfolder of git repo}/:/data/github --entrypoint=/bin/sh hashicorp/terraform
cd /data/k8s/01_infra/terraform
terraform init --upgrade
```

## 
Download CNI plugins through git:
https://github.com/containernetworking/plugins

CoreDNS
https://github.com/coredns/deployment
