# ETCD container based on AWS flags
This docker images uses AWS tags to automatically deploy a multimaster ETCD cluster. It uses the generic ETCD_ variables to provision the ETCD cluster.
In order to do so, the image uses the internal docker.socket from the guest operating system to initiate the default configured anigeo/awscli image.
All EC2 instances are equipped with the correct machine role (see example terraform scripts) in order to obtain the EC2 tags through the AWS cli.

The image will wait for at least two nodes to become available prior to starting the ETCD cluster. In some cases the second node will be faulty / not 
available. This will not prevent the cluster from being bootstrapped. The second node will extend the cluster resulting in an operational, 2 node, cluster.

Cleaning takes place only when restarting the ETCD service or bootstrapping new nodes.

## Before you start
* Make sure you add your AWS public and private SSH key in the private folder
* cp init/aws_credentials.tf.example to init/aws_credentials.tf and alter the file with the correct settings
* If you are in a region different then eu-west-1 please alter init/variables.tf :: subnet_private / subnet_public to meet your region and subnet count
* Take a look at init/init.tf :: module "instance_etcd". Here the variable count is set to 2. Change this to play with your ETCD cluster.
* execute ./run.sh in order to start deploying the ETCD cluster on AWS

## ETCD variables
As stated the image uses variables in order determine the working environment. Currently the following environment variables have default values
set which can be overridden.
```
##############################################################################
# Dont forget to mount (docker -v) the docker.sock into the container
##############################################################################
export DOCKER_SOCKET=${DOCKER_SOCKET:-/var/run/docker.sock}
export DOCKER_AWSCLI=${DOCKER_AWSCLI:-anigeo/awscli}
export DOCKER_AWSREG=${DOCKER_AWSREG:-eu-west-1}

export DOCKER_EC2TAG=${DOCKER_EC2TAG:-etcd}
export DOCKER_EC2VAL=${DOCKER_EC2VAL:-1}

export CLNT_PORT=${CLNT_PORT:-2379}
export CLNT_SCHEMA=${CLNT_SCHEMA:-http}

export PEER_PORT=${PEER_PORT:-2380}
export PEER_SCHEMA=${PEER_SCHEMA:-http}

export ETCD_MEMBER_ADD_OK=201
export ETCD_MEMBER_DEL_OK=204
```

Both DOCKER_EC2TAG and DOCKER_EC2VAL are used to filter EC2 instanced based on their Tags. If your ETCD EC2 instances have different tags for distinction
please override these variables with the docker -e VAR= command.

## Terraform example
The provides Terraform scripts are based on the latest Ubuntu image. This however can be changed into any flavor you like. Please keep in mind that 
the examples so you the cloud-init mechanism in order to provision the ETCD systemd service. CoreOS will be a good replacement is wanted.

## SSL / TLS
In the Terraform sample scripts, SSL certificates can be rendered and directly injected through cloud-init scripts. Please keep in mind that when using
a custom CA, all SSL certificates need to have the corresponding endpoint IP within the Certificate Subject Names. In our Terraform examples we 
dynamically provision ETCD members. In this case the private IP address is not fixed. If you want to use fixed addresses you need to create a map 
within Terraform and connect the index counter to the private IP address entry within the Terraform module "instance".

In the following example the export of the client certificate is shown. The entrypoint script will look for these certificates in the ${ED_SSL} folder
which is set in the Dockerfile. When using the docker -v option, which is used in the example, the SSL certificates are directly made available for ETCD.
```
export CLIENT_TRUSTED_CA_FILE=${CLIENT_TRUSTED_CA_FILE:-client_ca.crt}
export CLIENT_CERT_FILE=${CLIENT_CERT_FILE:-client.crt}
export CLIENT_KEY_FILE=${CLIENT_KEY_FILE:-client.key}
```

### Using -auto-tls | -peer-auto-tls
When only encrypted communication is needed, the -auto-tls (ETCD_AUTO_TLS) and -peer-auto-tls (ETCD_PEER_AUTO_TLS) variables can be used.
ETCD will automatically generate self-signed certificates in order to encrypt both client and peer communication. The following examples
show how to communicate with the client endpoint using both etcdctl and curl.

**When using ETCD_AUTO_TLS or ETCD_PEER_AUTO_TLS the self signed client certificate is used as de ca certificate in the etcdctl command:**
```
# /etcd/bin/etcdctl --ca-file /etcd/data/fixtures/client/cert.pem member list
```

**When using Curl instead, the -k option van be used:**
```
# curl -k https://<client endpoint>:<client port>/v2/members
```
