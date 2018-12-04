# #################################################################################

module "subnet_public" {
  source            = "../../terraform_modules/subnet"

  name              = "Public"

  vpc_id            = "${module.site.aws_vpc_id}"
  project           = "${module.site.project}"
  environment       = "${module.site.environment}"

  cidr_block        = [ "${local.cidr_public}" ]
  
  availability_zone = [ "${data.aws_availability_zones.site_avz.names}" ]

  map_public_ip     = true            

  tags = {
    KubernetesCluster     = "${var.kubernetes["name"]}-${module.site.environment}"
    KubernetesVersion     = "${var.kubernetes["k8s"]}"
  }             
}

output "subnet_public" {
  value = "${module.subnet_public.id}"
}

# #################################################################################
# EIP count cannot be computed. Therefor we need to -target aws_availability_zones
# first in order to generate a count.
# #################################################################################

module "eip_natgateway" {
  source            = "../../terraform_modules/eip_default"

  count             = "${length(data.aws_availability_zones.site_avz.names)}"
}

output "eip_natgateway" {
  value = "${module.eip_natgateway.public_ip}"
}

# #################################################################################
# The NAT gateway must be placed in the public subnet in order to route correctly
# #################################################################################

module "natgateway_private" {
  source            = "../../terraform_modules/nat_gateway"

  count             = "${length(data.aws_availability_zones.site_avz.names)}"
  eip_id            = "${module.eip_natgateway.id}"
  subnet_id         = "${module.subnet_public.id}"

  name              = "${module.site.environment}"
}

# #################################################################################

module "route_table_natgateway_private" {
  source            = "../../terraform_modules/route_table_nat_gateway"

  count             = "${length(data.aws_availability_zones.site_avz.names)}"
  vpc_id            = "${module.site.aws_vpc_id}"
  gateway_id        = "${module.natgateway_private.id}"
  cidr_block        = "0.0.0.0/0"

  project           = "${module.site.project}"
  environment       = "${module.site.environment}"
}

module "route_table_association_natgateway_private" {
  source            = "../../terraform_modules/route_table_association"

  count             = "${length(data.aws_availability_zones.site_avz.names)}"
  subnet_id         = "${module.subnet_private.id}"
  route_table_id    = "${module.route_table_natgateway_private.id}"
}

# ##################################################################################

module "sg_ingress_internal" {
  source            = "../../terraform_modules/sg_ingress_map"

  sg_name           = "${module.site.project}-${module.site.environment}-ingress-internal"
  aws_vpc_id        = "${module.site.aws_vpc_id}"

  ingress           = [
    {
      from_port     = 0
      to_port       = 0
      protocol      = "-1"
      cidr_blocks   = [ "${local.cidr_vpc["region"]}" ]      
    }
  ]
}

# ##################################################################################

module "sg_ingress_management" {
  source            = "../../terraform_modules/sg_ingress_map"

  sg_name           = "${module.site.project}-${module.site.environment}-ingress-management"
  aws_vpc_id        = "${module.site.aws_vpc_id}"

  ingress = [
    {
      from_port     = "${var.ports["ssh"]}"
      to_port       = "${var.ports["ssh"]}"
      protocol      = "tcp"
      cidr_blocks   = [ "${local.cidr_vpc["all"]}" ]
    },
    {
      from_port     = "${var.ports["https"]}"
      to_port       = "${var.ports["https"]}"
      protocol      = "tcp"
      cidr_blocks   = [ "${local.cidr_vpc["all"]}" ]
    }
  ]
}

module "sg_egress" {
  source            = "../../terraform_modules/sg_egress_map"

  sg_name           = "${module.site.project}-${module.site.environment}-egress"
  aws_vpc_id        = "${module.site.aws_vpc_id}"

  egress            = [
    {
      cidr_blocks   = [ "${local.cidr_vpc["all"]}" ]
      from_port     = 0
      to_port       = 0
      protocol      = "-1"
      self          = true          
    }
  ]
}

module "sg_gress_kubernetes" {
  source                  = "../../terraform_modules/sg_gress_new"

  sg_name                 = "Kubernetes SG"
  aws_vpc_id              = "${module.site.aws_vpc_id}"
  environment             = "${module.site.environment}"

