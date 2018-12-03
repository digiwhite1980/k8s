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

function toggleEnv {
	if [ -f ${1}/terraform/${1}.tf.disabled ]; then
		log 1 "Enable run environment ${1}"
		for file in $(find ${1}/terraform/ -maxdepth 1 -name *.tf.disabled)
		do
			org_file=$(echo ${file} | sed 's/\.disabled//g')
			mv ${file} ${org_file}
		done
	else
		log 1 "Disable run environment ${1}"
		for file in $(find ${1}/terraform/ -maxdepth 1 -name *.tf)
		do
			mv ${file} ${file}.disabled
		done
	fi
}

function createTfstate {

	##################################################################
	# We assume working in the directory where the symbolic link state
	# file needs to be placed
	##################################################################
	if [ ! -L terraform.tfstate ]; then
		rm terraform.tfstate > /dev/null 2>&1
		rm terraform.tfstate.backup > /dev/null 2>&1

		ln -s ../../terraform_state/terraform.tfstate terraform.tfstate
		ln -s ../../terraform_state/terraform.tfstate.backup terraform.tfstate.backup
	fi
}

function usage {
cat <<_EOF_

  $1

  Usage: ${0} -E <environment> [-F domain] [-n <CIDR prefix x.x>] <Options *> 
              [-r AWS Region] [-y] [-R] [-h Help] [-i Infra] [-e ETCD] [-a API] [-k Kubelet] [-s Services] [-c Custom] [-A All] [-D Destroy] [-d Destroy custom services] [-X] [-C] [-x {2..6}]

  Help:
  -h   This help

  General:
  -E   * Environment 
  -F   Domain (default: example.internal)
  -r   {Region | AWS)
  -n   CIDR prefix [x.x] <first 2 digits of ipv4 network> (defaults to 10.0 in variables.tf file)
  -y   auto-approve terraform
  -R   restore kubectl config and kubectl binary
  -f   Overwrite flags with new given flags
  -o   Show terraform output
  
  Options *: 
  -i   (1) Run infra
  -e   (2) Run ETCD terraform
  -a   (3) Run Kubernetes API server terraform
  -k   (4) Run Kubernetes Kubelete terraform
  -s   (5) Run services
  -c   (6) Run services custom (if made availablei: see -C)
  -A   Run All terraform 

  -t   Taint services and apply again (only to use with -s or -c)
  -x   Disable Option ([2,3,4,5,6,s] comma seperated). Disabled Run environment. Can be used when not installing Kubernetes but only create custom environment. 
       The option s shows all disabled services

  Destroy:
  -C   Create custom folder environment voor custom terraform and kubernetes files (06_custom)
  -D   Run destroy terraform 
  -X   [ only with -D ] dont run deletion of custom service scripts
  -d   Run destroy terraform (but only custom services)

   *   switches are mandatory. Running a higher option will invoke all lower options.
_EOF_
	[[ "${1}" != "" ]] && exit 1
}


while getopts ":eiaskfhyRtcCADXdox:r:E:n:l:F:" opt; do
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
		r)
			AWS_REGION=${OPTARG}
			;;
		C)
			CREATE_CUSTOM=1
			EXEC=1
			;;
		D)
			DESTROY=1
			EXEC=1
			;;
		X)
			SKIP_SERVICES=1
			;;
		d)
			DESTROY=1
			DESTROY_SERVICES_ONLY=1
			EXEC=1
			;;
		A)
			ALL=1
			EXEC=1
			;;
		E)
			ENVIRONMENT=${OPTARG}
			;;
		F)
			DOMAINNAME=${OPTARG}
			;;
		n)
			CIDR_PREFIX=${OPTARG}
			;;
		R)
			RESTORE_KUBECTL=1
			EXEC=1
			;;
		t)
			TAINT=1
			;;
		x)
			DISABLE_RUN=${OPTARG}
			EXEC=1
			;;
		f)
			OVERWRITE_FLAGS=1
			;;
		y)
			AUTO="-auto-approve"
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
SKIP_SERVICES=${SKIP_SERVICES:-0}
CUSTOM=${CUSTOM:-0}
DESTROY=${DESTROY:-0}
OUTPUT=${OUTPUT:-0}
TAINT=${TAINT:-0}
RESTORE_KUBECTL=${RESTORE_KUBECTL:-0}
OVERWRITE_FLAGS=${OVERWRITE_FLAGS:-0}
CREATE_CUSTOM=${CREATE_CUSTOM:-0}
CUSTOM_FOLDER="06_custom"

CURRENT_FOLDER=$(pwd)
TERRAFORM_STATE=${CURRENT_FOLDER}/terraform_state
CONFIG_DIR=${CURRENT_FOLDER}/config
CONFIG_FLAGS=${CONFIG_DIR}/run.flags
DEPLOY_DIR=${CURRENT_FOLDER}/deploy
CONFIG_FILE=${CONFIG_DIR}/run.conf

