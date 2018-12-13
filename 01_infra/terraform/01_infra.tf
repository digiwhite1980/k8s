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

  project         = "${var.tag}"
  environment     = "${var.env}"
  domain_name     = "${var.domainname}"

  ssh_pri_key     = "${var.ssh["ssh_priv"]}"
  ssh_pub_key     = "${var.ssh["ssh_pub"]}"

  tags {
    Name          = "${var.tag}"
    Environment   = "${var.env}"
  }
}

module "key_pair" {
  source          = "../../terraform_modules/key_pair"

  ssh_name_key    = "${module.site.project}-${module.site.environment}-keypair"
  ssh_pub_key     = "${module.site.ssh_pub_key}"
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

  tags {
    Name            											= "${module.site.project}"
    Environment     											= "${module.site.environment}"
	 "kubernetes.io/cluster/${module.site.project}" = "shared"
  }                        
}

output "subnet_private" {
  value = "${module.subnet_private.id}"
}

################################################################################

module "route53_zone" {
  source              = "../../terraform_modules/route53_zone_private"

  vpc_id              = "${module.site.aws_vpc_id}"
  vpc_region          = "${data.aws_region.site_region.name}"

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