  ingress = [
    {
      from_port       = 0
      to_port         = 0
      protocol        = "-1"
      cidr_blocks     = [ "${local.cidr_vpc["region"]}" ]
      self            = true
    },
    {
      from_port       = "${var.ports["ssh"]}"
      to_port         = "${var.ports["ssh"]}"
      protocol        = "tcp"
      cidr_blocks     = [ "${local.cidr_vpc["all"]}" ]
    }
  ]

  egress = [
    {
      from_port       = 0
      to_port         = 0
      protocol        = "-1"
      cidr_blocks     = [ "${local.cidr_vpc["all"]}" ]
      self            = true      
    }
  ]

  tags {
    KubernetesCluster     = "${var.kubernetes["name"]}-${module.site.environment}"
    KubernetesVersion     = "${var.kubernetes["k8s"]}"
  }
}

################################################################################

module "ssl_ca_key" {
  source              = "../../terraform_modules/ssl_private_key"
  rsa_bits            = 4096
}

module "ssl_ca_crt" {
  source                = "../../terraform_modules/ssl_self_signed_cert"

  private_key_pem       = "${module.ssl_ca_key.private_key_pem}"
  common_name           = "*"
  organization          = "${module.site.project}-${module.site.environment}"

  validity_period_hours = "${var.kubernetes["ca_ssl_valid"]}"
  is_ca_certificate     = true

  allowed_uses = [
    "key_encipherment",
    "cert_signing",
    "server_auth",
    "client_auth",
  ]
}

resource "null_resource" "ssl_ca_key" {
  triggers {
    ssl_ca_crt              = "${module.ssl_ca_key.private_key_pem}"
  }
  provisioner "local-exec" { command = "cat > ../../config/ca.key <<EOL\n${module.ssl_ca_key.private_key_pem}\nEOL\n" }
}

resource "null_resource" "ssl_ca_crt" {
  triggers {
    ssl_ca_crt              = "${module.ssl_ca_crt.cert_pem}"
  }
  provisioner "local-exec" { command = "cat > ../../config/ca.crt <<EOL\n${module.ssl_ca_crt.cert_pem}\nEOL\n" }
}

################################################################################

data "aws_ami" "ubuntu_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

# ##############################################################################################

module "ssl_kubeapi_key" {
  source              = "../../terraform_modules/ssl_private_key"
  rsa_bits            = 4096
}

module "ssl_kubeapi_csr" {
  source              = "../../terraform_modules/ssl_cert_request"

  private_key_pem     = "${module.ssl_kubeapi_key.private_key_pem}"

  #################################################################################
  # common_name and organization are mappes to user and group for RBAC
  #################################################################################
  # We set common name to cluster-admin
  # we set organization to system:masters
  #################################################################################
  common_name         = "cluster-admin"
  organization        = "system:masters" 
  organizational_unit = "${module.site.project} - ${module.site.environment}"
  street_address      = [ ]
  locality            = "Amsterdam"
  province            = "Noord-Holland"
  country             = "NL"

  dns_names           = [ "kubernetes",
                          "kubernetes.default",
                          "kubernetes.default.svc",
                          "kubernetes.default.svc.${var.kubernetes["cluster_domain"]}",
                          "127.0.0.1",
                          "${lookup(local.kubernetes_private, "api.0")}",
                          "*.${module.site.region}.compute.internal",
                          "*.compute.internal",
                          "*.${module.site.region}.compute.amazonaws.com",
                          "*.compute.amazonaws.com",
                          "*.${module.site.region}.elb.amazonaws.com",
                          "*.elb.amazonaws.com",
                          "*.${var.kubernetes["cluster_domain"]}",
                          "kubeapi.${module.site.environment}.${module.site.domain_name}",
                          "kubeapi",
                          "kubelet.${module.site.environment}.${module.site.domain_name}",
                          "kubelet",
                          "localhost",
                          "*.${module.site.domain_name}",
                          "${var.kubernetes["name"]}"
                        ]
  ip_addresses          = [
                          "127.0.0.1",
                          "${lookup(local.kubernetes_private, "api.0")}"
  ]
}

