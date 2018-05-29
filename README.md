# K8s 100% through Terraform

## History

## Good to know
This repo tries to use branch tagging which match the versions of Kubernetes:
|Kubernetes|k8s Repo|
|v1.5.7|v1.5|
|v1.9.7|v1.9|

## Preparing
We first need to clone the repo.
```
cd /data/github
git clone https://github.com/digiwhite1980/k8s.git
```

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
