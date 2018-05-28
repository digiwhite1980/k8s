# #################################################################################
# # We demand terraform to be executed with the -var env={value} flag 
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
  vpc_cidr        = "${var.vpc_cidr["${var.env}"]}"

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

  cidr_block        = [ "${var.subnet_public}" ]
  
  availability_zone = [ "${data.aws_availability_zones.site_avz.names}" ]

  map_public_ip     = true                         
}

output "subnet_public" {
  value = "${module.subnet_public.id}"
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
      cidr_blocks   = [ "${var.vpc_cidr["${var.env}"]}" ]      
    }
  ]
}

module "sg_ingress_management" {
  source            = "../../terraform_modules/sg_ingress_map"

  sg_name           = "${module.site.project}-${module.site.environment}-ingress-management"
  aws_vpc_id        = "${module.site.aws_vpc_id}"

  ingress = [
    {
      from_port     = "${var.ports["ssh"]}"
      to_port       = "${var.ports["ssh"]}"
      protocol      = "TCP"
      cidr_blocks   = [ "0.0.0.0/0" ]
    },
    {
      from_port     = "${var.ports["https"]}"
      to_port       = "${var.ports["https"]}"
      protocol      = "TCP"
      cidr_blocks   = [ "0.0.0.0/0" ]
    }
  ]
}

module "sg_egress" {
  source            = "../../terraform_modules/sg_egress_map"

  sg_name           = "${module.site.project}-${module.site.environment}-egress"
  aws_vpc_id        = "${module.site.aws_vpc_id}"

  egress            = [
    {
      cidr_blocks   = [ "0.0.0.0/0" ]
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
      cidr_blocks     = [ "${var.vpc_cidr["${var.env}"]}" ]
      self            = true
    },
    {
      from_port       = "${var.ports["ssh"]}"
      to_port         = "${var.ports["ssh"]}"
      protocol        = "TCP"
      cidr_blocks     = [ "0.0.0.0/0" ]
      self            = true
    }
  ]

  egress = [
    {
      from_port       = 0
      to_port         = 0
      protocol        = "-1"
      cidr_blocks     = [ "0.0.0.0/0" ]
      self            = true      
    }
  ]

  tags {
    KubernetesCluster     = "${var.kubernetes["name"]}-${module.site.environment}"
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