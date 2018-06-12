#!/bin/sh
# vim: set ts=3
########################################################################

function log {
	case "${1}" in
		1)
			echo "$(date +%Y-%m-%d' '%H:%M:%S)] | OK      : ${2}"
			;;
		2)
			echo "$(date +%Y-%m-%d' '%H:%M:%S)] | WARN    : ${2}"
			;;
		3)
			echo "$(date +%Y-%m-%d' '%H:%M:%S)] | ERROR   : ${2}"
			exit 1
			;;
		*)
			echo "$(date +%Y-%m-%d' '%H:%M:%S)] | UNKNOWN : ${2}"
			;;
	esac
}

function binCheck {
	for bin in ${@}
	do
		BIN_PATH=$(which ${bin})
		[[ ! -x "${BIN_PATH}" ]] && log 3 "binCheck: ${bin} not found in local PATH"
	done
}

function usage {
cat <<_EOF_

  $1

  Usage: ${0} -E <environment> -n <CIDR prefix x.x>
              [-h Help] [-i Infra] [-e ETCD] [-a API] [-k Kubelet] [-s Services] [-c Custom] [-A All] [-D Destroy]

  -E   * Environment 
  -n   CIDR prefix [x.x] <first 2 digits of ipv4 network> (defaults to 10.0 in variables.tf file)
  
  -i   Run infra
  -e   Run ETCD terraform
  -a   Run Kubernetes API server terraform
  -k   Run Kubernetes Kubelete terraform
  -s   Run services
  -c   Custom scripts (if made available)
  -A   Run All terraform 
  -D   Run destroy terraform 
  -h   This help

  -o   Show terraform output

   *   switches are mandatory
_EOF_
	[[ "${1}" != "" ]] && exit 1
}


while getopts ":eiaskhcADoE:n:" opt; do
	case $opt in
		h)
			usage
			exit 0
			;;
		i)
			INFRA=1
			EXEC=1
			;;
		e)
			ETCD=1
			EXEC=1
			;;
		a)
			KUBEAPI=1
			EXEC=1
			;;
		k)
			KUBELET=1
			EXEC=1
			;;
		s)
			SERVICES=1
			EXEC=1
			;;
		c)
			CUSTOM=1
			EXEC=1
			;;
		D)
			DESTROY=1
			EXEC=1
			;;
		A)
			ALL=1
			EXEC=1
			;;
		E)
			ENVIRONMENT=${OPTARG}
			;;
		n)
			CIDR_PREFIX=${OPTARG}
			;;
		o)
			OUTPUT=1
			EXEC=1
			;;
		?)
			usage
			exit 1
			;;
	esac
done

EXEC=${EXEC:-0}
ALL=${ALL:-0}
INFRA=${INFRA:-0}
ETCD=${ETCD:-0}
KUBEAPI=${KUBEAPI:-0}
KUBELET=${KUBELET:-0}
SERVICES=${SERVICES:-0}
CUSTOM=${CUSTOM:-0}
DESTROY=${DESTROY:-0}
OUTPUT=${OUTPUT:-0}

CURRENT_FOLDER=$(pwd)
TERRAFORM_STATE=${CURRENT_FOLDER}/terraform_state

binCheck git terraform

[[ ! -x $(basename ${0}) ]] 	&& log 3 "Please execute $(basename ${0}) from local directory (./run.sh)"
[[ ! -f terraform_modules/.git ]] && rm -fr terraform_modules > /dev/null 2>&1

git submodule add --force  https://github.com/digiwhite1980/terraform.git terraform_modules
[[ $? -ne 0 ]]	 					&& log 3 "Failed to initialize submodules"

[[ "${CIDR_PREFIX}" != "" ]] 	&& CIDR_ADDON="-var cidr_vpc_prefix=${CIDR_PREFIX}"
[[ "${ENVIRONMENT}" == "" ]] 	&& usage "No environment (-E) set"
[[ ${EXEC} -ne 1 ]] 				&& usage "No action selected"

########################################################################################

