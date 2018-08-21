################################################################################

module "ssl_etcd_key" {
  source              = "../../terraform_modules/ssl_private_key"
  rsa_bits            = 4096
}

module "ssl_etcd_csr" {
  source              = "../../terraform_modules/ssl_cert_request"

  private_key_pem     = "${module.ssl_etcd_key.private_key_pem}"

  common_name         = "*.${module.site.region}.compute.internal"
  organization        = "etcd" 
  organizational_unit = "etcd"
  street_address      = [ ]
  locality            = "Amsterdam"
  province            = "Noord-Holland"
  country             = "NL"

  dns_names           = [ "etcd",
                          "etcd.default",
                          "etcd.test",
                          "etcd.default.svc",
                          "localhost",
                          "etcd.${module.site.environment}.${module.site.domain_name}",
                          "*.${module.site.region}.compute.internal",
                          "*.compute.internal",
                          "*.compute.amazonaws.com",
                          "*.elb.amazonaws.com"
                        ]
  ip_addresses          = [
                          "127.0.0.1",
                        ]
}

module "ssl_etcd_crt" {
  source                = "../../terraform_modules/ssl_locally_signed_cert"

  validity_period_hours = "${var.kubernetes["etcd_ssl_valid"]}"

  cert_request_pem      = "${module.ssl_etcd_csr.cert_request_pem}"
  ca_private_key_pem    = "${module.ssl_ca_key.private_key_pem}"
  ca_cert_pem           = "${module.ssl_ca_crt.cert_pem}"
}

resource "null_resource" "ssl_etcd_key" {
  triggers {
    ssl_ca_crt              = "${module.ssl_etcd_key.private_key_pem}"
  }
  provisioner "local-exec" { command = "cat > ../../config/etcd.key <<EOL\n${module.ssl_etcd_key.private_key_pem}\nEOL\n" }
}

resource "null_resource" "ssl_etcd_crt" {
  triggers {
    ssl_ca_crt              = "${module.ssl_etcd_crt.cert_pem}"
  }
  provisioner "local-exec" { command = "cat > ../../config/etcd.crt <<EOL\n${module.ssl_etcd_crt.cert_pem}\nEOL\n" }
}

# #####################################################################################

module "sg_ingress_etcd" {
  source            = "../../terraform_modules/sg_ingress_map"
  sg_name           = "${module.site.project}-${module.site.environment}-ETCD"
  aws_vpc_id        = "${module.site.aws_vpc_id}"

  ingress = [
    {
      from_port     = "${var.ports["etcd_client"]}"
      to_port       = "${var.ports["etcd_client"]}"
      protocol      = "TCP"
      cidr_blocks   = [ "${local.cidr_vpc["region"]}" ]
    },
    {
      from_port     = "${var.ports["etcd_peer"]}"
      to_port       = "${var.ports["etcd_peer"]}"
      protocol      = "TCP"
      cidr_blocks   = [ "${local.cidr_vpc["region"]}" ]
    }    
  ]
}

 # #####################################################################################

data "template_file" "instance-etcd" {
  template                    = "${file("../../02_etcd/terraform/templates/etcd-cloud-config.tpl")}"

  vars {
    etcd_version              = "${var.kubernetes["etcd"]}"
    ssl_etcd_crt              = "${module.ssl_etcd_crt.cert_pem}"
    ssl_etcd_key              = "${module.ssl_etcd_key.private_key_pem}"
    ssl_ca_crt                = "${module.ssl_ca_crt.cert_pem}"
    ##########################################################################
    # This variable is used to determine the ETCD instances by filtering
    ##########################################################################
    EC2value                  = "${module.site.environment}"
  }
}

######################################################################################
# We use the template_cloudinit_config data type because we exceed the 16k user_data
# limit from the template (ssl certificates)
######################################################################################
data "template_cloudinit_config" "etcd" {
  gzip          = true
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content      = "${data.template_file.instance-etcd.rendered}"
  }
}

######################################################################################

module "etcd_launch_configuration" {
  source               = "../../terraform_modules/launch_configuration"
  
  name_prefix          = "etcd-${module.site.project}-${module.site.environment}-"

  image_id             = "${data.aws_ami.ubuntu_ami.id}"
  instance_type        = "${var.instance["etcd"]}"
  iam_instance_profile = "${module.iam_instance_profile.name}"
  #spot_price           = "${var.instance_spot_price["etcd"]}"

  key_name             = "${module.key_pair.ssh_name_key}"

  volume_size          = "20"

  ebs_optimized        = false

  associate_public_ip_address = false

  user_data_base64     = "${data.template_cloudinit_config.etcd.rendered}"
  
  security_groups      = [ "${module.sg_ingress_internal.id}",
                           "${module.sg_ingress_etcd.id}",
                           "${module.sg_ingress_management.id}",
                           "${module.sg_egress.id}" ]
}

