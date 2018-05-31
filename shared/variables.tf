############################################################
# This variable is set through terraform commandline
############################################################
variable "env" {
  default            = ""
}

variable "cidr_vpc_prefix" {
  default            = "10.0"
}

variable "cidr_vpc_postfix" {
  default            = "0.0/16"
}

variable "domainname" {
  default            = "example.internal"
}

locals  {
  cidr_vpc = {
    region    = "${var.cidr_vpc_prefix}.${var.cidr_vpc_postfix}"
    all       = "0.0.0.0/0"
  },

  cidr_public = {
    avz.0  = "${var.cidr_vpc_prefix}.110.0/24"
    avz.1  = "${var.cidr_vpc_prefix}.111.0/24"
    avz.2  = "${var.cidr_vpc_prefix}.112.0/24"
    avz.3  = "${var.cidr_vpc_prefix}.113.0/24"
    avz.4  = "${var.cidr_vpc_prefix}.114.0/24"
    avz.5  = "${var.cidr_vpc_prefix}.115.0/24"
    avz.6  = "${var.cidr_vpc_prefix}.116.0/24"
    avz.7  = "${var.cidr_vpc_prefix}.117.0/24"
    avz.8  = "${var.cidr_vpc_prefix}.118.0/24"
    avz.9  = "${var.cidr_vpc_prefix}.119.0/24"
  },

  cidr_private {
    avz.0  = "${var.cidr_vpc_prefix}.210.0/24"
    avz.1  = "${var.cidr_vpc_prefix}.211.0/24"
    avz.2  = "${var.cidr_vpc_prefix}.212.0/24"
    avz.3  = "${var.cidr_vpc_prefix}.213.0/24"
    avz.4  = "${var.cidr_vpc_prefix}.214.0/24"
    avz.5  = "${var.cidr_vpc_prefix}.215.0/24"
    avz.6  = "${var.cidr_vpc_prefix}.216.0/24"
    avz.7  = "${var.cidr_vpc_prefix}.217.0/24"
    avz.8  = "${var.cidr_vpc_prefix}.218.0/24"
    avz.9  = "${var.cidr_vpc_prefix}.219.0/24"    
  }

  kubernetes_public {
    api.0  = "${var.cidr_vpc_prefix}.110.1"
    dns.0  = "${var.cidr_vpc_prefix}.110.5"
  }

  kubernetes_private {
    api.0  = "${var.cidr_vpc_prefix}.210.1"
    dns.0  = "${var.cidr_vpc_prefix}.210.5"
  }
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

variable "project" {
  default = {
    main             = "k8s"
    etcd             = "etcd"
    kubeapi          = "kubeapi"
    kubelet          = "kubelet"
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
    kubelet          = 6
    kubelet_min      = 6
  }
}

variable "instance_sport_price" {
  default = {
    kubelet         = "1.0"
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
    k8s               = "v1.5.7"
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
    dashboard         = "v1.6.1"
    state-metrics     = "v1.3.1"
    addon-resizer     = "1.7"

    cluster_domain    = "cluster.local"

    namespace_demo    = "kube-public"
  }
}
