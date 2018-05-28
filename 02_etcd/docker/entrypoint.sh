#!/bin/bash

###############################################################################
function consoleOutput {
	case "${1}" in
		3)
			echo "[$(date +%Y-%m-%d' '%H:%M:%S)] || Error = ${2}"
			exit 1
			;;
		2)
			echo "[$(date +%Y-%m-%d' '%H:%M:%S)] || Warning = ${2}"
			;;
		1)
			echo "[$(date +%Y-%m-%d' '%H:%M:%S)] || Ok = ${2}"
			;;
		*)
			echo "[$(date +%Y-%m-%d' '%H:%M:%S)] || Ok = ${2}"
			;;
	esac
}

function checkBin {
	###########################################################################
	# This functions will check the needed binaries for existance
	###########################################################################
	for BIN_FILE in ${@}
	do
		BIN_LOCATION=$(which ${BIN_FILE})
		[[ ! -x "${BIN_LOCATION}" ]] && consoleOutput 3 "Unable to locate ${BIN_FILE}. Aborting."
	done
}
###############################################################################
consoleOutput 1 "Starting ${0}"
###############################################################################
export TZ=${TZ:-Europe/Amsterdam}

if [ -f "/usr/share/zoneinfo/${TZ}" ]; then
	cp -p /usr/share/zoneinfo/${TZ} /etc/localtime
	consoleOutput 1 "Setting TZ to ${TZ}"
else
	consoleOutput 2 "${TZ} not found. Setting time to UTC"
fi

checkBin curl docker ${ED_HOME}/bin/etcd

##############################################################################
# Here we define the way we add nodes: based on host or IP. When using SSL
# please use host.
##############################################################################
export ETCD_MEMBER_TYPE=${ETCD_MEMBER_TYPE:-host}