data "template_file" "etcd_cloudformation" {
  template              = "${file("../../02_etcd/terraform/templates/etcd-cloudformation.tpl")}"

  vars {
    cluster_name        = "${var.kubernetes["name"]}-${module.site.environment}"
    kubernetes_version  = "${var.kubernetes["k8s"]}"
    environment         = "${module.site.environment}"
    resource_name       = "${var.kubernetes["name"]}${module.site.environment}etcd"
    subnet_ids          = "${join(",", module.subnet_public.id)}"
    launch_name         = "${module.etcd_launch_configuration.name}"
    loadbalancer        = "${module.elb_etcd.name}"
    max_size            = "${var.instance_count["etcd"]}"
    min_size            = "${var.instance_count["etcd_min"]}"
    pause_time          = "PT60S"

    etcd_tag            = "${module.site.environment}"
    etcd_version        = "${var.kubernetes["etcd"]}"
  }
}

module "etcd_cloudformation_stack" {
  source               = "../../terraform_modules/cloudformation_stack"

  name                 = "${module.site.project}${module.site.environment}etcd"
  template_body        = "${data.template_file.etcd_cloudformation.rendered}"
}

# module "instance_etcd" {
#   source                      = "../../terraform_modules/instance"

#   availability_zone           = "${element(data.aws_availability_zones.site_avz.names, 0)}"
  
#   count                       = "${var.instance_count["etcd"]}"

#   tags = {
#     etcd                      = "${module.site.environment}"
#     etcdVersion               = "${var.kubernetes["etcd"]}"
#   }

#   instance_name               = "${var.project["etcd"]}"
#   environment                 = "${module.site.environment}"
#   aws_subnet_id               = "${element(module.subnet_public.id, 0)}"

#   ssh_user                    = "ubuntu"
#   ssh_name_key                = "${module.key_pair.ssh_name_key}"
#   ssh_pri_key                 = "${module.site.ssh_pri_key}"

#   region                      = "${module.site.region}"

#   aws_ami                     = "${data.aws_ami.ubuntu_ami.id}"

#   iam_instance_profile        = "${module.iam_instance_profile.name}"

#   root_block_device_size      = "20"

#   security_groups_ids         = [ "${module.sg_ingress_internal.id}",
#                                   "${module.sg_ingress_etcd.id}",
#                                   "${module.sg_ingress_management.id}",
#                                   "${module.sg_egress.id}" ]

#   aws_instance_type           = "${var.instance["etcd"]}"
#   associate_public_ip_address = true

#   user_data_base64            = "${data.template_cloudinit_config.etcd.rendered}"
# }

# output "etcd_public_ip" {
#   value = "${module.instance_etcd.public_ip}"
# }

# output "etcd_private_ip" {
#   value = "${module.instance_etcd.private_ip}"
# }

# output "etcd_public_dns" {
#   value = "${module.instance_etcd.public_dns}"
# }

# #####################################################################################

module "elb_etcd" {
  source                  = "../../terraform_modules/elb_map_asg"
  project                 = "${module.site.project}"
  environment             = "${module.site.environment}"

  name                    = "ELB-${var.project["etcd"]}"

  tags = {
    Name                  = "ELB-${var.project["etcd"]}"
  }

  internal                = true

  subnet_ids              = [ "${module.subnet_public.id}" ]
  security_group_ids      = [ "${module.sg_ingress_etcd.id}" ,
                              "${module.sg_egress.id}"]

  #instances               = [ "${module.instance_etcd.id}" ]

  listener = [
    {
      instance_port       = "${var.ports["etcd_client"]}"
      instance_protocol   = "TCP"
      lb_port             = "${var.ports["etcd_client"]}"
      #lb_protocol         = "HTTP"
      lb_protocol         = "TCP"
      #ssl_certificate_id  = "${var.ssl_arn}"
    },
    {
      instance_port       = "${var.ports["etcd_peer"]}"
      instance_protocol   = "TCP"
      lb_port             = "${var.ports["etcd_peer"]}"
      #lb_protocol         = "HTTP"
      lb_protocol         = "TCP"
      #ssl_certificate_id  = "${var.ssl_arn}"
    }
  ]

  health_check = [
    { 
      healthy_threshold   = 2
      unhealthy_threshold = 2
      timeout             = 3
      target              = "TCP:${var.ports["etcd_client"]}"
      interval            = 15
    }
  ]
}

output "elb-etcd" {
  value = "${module.elb_etcd.dns_name}"
}

# #####################################################################################

module "route53_record_etcd" {
  source              = "../../terraform_modules/route53_record"

  type                = "CNAME"
  zone_id             = "${module.route53_zone.id}"
  name                = "etcd.${module.site.environment}.${module.site.domain_name}"
  records             = [ "${module.elb_etcd.dns_name}" ]
}