module "ssl_kubeapi_crt" {
  source                = "../../terraform_modules/ssl_locally_signed_cert"

  cert_request_pem      = "${module.ssl_kubeapi_csr.cert_request_pem}"
  ca_private_key_pem    = "${module.ssl_ca_key.private_key_pem}"
  ca_cert_pem           = "${module.ssl_ca_crt.cert_pem}"

  validity_period_hours = "${var.kubernetes["kubeapi_ssl_valid"]}"

  allowed_uses = [
    "key_encipherment",
    "server_auth",
    "client_auth",
  ]
}

# ##############################################################################################

resource "null_resource" "ssl_kubeapi_key" {
  triggers {
    ssl_ca_crt              = "${module.ssl_kubeapi_key.private_key_pem}"
  }
  provisioner "local-exec" { command = "cat > ../../config/kubeapi.key <<EOL\n${module.ssl_kubeapi_key.private_key_pem}\nEOL\n" }
}

resource "null_resource" "ssl_kubeapi_crt" {
  triggers {
    ssl_ca_crt              = "${module.ssl_kubeapi_crt.cert_pem}"
  }
  provisioner "local-exec" { command = "cat > ../../config/kubeapi.crt <<EOL\n${module.ssl_kubeapi_crt.cert_pem}\nEOL\n" }
}

# ##############################################################################################

data "template_file" "kubeconfig" {
  template                = "${file("../../03_kubeapi/terraform/templates/template_kubeconfig.tpl")}"

  vars {
    elb_name              = "${module.elb_kubeapi.dns_name}"
    ssl_ca_crt            = "${base64encode("${module.ssl_ca_crt.cert_pem}")}"
    ssl_kubeapi_key       = "${base64encode("${module.ssl_kubeapi_key.private_key_pem}")}"
    ssl_kubeapi_crt       = "${base64encode("${module.ssl_kubeapi_crt.cert_pem}")}"
    clustername           = "${module.site.environment}-${var.kubernetes["name"]}"
    namespace             = "${module.site.environment}"
  }
}

resource "null_resource" "kubeconfig" {
  # Any change to UUID (every apply) triggers re-provisioning
  triggers {
    #filename = "test-${uuid()}"
    ssl_kubeapi_crt         = "${module.ssl_kubeapi_crt.cert_pem}"
    elb_controller_dns_name = "${module.elb_kubeapi.dns_name}"
  }
  provisioner "local-exec" { command = "cat > ../../config/kubeconfig <<EOL\n${data.template_file.kubeconfig.rendered}\nEOL\n" }
}

data "template_file" "kubectlconfig" {
  template             = "${file("../../03_kubeapi/terraform/templates/template_kubectl_config.tpl")}"

  vars {
    root_path          = "${path.cwd}/../.."
    kubeapi_url        = "https://${module.elb_kubeapi.dns_name}"
    clustername        = "${module.site.environment}-${var.kubernetes["name"]}"
  }
}

resource "null_resource" "kubectlconfig" {
  triggers {
    ssl_kubeapi_crt    = "${module.ssl_kubeapi_crt.cert_pem}"
    kubeapi_url        = "${module.elb_kubeapi.dns_name}"
  }
  provisioner "local-exec" { command = "mkdir -p $HOME/.kube; cat > $HOME/.kube/config <<EOL\n${data.template_file.kubectlconfig.rendered}\nEOL\n" }
}

resource "null_resource" "kubectl" {
  provisioner "local-exec" { command = "curl -L -o /usr/bin/kubectl https://storage.googleapis.com/kubernetes-release/release/${var.kubernetes["k8s"]}/bin/linux/amd64/kubectl" }
  provisioner "local-exec" { command = "chmod 755 /usr/bin/kubectl" }
}

# ##############################################################################################