INSTANCE_OWN_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
INSTANCE_OWN_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
INSTANCE_OWN_HN=$(curl -s http://169.254.169.254/latest/meta-data/local-hostname)
INSTANCE_COUNT=0

###############################################################################

#if [ "${ELB_ENDPOINT}" == "" ]; then
#	consoleOutput 3 "Variable ELB_ENDPOINT not set. Aborting"
#fi

#if [ "${HOST_IP}" == "" ]; then
#	consoleOutput 3 "Variable HOST_IP not set. Aborting"
#fi

###############################################################################

export CURL_OPT="-k"

###############################################################################
# Dont forget to mount (docker -v) the docker.sock into the container
###############################################################################
export DOCKER_SOCKET=${DOCKER_SOCKET:-/var/run/docker.sock}
export DOCKER_AWSCLI=${DOCKER_AWSCLI:-anigeo/awscli}
export DOCKER_AWSREG=${DOCKER_AWSREG:-eu-west-1}

export DOCKER_EC2TAG=${DOCKER_EC2TAG:-etcd}
export DOCKER_EC2VAL=${DOCKER_EC2VAL:-1}

export DOCKER_AWS_CMD="docker -H unix:///${DOCKER_SOCKET} run --rm -i ${DOCKER_AWSCLI}"
export DOCKER_TAG_OPT="--region ${DOCKER_AWSREG} ec2 describe-tags"
export DOCKER_TAG_FTR="--filter Name=key,Values=${DOCKER_EC2TAG} Name=value,Values=${DOCKER_EC2VAL}"
export DOCKER_EC2_OPT="--region ${DOCKER_AWSREG} ec2 describe-instances"

export CLNT_PORT=${CLNT_PORT:-2379}
export CLNT_SCHEMA=${CLNT_SCHEMA:-http}

export PEER_PORT=${PEER_PORT:-2380}
export PEER_SCHEMA=${PEER_SCHEMA:-http}

export BOOTSTRAP_WAIT=${BOOTSTRAP_WAIT:-20}

export ETCD_MEMBER_ADD_OK=201
export ETCD_MEMBER_DEL_OK=204

##############################################################################
# We first check for certificates. If present we also need to set the schema
# ---------------------------------------------------------------------------
# When using client and peer certificate you need to add the node ip address
# to the SSL certificate SAN (hosts / ip's). If not verification of client
# will fail
##############################################################################
export CLIENT_TRUSTED_CA_FILE=${CLIENT_TRUSTED_CA_FILE:-client_ca.crt}
export CLIENT_CERT_FILE=${CLIENT_CERT_FILE:-client.crt}
export CLIENT_KEY_FILE=${CLIENT_KEY_FILE:-client.key}

if [ -f ${ED_SSL}/${CLIENT_CERT_FILE} -a -f ${ED_SSL}/${CLIENT_KEY_FILE} -a "${ETCD_AUTO_TLS}" == "" ]; then
	export ETCD_CERT_FILE=${ED_SSL}/${CLIENT_CERT_FILE}
	export ETCD_KEY_FILE=${ED_SSL}/${CLIENT_KEY_FILE}
	export CLNT_SCHEMA=https
	export CURL_OPT_CLIENT="--cert ${ED_SSL}/${CLIENT_CERT_FILE} --key ${ED_SSL}/${CLIENT_KEY_FILE}"
fi

if [ -f "${ED_SSL}/${CLIENT_TRUSTED_CA_FILE}" ]; then
	export ETCD_TRUSTED_CA_FILE=${ED_SSL}/${CLIENT_TRUSTED_CA_FILE}
	export CURL_OPT_CLIENT="${CURL_OPT_CLIENT} --cacert ${ED_SSL}/${CLIENT_TRUSTED_CA_FILE}"
fi

if [ -f ${ED_SSL}/${CLIENT_TRUSTED_CA_FILE} ]; then
	cp ${ED_SSL}/${CLIENT_TRUSTED_CA_FILE} /etc/ssl/certs
	consoleOutput 1 "Stage [0]: Setting ca-certifcates ${CLIENT_TRUSTED_CA_FILE} with update-ca-certificates"
	update-ca-certificates > /dev/null 2>&1
fi

if [ -f ${ED_SSL}/${PEER_TRUSTED_CA_FILE} ]; then
	cp ${ED_SSL}/${PEER_TRUSTED_CA_FILE} /etc/ssl/certs
	consoleOutput 1 "Stage [0]: Setting ca-certifcates ${peer_TRUSTED_CA_FILE} with update-ca-certificates"
	update-ca-certificates > /dev/null 2>&1
fi
### ---------------------------------------------------------------------- ###

export PEER_TRUSTED_CA_FILE=${PEER_TRUSTED_CA_FILE:-peer_ca.crt}
export PEER_CERT_FILE=${PEER_CERT_FILE:-peer.crt}
export PEER_KEY_FILE=${PEER_KEY_FILE:-peer.key}

if [ -f ${ED_SSL}/${PEER_CERT_FILE} -a -f ${ED_SSL}/${PEER_KEY_FILE} -a "${ETCD_PEER_AUTO_TLS}" == "" ]; then
	export ETCD_PEER_CERT_FILE=${ED_SSL}/${PEER_CERT_FILE}
	export ETCD_PEER_KEY_FILE=${ED_SSL}/${PEER_KEY_FILE}
	export PEER_SCHEMA=https
	export CURL_OPT_PEER="--cert ${ED_SSL}/${PEER_CERT_FILE} --key ${ED_SSL}/${PEER_KEY_FILE}"
fi

if [ -f "${ED_SSL}/${PEER_TRUSTED_CA_FILE}" ]; then
	export ETCD_PEER_TRUSTED_CA_FILE=${ED_SSL}/${PEER_TRUSTED_CA_FILE}
	export CURL_OPT_PEER="${CURL_OPT_PEER} --cacert ${ED_SSL}/${PEER_TRUSTED_CA_FILE}"
fi

#############################################################################
# We use AUTO_TLS to only encrypt data in motion, not authenticate it
#############################################################################
[[ "${ETCD_AUTO_TLS}" != "" ]] 		&& export CLNT_SCHEMA=https
[[ "${ETCD_PEER_AUTO_TLS}" != "" ]]	&& export PEER_SCHEMA=https

##############################################################################

export ETCD_DATA_DIR=${ETCD_DATA_DIR:-$ED_DATA}
export ETCD_WAL_DIR=${ETCD_WAL_DIR:-$ED_WAL}
export ETCD_LISTEN_CLIENT_URLS=${ETCD_LISTEN_CLIENT_URLS:-${CLNT_SCHEMA}://${INSTANCE_OWN_IP}:${CLNT_PORT}},http://127.0.0.1:${CLNT_PORT}
export ETCD_LISTEN_PEER_URLS=${ETCD_LISTEN_PEER_URLS:-${PEER_SCHEMA}://${INSTANCE_OWN_IP}:${PEER_PORT}}
export ETCD_NAME=${ETCD_NAME:-${INSTANCE_OWN_ID}}

if [ ${ETCD_MEMBER_TYPE} == "host" ]; then
	export ETCD_ADVERTISE_CLIENT_URLS=${ETCD_ADVERTISE_CLIENT_URLS:-${CLNT_SCHEMA}://${INSTANCE_OWN_HN}:${CLNT_PORT}}
	export ETCD_INITIAL_ADVERTISE_PEER_URLS=${ETCD_INITIAL_ADVERTISE_PEER_URLS:-${PEER_SCHEMA}://${INSTANCE_OWN_HN}:${PEER_PORT}}
else
	export ETCD_ADVERTISE_CLIENT_URLS=${ETCD_ADVERTISE_CLIENT_URLS:-${CLNT_SCHEMA}://${INSTANCE_OWN_IP}:${CLNT_PORT}}
	export ETCD_INITIAL_ADVERTISE_PEER_URLS=${ETCD_INITIAL_ADVERTISE_PEER_URLS:-${PEER_SCHEMA}://${INSTANCE_OWN_IP}:${PEER_PORT}}
fi

export ETCD_INITIAL_CLUSTER_TOKEN=${ETCD_INITIAL_CLUSTER_TOKEN:-default}

################################################################################
# Enable metrics endpoint
################################################################################
[[ "${ETCD_LISTEN_METRICS_URLS}" != "" ]] \
	&& export ETCD_LISTEN_METRICS_URLS=${CLNT_SCHEMA}://${INSTANCE_OWN_IP}:${CLNT_PORT}

################################################################################
# Here we need to figure out if a new cluster needs to be created
################################################################################

[[ -S ${DOCKER_SOCKET} ]] || consoleOutput 3 "${DOCKER_SOCKET} not found. Aborting"
[[ -x $(which docker)  ]] || consoleOutput 3 "docker executable not found. Aborting"

while [ ${INSTANCE_COUNT} -lt 2 ]
do
	INSTANCE_COUNT=$(${DOCKER_AWS_CMD} ${DOCKER_TAG_OPT} ${DOCKER_TAG_FTR} | jq '.Tags |length')
	consoleOutput 1 "Stage [1]: Determining bootstrap count (at least 2 nodes needed: received: ${INSTANCE_COUNT})"
	[[ ${INSTANCE_COUNT} -lt 2 ]] && sleep ${BOOTSTRAP_WAIT}
	consoleOutput 1 "[1]: Bootstrap [instance] count: [${INSTANCE_COUNT}]. [Sleeing: ${BOOTSTRAP_WAIT}]"
done

#################################################################################
# We found at least 2 nodes so we are going to fetch instance-id's + private ip's
#################################################################################

consoleOutput 1 "Stage [2]: retreive corresponding IP adres for instances"
for INSTANCE in $(${DOCKER_AWS_CMD} ${DOCKER_TAG_OPT} ${DOCKER_TAG_FTR} | jq -r '.Tags[] | "\(.ResourceId)"')
do
	INSTANCE_IH=$(${DOCKER_AWS_CMD} ${DOCKER_EC2_OPT} --instance=${INSTANCE} | jq -r '.Reservations[].Instances[] | "\(.PrivateIpAddress):\(.PrivateDnsName)"')
	INSTANCE_IP=$(echo ${INSTANCE_IH} | awk -F: '{print $1}') 
	INSTANCE_HN=$(echo ${INSTANCE_IH} | awk -F: '{print $2}') 

	if [[ ! "${INSTANCE_IP}"  =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
		consoleOutput 1 "[2]: - instance ${INSTANCE} State = has null address. [Instance probably terminated]"
		continue
	fi

	[[ "${ETCD_MEMBER_TYPE}" == "host" ]] \
		&& INSTANCE_DATA[${INSTANCE_COUNT}]=${INSTANCE}:${INSTANCE_HN} \
		|| INSTANCE_DATA[${INSTANCE_COUNT}]=${INSTANCE}:${INSTANCE_IP}

	((INSTANCE_COUNT=INSTANCE_COUNT+1))
	consoleOutput 1 "[2]: * Instance ${INSTANCE}[${INSTANCE_COUNT}] [ip: ${INSTANCE_IP}, dns: ${INSTANCE_HN}]"
done

#################################################################################
# We have all nodes available. We now check the health of a possible existing
# cluster. If no health is found, we start a new cluster
#################################################################################

consoleOutput 1 "Stage [3]: Check for health in case ETCD cluster exists"
CLUSTER_EXISTS=0
for INSTANCE in ${INSTANCE_DATA[@]}
do
	INSTANCE_ID=$(echo ${INSTANCE} | awk -F: '{print $1}')
	INSTANCE_IP=$(echo ${INSTANCE} | awk -F: '{print $2}')

	if [ "${INSTANCE_ID}" == "${INSTANCE_OWN_ID}" ]; then
		consoleOutput 1 "[3]: * Instance ${INSTANCE_ID} matched own [id: ${INSTANCE_OWN_ID}]. [Skipping]"
		continue
	fi

	HEALTH=$(curl ${CURL_OPT} ${CURL_OPT_CLIENT} -m 3 -s ${CLNT_SCHEMA}://${INSTANCE_IP}:${CLNT_PORT}/health | jq -r .health)
	if [ "${HEALTH}" == "true" ]; then
		consoleOutput 1 "[3]: * Instance ${INSTANCE_ID} State = Healty [ip/hn: ${INSTANCE_IP}, schema: ${CLNT_SCHEMA}]"
		CLUSTER_EXISTS=1
		LAST_HEALTHY_IP=${INSTANCE_IP}

		[[ "${TMP_ETCD_INITIAL_CLUSTER}" == "" ]] \
			&& TMP_ETCD_INITIAL_CLUSTER="${INSTANCE_ID}=${PEER_SCHEMA}://${INSTANCE_IP}:${PEER_PORT}" \
			|| TMP_ETCD_INITIAL_CLUSTER+=",${INSTANCE_ID}=${PEER_SCHEMA}://${INSTANCE_IP}:${PEER_PORT}"
	else
		consoleOutput 1 "[3]: - Instance ${INSTANCE_ID} State = Unhealthy [ip/hn: ${INSTANCE_IP}, schema: ${CLNT_SCHEMA}]"
	fi
done

consoleOutput 1 "[3]: * ETCD_INITIAL_CLUSTER=${TMP_ETCD_INITIAL_CLUSTER}"
export ETCD_INITIAL_CLUSTER=${TMP_ETCD_INITIAL_CLUSTER}

case ${CLUSTER_EXISTS} in
	0)
		consoleOutput 1 "Stage [4]: Setting ETCD in initial cluster setup: new"
		export ETCD_INITIAL_CLUSTER=${TMP_ETCD_INITIAL_CLUSTER}
		export ETCD_INITIAL_CLUSTER_STATE="new"
		;;
	1)
		declare -A MEMBER_DATA_FAULTY
		consoleOutput 1 "Stage [4]: Setting ETCD in initial cluster setup: existing"
		for INSTANCE in $(curl ${CURL_OPT} ${CURL_OPT_CLIENT} -s ${CLNT_SCHEMA}://${LAST_HEALTHY_IP}:${CLNT_PORT}/v2/members | jq -r '.members[] | "\(.id);\(.name);\(.peerURLs[])"')
		do
			INSTANCE_ID=$(echo ${INSTANCE} | awk -F';' '{print $1}')
			INSTANCE_NM=$(echo ${INSTANCE} | awk -F';' '{print $2}')
			INSTANCE_IP=$(echo ${INSTANCE} | awk -F';' '{print $3}')
			INSTANCE_CL=$(echo ${INSTANCE_IP} | sed "s/:[0-9]*$/:${CLNT_PORT}/g")
			consoleOutput 1 "[4]: Instance ${INSTANCE_ID}=${INSTANCE_CL} found."

			######################################################################################
			# if instance name or client IP are empty, we set node to faulty
			######################################################################################
			if [ "${INSTANCE_NM}" == "" -o "${INSTANCE_CL}" == "" ]; then
				consoleOutput 1 "[4]: - Instance ${INSTANCE_ID} State = Faulty. Registering to faulty index."
				MEMBER_DATA_FAULTY[${INSTANCE_ID}]=${INSTANCE_ID}
				continue
			fi

			if [[ "${PEER_SCHEMA}://${INSTANCE_OWN_IP}:${PEER_PORT}" == "${INSTANCE_IP}" ]]; then
				consoleOutput 1 "[4]: - Instance ${INSTANCE_ID} State = Own instance. Possible restart. [Set State = Join]"
				ETCD_INITIAL_CLUSTER+=",${INSTANCE_OWN_ID}=${PEER_SCHEMA}://${INSTANCE_OWN_IP}:${PEER_PORT}"
				INSTANCE_OWN_FOUND=1
				continue
			fi
			consoleOutput 1 "[4]: * Instance ${INSTANCE_ID} State = Ok."
			
			consoleOutput 1 "[4]: * Instance ${INSTANCE_ID}=${INSTANCE_CL} checking for health."
			HEALTH=$(curl ${CURL_OPT} ${CURL_OPT_CLIENT} -m 3 -s ${INSTANCE_CL}/health | jq -r .health)
			if [ "${HEALTH}" != "true" ]; then
				[[ "${INSTANCE_NM}" == "" ]] && INSTANCE_NM=${INSTANCE_ID}
				consoleOutput 1 "[4]: - Instance ${INSTANCE_ID} State = Unhealthy [ip: ${INSTANCE_IP}]"
				MEMBER_DATA_FAULTY[${INSTANCE_NM}]=${INSTANCE_ID}
			else
				consoleOutput 1 "[4]: * Instance ${INSTANCE_ID} State = Healthy [ip: ${INSTANCE_IP}]"
			fi

			[[ "${INSTANCE_NM}" == "${INSTANCE_OWN_ID}" ]] && INSTANCE_OWN_FOUND=1
		done

		export ETCD_INITIAL_CLUSTER_STATE="existing"
		;;
esac

##########################################################################
# Here we check if we have failty nodes. If so we delete them from 
# the ETCD cluster. This needs to be done first before we can add 
# the new member
##########################################################################
if [ ${#MEMBER_DATA_FAULTY[@]} -gt 0 -a ${INSTANCE_COUNT} -ge 2 ]; then
	consoleOutput 1 "Stage [5]: We have a faulty index. Looping for removal."

	for INSTANCE_ID in ${MEMBER_DATA_FAULTY[@]}
	do
		consoleOutput 1 "[5]: Instance ${INSTANCE_ID}. Removing from cluster."
		HTTP_CODE=$(curl ${CURL_OPT} ${CURL_OPT_CLIENT} -s -o /dev/null -w "%{http_code}" ${CLNT_SCHEMA}://${LAST_HEALTHY_IP}:${CLNT_PORT}/v2/members/${INSTANCE_ID} \
			-X DELETE)

		[[ "${HTTP_CODE}" != "${ETCD_MEMBER_DEL_OK}" ]] \
			&& consoleOutput 3 "[5]: - Instance ${INSTANCE_ID} State = Failed to remove from cluster. [Aborting]" \
			|| consoleOutput 1 "[5]: * Instance ${INSTANCE_ID} State = Removed from cluster."
	done
fi		

##########################################################################################
# We need to check if our INSTANCE_OWN_ID is a member of the cluster. If not we need to
# add our selve as a member 
##########################################################################################
if [ "${INSTANCE_OWN_FOUND}" != "1" -a ${CLUSTER_EXISTS} -ne 0 ]; then
	((INSTANCE_COUNT=INSTANCE_COUNT+1))
	consoleOutput 1 "[6]: We are a new members. Adding to cluster."

	[[ ${ETCD_MEMBER_TYPE} == "host" ]] \
		&& MEMBER_ADD_ADDRESS=${INSTANCE_OWN_HN} \
		|| MEMBER_ADD_ADDRESS=${INSTANCE_OWN_IP}

	HTTP_CODE=$(curl ${CURL_OPT} ${CURL_OPT_CLIENT} -s -o /dev/null -w "%{http_code}" ${CLNT_SCHEMA}://${LAST_HEALTHY_IP}:${CLNT_PORT}/v2/members \
		-X POST \
		-H 'Content-Type: application/json' \
		-d '{"peerURLs":["'${PEER_SCHEMA}'://'${MEMBER_ADD_ADDRESS}':'${PEER_PORT}'"]}')

	[[ "${HTTP_CODE}" != "${ETCD_MEMBER_ADD_OK}" ]] \
		&& consoleOutput 3 "[6]: - Instance ${INSTANCE_OWN_IP} State = Failed to add to cluster [http_code: ${HTTP_CODE}]. [Aborting]" \
		|| consoleOutput 1 "[6]: * Instance ${INSTANCE_OWN_IP} State = Added to cluster"

	ETCD_INITIAL_CLUSTER+=",${INSTANCE_OWN_ID}=${PEER_SCHEMA}://${INSTANCE_OWN_IP}:${PEER_PORT}"
fi

export ETCD_INITIAL_CLUSTER

consoleOutput 1 "[100]: Starting ${ED_HOME}/bin/etcd ${ETCD_OPTS}"
${ED_HOME}/bin/etcd ${ETCD_OPTS}
