#!/bin/sh
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

		-E			Environment (mandatory)
		-n			CIDR prefix [x.x] <first 2 digits of ipv4 network>

		-i			Run infra
		-e 		Run ETCD terraform
		-a 		Run Kubernetes API server terraform
		-k 		Run Kubernetes Kubelete terraform
		-s			Run services
		-c			Custom scripts (if made available)
		-A 		Run All terraform 
		-D 		Run destroy terraform 
		-h 		This help
_EOF_
	[[ "${1}" != "" ]] && exit 1
}

while getopts ":eiaskhcADE:n:" opt; do
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

CURRENT_FOLDER=$(pwd)
TERRAFORM_STATE=${CURRENT_FOLDER}/terraform_state

binCheck git terraform

[[ ! -x $(basename ${0}) ]] 	&& log 3 "Please execute $(basename ${0}) from local directory (./run.sh)"

git submodule init
[[ $? -ne 0 ]]	 		&& log 3 "Failed to initialize submodules"

git submodule update
[[ $? -ne 0 ]] 			&& log 3 "Failed to update submodules"

[[ "${CIDR_PREFIX}" == "" ]] 	&& usage "No CIDR prefix (-n) set"
[[ "${ENVIRONMENT}" == "" ]] 	&& usage "No environment (-E) set"
[[ ${EXEC} -ne 1 ]] 		&& usage "No action selected"

########################################################################################

if [ ${INFRA} -eq 1 -a ${ALL} -ne 1 ]; then
	[[ ! -d "01_infra" ]] && log 3 "Unable to find infra folder for option -i"
	cd 01_infra/terraform	
	log 1 "Executing terraform init on infra"
	terraform init > /dev/null
	terraform apply -var env=${ENVIRONMENT} -var cidr_prefix=${CIDR_PREFIX}
	cd -
fi


if [ ${ETCD} -eq 1 -a ${ALL} -ne 1 ]; then
	[[ ! -d "02_etcd" ]] && log 3 "Unable to find etcd folder for option -e"
	cd 02_etcd/terraform
	log 1 "Executing terraform init etcd"
	terraform init > /dev/null
	terraform apply -var env=${ENVIRONMENT} -var cidr_prefix=${CIDR_PREFIX}
	cd -
fi

if [ ${KUBEAPI} -eq 1 -a ${ALL} -ne 1 ]; then
	[[ ! -d "03_kubeapi" ]] && log 3 "Unable to find kubeapi folder for option -a"
	cd 03_kubeapi/terraform
	log 1 "Executing terraform init kubeapi"
	terraform init > /dev/null
	terraform apply -var env=${ENVIRONMENT} -var cidr_prefix=${CIDR_PREFIX}
	cd -
fi

if [ ${KUBELET} -eq 1 -a ${ALL} -ne 1 ]; then
	[[ ! -d "04_kubelet" ]] && log 3 "Unable to find kubelet folder for option -k"
	cd 04_kubelet/terraform
	log 1 "Executing terraform init kubelet"
	terraform init > /dev/null
	terraform apply -var env=${ENVIRONMENT} -var cidr_prefix=${CIDR_PREFIX}
	cd -
fi

if [ ${SERVICES} -eq 1 -a ${ALL} -ne 1 ]; then
	[[ ! -d "05_services" ]] && log 3 "Unable to find services folder for option -s"
	cd 05_services/terraform
	log 1 "Executing terraform init services"
	terraform init > /dev/null
	terraform apply -var env=${ENVIRONMENT} -var cidr_prefix=${CIDR_PREFIX}
	cd -
fi

if [ ${CUSTOM} -eq 1 -o ${ALL} -eq 1 ]; then
	[[ ! -d "06_custom" ]] && log 3 "Unable to find custom folder for option -s"
	cd 06_custom/terraform
	log 1 "Executing terraform init custom"
	terraform init > /dev/null
	terraform apply -var env=${ENVIRONMENT} -var cidr_prefix=${CIDR_PREFIX}
	cd -
fi

if [ ${DESTROY} -eq 1 ]; then
	[[ ! -d "01_infra" ]] && log 3 "Unable to find custom folder for option -D"
	cd 01_infra/terraform
	log 1 "Executing terraform destroy"
	terraform destroy -var env=${ENVIRONMENT} -var cidr_prefix=${CIDR_PREFIX}
fi