if [ ! -f config/aws_key ]; then
	cd 01_infra/terraform
	log 1 "AWS SSH Keys not found. Creating"
	terraform init > /dev/null
	terraform apply -var env=${ENVIRONMENT} ${CIDR_ADDON} --target=null_resource.ssh-key
	cd -
fi

if [ ${INFRA} -eq 1 -a ${ALL} -ne 1 ]; then
	[[ ! -d "01_infra" ]] && log 3 "Unable to find infra folder for option -i"
	cd 01_infra/terraform	
	log 1 "Executing terraform init on infra"
	terraform init > /dev/null
	terraform apply -var env=${ENVIRONMENT} ${CIDR_ADDON}
	cd -
fi

if [ ${ETCD} -eq 1 -a ${ALL} -ne 1 ]; then
	[[ ! -d "02_etcd" ]] && log 3 "Unable to find etcd folder for option -e"
	cd 02_etcd/terraform
	log 1 "Executing terraform init etcd"
	terraform init > /dev/null
	terraform apply -var env=${ENVIRONMENT} ${CIDR_ADDON}
	cd -
fi

if [ ${KUBEAPI} -eq 1 -a ${ALL} -ne 1 ]; then
	[[ ! -d "03_kubeapi" ]] && log 3 "Unable to find kubeapi folder for option -a"
	cd 03_kubeapi/terraform
	log 1 "Executing terraform init kubeapi"
	terraform init > /dev/null
	terraform apply -var env=${ENVIRONMENT} ${CIDR_ADDON}
	cd -
fi

if [ ${KUBELET} -eq 1 -a ${ALL} -ne 1 ]; then
	[[ ! -d "04_kubelet" ]] && log 3 "Unable to find kubelet folder for option -k"
	cd 04_kubelet/terraform
	log 1 "Executing terraform init kubelet"
	terraform init > /dev/null
	terraform apply -var env=${ENVIRONMENT} ${CIDR_ADDON}
	cd -
fi

if [ ${SERVICES} -eq 1 -a ${ALL} -ne 1 ]; then
	[[ ! -d "05_services" ]] && log 3 "Unable to find services folder for option -s"
	cd 05_services/terraform
	log 1 "Executing terraform init services"
	terraform init > /dev/null
	terraform apply -var env=${ENVIRONMENT} ${CIDR_ADDON}
	cd -
fi

if [ ${CUSTOM} -eq 1 -o ${ALL} -eq 1 ]; then
	[[ ! -d "06_custom" ]] && log 3 "Unable to find custom folder for option -s"
	cd 06_custom/terraform
	log 1 "Executing terraform init custom"
	terraform init > /dev/null
	terraform apply -var env=${ENVIRONMENT} ${CIDR_ADDON}
	cd -
fi

if [ ${DESTROY} -eq 1 ]; then
	[[ ! -d "01_infra" ]] && log 3 "Unable to find custom folder for option -D"

	log 1 "Deleting kubernetes yaml's with dependencies"

	[[ -f "deploy/k8s/03_influxdb.yaml" ]] 			&& kubectl --kubeconfig config/kubeconfig delete -f deploy/k8s/03_influxdb.yaml > /dev/null 2>&1
	[[ -f "deploy/k8s/06_ingress_backend.yaml" ]] 	&& kubectl --kubeconfig config/kubeconfig delete -f deploy/k8s/06_ingress_backend.yaml > /dev/null 2>&1
	[[ -f "deploy/k8s/07_pvc.yaml" ]] 					&& kubectl --kubeconfig config/kubeconfig delete -f deploy/k8s/07_pvc.yaml > /dev/null 2>&1
	[[ -f "deploy/k8s/08_efs.yaml" ]] 					&& kubectl --kubeconfig config/kubeconfig delete -f deploy/k8s/08_efs.yaml > /dev/null 2>&1

	cd 01_infra/terraform
	log 1 "Executing terraform destroy"

	terraform destroy -var env=${ENVIRONMENT} ${CIDR_ADDON}
fi

if [ ${OUTPUT} -eq 1 ]; then
	[[ ! -d "01_infra" ]] && log 3 "Unable to find custom folder for option -D"

	log 1 "Terraform output"

	cd 01_infra/terraform
	terraform output
fi