data "template_file" "instance-kubeapi" {
  template                = "${file("../../03_kubeapi/terraform/templates/kubeapi-cloud-config.tpl")}"

  vars {
    kubernetes_version    = "${var.kubernetes["k8s"]}"

    service_ip            = "${lookup(local.kubernetes_private, "api.0")}"
    service_ip_range      = "${lookup(local.cidr_private, "avz.0")}"
    cluster_dns           = "${lookup(local.kubernetes_private, "dns.0")}"

    cluster_domain        = "${var.kubernetes["cluster_domain"]}"
    
    cni_plugin_version    = "${var.kubernetes["cni_plugins"]}"

    instance_group        = "${module.site.environment}.${module.site.domain_name}"
    docker_port           = "${var.ports["docker"]}"
    #################################################################################
    # We will use internal route53 DNS for our ELB endpoint
    #################################################################################
    etcd_version          = "${var.kubernetes["etcd"]}"
    etcd_endpoint         = "https://${module.route53_record_etcd.fqdn}:2379"

    ssl_kubeapi_key       = "${module.ssl_kubeapi_key.private_key_pem}"
    ssl_kubeapi_crt       = "${module.ssl_kubeapi_crt.cert_pem}"
    
    ssl_ca_crt            = "${module.ssl_ca_crt.cert_pem}"

    ssl_etcd_key          = "${module.ssl_etcd_key.private_key_pem}"
    ssl_etcd_crt          = "${module.ssl_etcd_crt.cert_pem}"

    kubeapi_lb_endpoint   = "https://kubeapi.${module.site.environment}.${module.site.domain_name}"

    PRIVATE_IPV4          = "$${PRIVATE_IPV4}"

    environment           = "${module.site.environment}"
    cluster_name          = "${var.kubernetes["name"]}-${module.site.environment}"
  }
}
######################################################################################
# We use the template_cloudinit_config data type because we exceed the 16k user_data
# limit from the template (ssl certificates)
######################################################################################
data "template_cloudinit_config" "kubeapi" {
  gzip          = true
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content      = "${data.template_file.instance-kubeapi.rendered}"
  }
}

module "kubeapi_launch_configuration" {
  source               = "../../terraform_modules/launch_configuration"
  
  name_prefix          = "kubeapi-${module.site.project}-${module.site.environment}-"

  image_id             = "${data.aws_ami.ubuntu_ami.id}"
  instance_type        = "${var.instance["kubeapi"]}"
  iam_instance_profile = "${module.iam_instance_profile.name}"
  #############################################################
  # We dont use spot instances for etcd because we dont receive
  # the ip address directly so it will not be assigned to 
  # the loadBalancer
  #############################################################
  #spot_price           = "${var.instance_spot_price["etcd"]}"

  key_name             = "${module.key_pair.ssh_name_key}"

  volume_size          = "20"

  ebs_optimized        = false

  associate_public_ip_address = false

  user_data_base64     = "${data.template_cloudinit_config.kubeapi.rendered}"
  
  security_groups      = [ "${module.sg_gress_kubernetes.id}" ] 
}

data "template_file" "kubeapi_cloudformation" {
  template              = "${file("../../03_kubeapi/terraform/templates/kubeapi-cloudformation.tpl")}"

  vars {
    cluster_name        = "${var.kubernetes["name"]}-${module.site.environment}"
    kubernetes_version  = "${var.kubernetes["k8s"]}"
    environment         = "${module.site.environment}"
    resource_name       = "${var.kubernetes["name"]}${module.site.environment}kubeapi"
    subnet_ids          = "${join(",", module.subnet_private.id)}"
    launch_name         = "${module.kubeapi_launch_configuration.name}"
    loadbalancer        = "\"${module.elb_kubeapi_internal.name}\",\"${module.elb_kubeapi.name}\"" 
    max_size            = "${var.instance_count["kubeapi"]}"
    min_size            = "${var.instance_count["kubeapi_min"]}"
    pause_time          = "PT60S"
  }
}

module "kubeapi_cloudformation_stack" {
  source               = "../../terraform_modules/cloudformation_stack"

  name                 = "${module.site.project}${module.site.environment}kubeapi"
  template_body        = "${data.template_file.kubeapi_cloudformation.rendered}"
}

######################################################################
# This is an external LB so we could apply firewall rules through
# security groups
######################################################################
module "elb_kubeapi" {
  source                  = "../../terraform_modules/elb_map_asg"

  project                 = "${module.site.project}"
  environment             = "${module.site.environment}"

  name                    = "ELB-${var.project["kubeapi"]}"

