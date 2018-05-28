############################################################
# This variable is set through terraform commandline
############################################################
variable "env" {
  default            = ""
}

variable "domainname" {
  default            = "example.internal"
}

############################################################
# SSH certificate is generated through 01_infra.tf
############################################################
variable "ssh" {
  default = {
    ssh_priv         = "../../config/aws_key"
    ssh_pub          = "../../config/aws_key.pub"
  }
}

variable "ports" {
  default = {
    ssh              = "22"
    http             = "80"
    https            = "443"
    etcd_client      = "2379"
    etcd_peer        = "2380"
    docker           = "2376"
  }
}

variable "instance" {
  default = {
    default          = "t2.micro"
    etcd             = "t2.medium"
    kubeapi          = "t2.medium"
    kubelet          = "t2.large"
  }
}

variable "instance_count" {
  default = {
    etcd             = 2
    etcd_min         = 2
    kubeapi          = 1
    kubeapi_min      = 1
    kubelet          = 3
    kubelet_min      = 3
  }
}

variable "instance_sport_price" {
  default = {
    kubelet         = "1.0"
  }
}

variable "vpc_cidr" {
  default = {
    dev              = "10.11.0.0/16"
    acc              = "10.12.0.0/16"
    prd              = "10.13.0.0/16"
  }
}

variable "subnet_private" {
  default = { 
    dev.eu-west-1a   = "10.11.1.0/24"
    dev.eu-west-1b   = "10.11.11.0/24"
    dev.eu-west-1c   = "10.11.21.0/24"
    acc.eu-west-1a   = "10.12.2.0/24"
    acc.eu-west-1b   = "10.12.12.0/24"
    acc.eu-west-1c   = "10.12.22.0/24"
    prd.eu-west-1a   = "10.13.3.0/24"
    prd.eu-west-1b   = "10.13.13.0/24"
    prd.eu-west-1c   = "10.13.23.0/24"
  }
}

variable "subnet_public" {
  default = {
    dev.eu-west-1a   = "10.11.101.0/24"
    dev.eu-west-1b   = "10.11.111.0/24"
    dev.eu-west-1c   = "10.11.121.0/24"
    acc.eu-west-1a   = "10.12.102.0/24"
    acc.eu-west-1b   = "10.12.112.0/24"
    acc.eu-west-1c   = "10.12.122.0/24"
    prd.eu-west-1a   = "10.13.103.0/24"
    prd.eu-west-1b   = "10.13.113.0/24"
    prd.eu-west-1c   = "10.13.123.0/24"
  }
}


variable "project" {
  default = {
    main             = "k8s"
    etcd             = "etcd"
    kubeapi          = "kubeapi"
    kubelet          = "kubelet"
  }
}

variable "kubernetes" {
  default = {
    ##########################################
    # SSL Validity = 1 year (8544 hours)
    ##########################################
    ca_ssl_valid      = "8544"
    etcd_ssl_valid    = "8544"
    kubeapi_ssl_valid = "12"
    kubelet_ssl_valid = "12" 
    name              = "kube"
    k8s               = "v1.9.7"
    cni_plugins       = "v0.7.1"
    proxy             = "0.3"
    etcd              = "3.2.2"
    coredns           = "1.1.2"
    #########################################
    # KubeDNS
    #########################################
    kubedns           = "1.9"
    kubednsmasq       = "1.4"
    exechealthz       = "1.2"
    #########################################
    dashboard         = "v1.8.3"
    state-metrics     = "v1.3.1"
    addon-resizer     = "1.7"

    service_ip        = "10.11.101.1"
    service_ip_range  = "10.11.101.0/24"
    flannel_ip_range  = "192.168.0.0/16"
    cluster_dns       = "10.11.101.10"
    cluster_domain    = "cluster.local"

    namespace_demo    = "kube-public"
  }
}
