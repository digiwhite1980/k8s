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

	Usage: ${0} [-h Help] [-e ETCD] [-a API] [-k Kubelet] [-A All] [-D Destroy]"

		-h 		This help
		-e 		Run ETCD terraform
		-a 		Run Kubernetes API server terraform
		-k 		Run Kubernetes Kubelete terraform
		-A 		Run All terraform 
		-D 		Run destroy terraform 
_EOF_
}

while getopts ":eakhAD" opt; do
	case $opt in
		h)
			usage
			exit 0
			;;
		e)
			ETCD=1
			;;
		a)
			KUBEAPI=1
			;;
		k)
			KUBELET=1
			;;
		D)
			DESTROY=1
			;;
		A)
			ALL=1
			;;
		?)
			usage
			exit 1
			;;
	esac
done

ALL=${ALL:-0}
ETCD=${ETCD:-0}
KUBEAPI=${KUBEAPI:-0}
KUBELET=${KUBELET:-0}
DESTROY=${DESTROY:-0}

CURRENT_FOLDER=$(pwd)
TERRAFORM_STATE=${CURRENT_FOLDER}/terraform_state

binCheck git terraform

[[ ! -x $(basename ${0}) ]] 	&& log 3 "Please execute $(basename ${0}) from local directory (./run.sh)"

git submodule init
[[ $? -ne 0 ]] && log 3 "Failed to initialize submodules"

git submodule update
[[ $? -ne 0 ]] && log 3 "Failed to update submodules"


########################################################################################

if [ ${ETCD} -eq 1 -o ${ALL} -eq 1 ]; then
	[[ ! -d "etcd" ]] 		&& log 3 "Unable to find etcd folder for option -e"
	cd etcd
	log 1 "Executing terraform init"
	terraform init > /dev/null
	terraform apply -state .terraform_state
fi

if [ ${KUBEAPI} -eq 1 -o ${ALL} -eq 1 ]; then
	[[ ! -d "kubeapi" ]] 	&& log 3 "Unable to find kubeapi folder for option -a"
	echo KUBEAPI
fi

if [ ${KUBELET} -eq 1 -o ${ALL} -eq 1 ]; then
	[[ ! -d "kubelet" ]] 	&& log 3 "Unable to find kubelet folder for option -k"
	echo KUBELET
fi





terraform init
[[ $? -ne 0 ]] && log 3 "Failed to initialize terraform"

terraform plan -state .terraform_state > /dev/null 2>&1
[[ $? -ne 0 ]] && log 3 "Failed to plan terraform"

terraform apply -state .terraform_state