##################################################################################################################
# Generic checks
##################################################################################################################
[[ ! -x $(basename ${0}) ]] 				&& log 3 "Please execute $(basename ${0}) from local directory (./run.sh)"
[[ ! -f shared/aws_credentials.tf ]] 	&& usage "File shared/aws_credentials.tf not found. Please see README.md"
[[ "${ENVIRONMENT}" == "" ]] 				&& usage "No environment (-E) set"
[[ ${EXEC} -ne 1 ]] 							&& usage "No action selected"

clear
binCheck git terraform

[[ ! -f terraform_modules/.git ]] 	&& rm -fr terraform_modules > /dev/null 2>&1
git submodule add --force  https://github.com/digiwhite1980/terraform.git terraform_modules > /dev/null
[[ $? -ne 0 ]]	 							&& log 3 "Failed to initialize submodules"

FLAGS="-var env=${ENVIRONMENT}"
[[ "${CIDR_PREFIX}" != "" ]] 		&& FLAGS="${FLAGS} -var cidr_vpc_prefix=${CIDR_PREFIX}"
[[ "${AWS_REGION}" != "" ]] 		&& FLAGS="${FLAGS} -var aws_region=${AWS_REGION}"
[[ "${DOMAINNAME}" != "" ]]		&& FLAGS="${FLAGS} -var domainname=${DOMAINNAME}"

[[ ! -d ${TERRAFORM_STATE} ]]	&& mkdir ${TERRAFORM_STATE}
[[ ! -d ${CONFIG_DIR} ]] 		&& mkdir ${CONFIG_DIR}
[[ ! -d ${DEPLOY_DIR} ]] 		&& mkdir ${DEPLOY_DIR}

[[ ${OVERWRITE_FLAGS} -eq 1 ]] && rm ${CONFIG_FLAGS}

if [ -s "${CONFIG_FLAGS}" ]; then
	. ${CONFIG_FLAGS}
	#########################################################################################################
	# File already exists so we overwite flags given
	#########################################################################################################
	log 1 "flags for ${0} found. Using : ${FLAGS}"
	sleep 3
else
	echo "FLAGS=\"${FLAGS}\"" > ${CONFIG_FLAGS}
fi

if [ ${CREATE_CUSTOM} -eq 1 ]; then
	[[ ! -d ${CUSTOM_FOLDER} ]] && mkdir -p ${CUSTOM_FOLDER}/terraform
	log 1 "Creating custom ${CUSTOM_FOLDER} environment"
	for FOLDER in $(ls -1d 0* | grep -v ${CUSTOM_FOLDER})
	do
		[[ ! -L ${CUSTOM_FOLDER}/terraform/${FOLDER}.tf ]] && ln -s ../../${FOLDER}/terraform/${FOLDER}.tf ${CUSTOM_FOLDER}/terraform/${FOLDER}.tf
	done

	[[ ! -L ${CUSTOM_FOLDER}/terraform/aws_credentials.tf ]] && ln -s ../../shared/aws_credentials.tf ${CUSTOM_FOLDER}/terraform/aws_credentials.tf
	[[ ! -L ${CUSTOM_FOLDER}/terraform/terraform.tfstate ]] && ln -s ../../terraform_state/terraform.tfstate ${CUSTOM_FOLDER}/terraform/terraform.tfstate
	[[ ! -L ${CUSTOM_FOLDER}/terraform/terraform.tfstate.backup ]] && ln -s ../../terraform_state/terraform.tfstate.backup ${CUSTOM_FOLDER}/terraform/terraform.tfstate.backup
	[[ ! -L ${CUSTOM_FOLDER}/terraform/variables.tf ]] && ln -s ../../shared/variables.tf ${CUSTOM_FOLDER}/terraform/variables.tf
fi

########################################################################################
# Disable run envrionemnt if -x is specified
########################################################################################

if [ "${DISABLE_RUN}" != "" ]; then
	for RUN in $(echo ${DISABLE_RUN} | tr "," " ")
	do
		case ${RUN} in
			2)
				toggleEnv 02_etcd
				;;
			3)
				toggleEnv 03_kubeapi
				;;
			4)
				toggleEnv 04_kubelet
				;;
			5)
				toggleEnv 05_services
				;;
			6)
				toggleEnv 06_custom
				;;
			s)
				for run in $(ls -1d 0*)
				do
					if [ -f ${run}/terraform/${run}.tf.disabled ]; then
						log 1 "Envirionment ${run} DISABLED"
					else
						log 1 "Environment ${run} ENABLED"
					fi
				done
				;;
			*)
				;;
		esac
	done
fi
	
########################################################################################
# The possible configuration options which are specified will be saved if not set
########################################################################################
# to build
########################################################################################

