# #################################################################################
# We demand terraform to be executed with the -var env={value} flag 
#
# terraform plan -var env={environment} -var cidr_prefix={x.x}
# #################################################################################

data "aws_caller_identity" "main" {}

# #################################################################################

data "aws_region" "site_region" {}

output "aws_region" {
  value = "${data.aws_region.site_region.name}"
}

# #################################################################################

data "aws_availability_zones" "site_avz" {}

output "aws_availability_zones" {
  value = "${data.aws_availability_zones.site_avz.names}"
}

# #################################################################################

resource "null_resource" "ssh-key" {
  # Any change to UUID (every apply) triggers re-provisioning
  # triggers {
  #   #filename = "test-${uuid()}"
  #   elb_controller_dns_name = "${module.elb_kubeapi_internal.dns_name}"
  # }
  provisioner "local-exec" { command = "echo -e  'y\n' | ssh-keygen -q -f ${var.ssh["ssh_priv"]} -C k8s-ssh-key  -N ''" }
}

# #################################################################################

module "site" {
  source          = "../../terraform_modules/site"

  region          = "${data.aws_region.site_region.name}"
  vpc_cidr        = "${local.cidr_vpc["region"]}"

  project         = "${var.project["main"]}"
  environment     = "${var.env}"
  domain_name     = "${var.domainname}"

  ssh_pri_key     = "${var.ssh["ssh_priv"]}"
  ssh_pub_key     = "${var.ssh["ssh_pub"]}"
}

module "key_pair" {
  source          = "../../terraform_modules/key_pair"

  ssh_name_key    = "${module.site.project}-${module.site.environment}-keypair"
  ssh_pub_key     = "${module.site.ssh_pub_key}"
}

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

module "subnet_private" {
  source            = "../../terraform_modules/subnet"

  name              = "Private"

  vpc_id            = "${module.site.aws_vpc_id}"
  project           = "${module.site.project}"
  environment       = "${module.site.environment}"

  cidr_block        = [ "${local.cidr_private}" ]
  
  availability_zone = [ "${data.aws_availability_zones.site_avz.names}" ]

  map_public_ip     = true                         
}

output "subnet_private" {
  value = "${module.subnet_private.id}"
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

################################################################################

data "template_file" "machine_default" {
  template             = "${file("../../01_infra/terraform/templates/template_machine_role.tpl")}"
}

data "template_file" "autoscaling_default" {
  template             = "${file("../../01_infra/terraform/templates/template_machine_role_autoscaling.tpl")}"
}

data "template_file" "machine_default_policy" {
  template             = "${file("../../01_infra/terraform/templates/template_machine_role_policy.tpl")}"
}

module "role_iam" {
  source              = "../../terraform_modules/iam_role"

  name                = "${module.site.project}-${module.site.environment}-role-machine" 
  assume_role_policy  = "${data.template_file.machine_default.rendered}"
}

module "role_iam_policy" {
  source              = "../../terraform_modules/iam_role_policy"

  name                = "${module.site.project}-${module.site.environment}-policy-machine"
  role                = "${module.role_iam.id}"
  policy              = "${data.template_file.machine_default_policy.rendered}"
}

module "iam_instance_profile" {
  source              = "../../terraform_modules/iam_instance_profile"

  name                = "${module.site.project}-${module.site.environment}-instance"
  role                = "${module.role_iam.id}"
}

module "role_autoscaling" {
  source              = "../../terraform_modules/iam_role"

  name                = "${module.site.project}-${module.site.environment}-role-autoscaling" 
  assume_role_policy  = "${data.template_file.autoscaling_default.rendered}"
}

module "role_autoscaling_policy" {
  source              = "../../terraform_modules/iam_role_policy"

  name                = "${module.site.project}-${module.site.environment}-policy-autoscaling"
  role                = "${module.role_autoscaling.id}"
  policy              = "${data.template_file.machine_default_policy.rendered}"
}

################################################################################

module "route53_zone" {
  source              = "../../terraform_modules/route53_zone_private"

  vpc_id              = "${module.site.aws_vpc_id}"

  project             = "${module.site.project}"
  environment         = "${module.site.environment}"
  domain_name         = "${module.site.environment}.${var.domainname}"
}

output "route53_zone_id" {
	value = "${module.route53_zone.id}"
}

output "route53_domain" {
	value = "${module.site.environment}.${var.domainname}"
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
