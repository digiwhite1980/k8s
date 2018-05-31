# K8s 100% through Terraform

## History

## Good to know
This repo tries to use branch tagging which match the versions of Kubernetes:
Kubernetes version | repo version
* v1.5.7 | v1.5
* v1.9.7 | v1.9

Within de 05_services folder demo deployments are added for reference. Also included is a default ingress setup which uses the default nginx backend.
If you wish to use this project for further deployment, place all custom kubernetes yaml's in 06_custom/terraform.

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

The following switches are available.
```
./run.sh

	No environment (-E) set

	Usage: ./run.sh -E <environment> -n <CIDR prefix x.x>
			[-h Help] [-i Infra] [-e ETCD] [-a API] [-k Kubelet] [-s Services] [-c Custom] [-A All] [-D Destroy]

		-E		* Environment
		-n		CIDR prefix [x.x] <first 2 digits of ipv4 network> (defaults to 10.0 in variables.tf file)

		-i		Run infra
		-e 	Run ETCD terraform
		-a 	Run Kubernetes API server terraform
		-k 	Run Kubernetes Kubelete terraform
		-s		Run services
		-c		Custom scripts (if made available)
		-A 	Run All terraform
		-D 	Run destroy terraform
		-h 	This help

		* switches are mandatory
```
As described there is one mandatory switch (-E) which is used for the environment. Optionally the (-n) switch can be added to change the cidr_prefix.
the switches (-e -a -k -s -c) represent the different direcories (01 to 06). When executing, terraform will run from the given numbered folder and downwards due to the needed dependencies.

The script will include / downloaded the needed subrepo (https://github.com/digiwhite1980/terraform.git). This repo contains a bunch of terraform modules.

I like to keep things clean. The terraform scripts includes the download of the corresponding, versioned kubectl binary. Therefor we can run the run.sh script in the default
hashicorp/terraform container from you local machine.
```
docker run -ti --name terraform_k8s -v ~{path to rootfolder of git repo}/:/data/github --entrypoint=/bin/sh hashicorp/terraform
cd /data/k8s/
./run.sh
```

## External resources used by repo
Download CNI plugins through git:
```
https://github.com/containernetworking/plugins
```

CoreDNS
```
https://github.com/coredns/deployment
```