if [ ! -f config/aws_key ]; then
	cd 01_infra/terraform
	log 1 "AWS SSH Keys not found. Creating first..."
	createTfstate
	terraform init > /dev/null
	terraform apply -auto-approve ${FLAGS} --target=null_resource.ssh-key
	cd -
fi

if [ ${INFRA} -eq 1 -a ${ALL} -ne 1 ]; then
	[[ ! -d "01_infra" ]] && log 3 "Unable to find infra folder for option -i"
	cd 01_infra/terraform	
	log 1 "Executing terraform init on infra"
	createTfstate
	terraform init > /dev/null

	############################################################################
	# Because we cannot compute count for EIP we target 
	# data.aws_availability_zones.site_avz.names first
	############################################################################

	terraform apply ${AUTO} ${FLAGS} -target data.aws_availability_zones.site_avz
	terraform apply ${AUTO} ${FLAGS}
	cd -
fi

if [ ${ETCD} -eq 1 -a ${ALL} -ne 1 ]; then
	[[ ! -d "02_etcd" ]] && log 3 "Unable to find etcd folder for option -e"
	cd 02_etcd/terraform
	log 1 "Executing terraform init etcd"
	createTfstate
	terraform init > /dev/null
	terraform apply ${AUTO} ${FLAGS}
	cd -
fi

if [ ${KUBEAPI} -eq 1 -a ${ALL} -ne 1 ]; then
	[[ ! -d "03_kubeapi" ]] && log 3 "Unable to find kubeapi folder for option -a"
	cd 03_kubeapi/terraform
	log 1 "Executing terraform init kubeapi"
	createTfstate
	terraform init > /dev/null
	terraform apply ${AUTO} ${FLAGS}
	cd -
fi

if [ ${KUBELET} -eq 1 -a ${ALL} -ne 1 ]; then
	[[ ! -d "04_kubelet" ]] && log 3 "Unable to find kubelet folder for option -k"
	cd 04_kubelet/terraform
	log 1 "Executing terraform init kubelet"
	createTfstate
	terraform init > /dev/null
	terraform apply ${AUTO} ${FLAGS}
	cd -
fi

if [ ${SERVICES} -eq 1 -a ${ALL} -ne 1 ]; then
	[[ ! -d "05_services" ]] && log 3 "Unable to find services folder for option -s"
	cd 05_services/terraform
	log 1 "Executing terraform init services"
	createTfstate

	if [ ${TAINT} -eq 1 ]; then
		log 1 "Taint flag set: only executing kubernetes scripts"
		terraform taint null_resource.k8s_services
	fi

	terraform init > /dev/null
	terraform apply ${AUTO} ${FLAGS}
	cd -
fi

if [ ${CUSTOM} -eq 1 -o ${ALL} -eq 1 ]; then
	[[ ! -d ${CUSTOM_FOLDER} ]] && log 3 "Unable to find custom folder for option -c"
	cd ${CUSTOM_FOLDER}/terraform
	log 1 "Executing terraform init custom"
	createTfstate
	terraform init > /dev/null
	terraform apply ${AUTO} ${FLAGS}
	cd -
fi

if [ ${RESTORE_KUBECTL} -eq 1 ]; then
	cd 05_services/terraform
	log 1 "Restoring kubectl and kubeconfig"
	terraform taint null_resource.kubectlconfig
	terraform taint null_resource.kubectl
	terraform apply -auto-approve ${FLAGS} -target=null_resource.kubectlconfig -target=null_resource.kubectl -target=null_resource.k8s_context
	terraform taint null_resource.k8s_context
	terraform apply -auto-approve ${FLAGS} -target=null_resource.k8s_context
	cd -
fi

if [ ${DESTROY} -eq 1 ]; then
	[[ ! -d "01_infra" ]] && log 3 "Unable to find custom folder for option -D"

	log 1 "Deleting kubernetes yaml's with dependencies"

	if [ ${SKIP_SERVICES} -ne 1 ]; then
		for FILE in $(ls -1 deploy/k8s/*.yaml)
		do
			log 1 "Deleting yaml ${FILE}"
			kubectl --kubeconfig config/kubeconfig delete -f ${FILE} > /dev/null 2>&1
		done
		log 1 "Sleeping 20 seconds for services to delete AWS created infrastucture"
		rm -fr deploy/k8s/*.yaml 2> /dev/null
		sleep 20
	fi

	if [ "${DESTROY_SERVICES_ONLY}" == "1" ]; then
		exit 0
	fi	

	cd 01_infra/terraform
	log 1 "Executing terraform destroy"

	terraform destroy ${FLAGS}
	cd -
	rm -fr terraform_modules 2> /dev/null
	rm -fr config/* 2> /dev/null
fi

if [ ${OUTPUT} -eq 1 ]; then
	[[ ! -d "01_infra" ]] && log 3 "Unable to find custom folder for option -D"

	log 1 "Terraform output"
	cd 05_services/terraform

	createTfstate
	terraform output
fi