  tags = {
    Name                  = "ELB-${var.project["kubeapi"]}"
  }

  subnet_ids              = [ "${module.subnet_public.id}" ]

  ####################################################################
  # We incease the load balancer idle timeout to 300. This is needed
  # in order to keep the connection with kubectl exec -ti alive
  ####################################################################
  lb_idle_timeout         = 300

  security_group_ids      = [ "${module.sg_egress.id}",
                              "${module.sg_ingress_management.id}" ]

  listener = [
    {
      instance_port       = "${var.ports["https"]}"
      instance_protocol   = "TCP"
      lb_port             = "${var.ports["https"]}"
      lb_protocol         = "TCP"
      #lb_protocol         = "HTTP"
      #ssl_certificate_id  = "${var.ssl_arn}"
    }
  ]

  health_check = [
    { 
      healthy_threshold   = 2
      unhealthy_threshold = 2
      timeout             = 3
      target              = "TCP:${var.ports["https"]}"
      interval            = 15
    }
  ]
}

output "elb_kubeapi" {
  value = "${module.elb_kubeapi.dns_name}"
}


######################################################################
# We use an internal LB for kube API communication. We dont have to 
# applyfirewall rules because it is not accessable from the outside 
# world
######################################################################
module "elb_kubeapi_internal" {
  source                  = "../../terraform_modules/elb_map_asg"

  project                 = "${module.site.project}"
  environment             = "${module.site.environment}"

  name                    = "ELB-${var.project["kubeapi"]}-internal"

  tags = {
    Name                  = "ELB-${var.project["kubeapi"]}"
    Internal              = true
  }

  subnet_ids              = [ "${module.subnet_private.id}" ]

  internal                = true

  security_group_ids      = [ "${module.sg_egress.id}",
                              "${module.sg_ingress_internal.id}" ]

  listener = [
    {
      instance_port       = "${var.ports["https"]}"
      instance_protocol   = "tcp"
      lb_port             = "${var.ports["https"]}"
      lb_protocol         = "tcp"
      #lb_protocol         = "HTTP"
      #ssl_certificate_id  = "${var.ssl_arn}"
    }
  ]

  health_check = [
    { 
      healthy_threshold   = 2
      unhealthy_threshold = 2
      timeout             = 3
      target              = "tcp:${var.ports["https"]}"
      interval            = 15
    }
  ]
}

output "elb_kubeapi_internal" {
  value = "${module.elb_kubeapi_internal.dns_name}"
}

# ####################################################################

module "route53_record_kubeapi" {
  source              = "../../terraform_modules/route53_record"

  type                = "CNAME"
  zone_id             = "${module.route53_zone.id}"
  name                =  "kubeapi.${module.site.environment}.${module.site.domain_name}"
  records             = [ "${module.elb_kubeapi_internal.dns_name}" ] 
}

module "instance_bastion" {
  source                      = "../../terraform_modules/instance_spot"
  spot_price                  = "${var.instance_spot_price["bastion"]}"

  availability_zone           = "${element(data.aws_availability_zones.site_avz.names, 0)}"
  
  count                       = "${var.instance_count["bastion"]}"

  tags = {
    bastion                   = "${module.site.environment}"
  }

  instance_name               = "bastion"
  environment                 = "${module.site.environment}"
  aws_subnet_id               = "${element(module.subnet_public.id, 0)}"

  ssh_user                    = "ubuntu"
  ssh_name_key                = "${module.key_pair.ssh_name_key}"
  ssh_pri_key                 = "${module.site.ssh_pri_key}"

  region                      = "${module.site.region}"

  aws_ami                     = "${data.aws_ami.ubuntu_ami.id}"

  iam_instance_profile        = "${module.iam_instance_profile.name}"

  root_block_device_size      = "20"

  security_groups_ids         = [ "${module.sg_ingress_management.id}",
                                  "${module.sg_egress.id}" ]

  aws_instance_type           = "${var.instance["default"]}"
  associate_public_ip_address = true

  user_data_base64            = ""
}

########################################################################
# Only enable this if bastion != spot instance
########################################################################
# output "instance_bastion_dns" {
#   value = "${module.instance_bastion.public_dns}"
# }