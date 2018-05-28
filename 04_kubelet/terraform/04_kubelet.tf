# ##############################################################################################

module "ssl_kubelet_key" {
  source              = "../../terraform_modules/ssl_private_key"
  rsa_bits            = 4096
}

module "ssl_kubelet_csr" {
  source              = "../../terraform_modules/ssl_cert_request"

  private_key_pem     = "${module.ssl_kubelet_key.private_key_pem}"

  common_name         = "*"
  organization        = "${module.site.project}" 
  organizational_unit = "${module.site.project} - ${module.site.environment}"
  street_address      = [ ]
  locality            = "Amsterdam"
  province            = "Noord-Holland"
  country             = "NL"

  dns_names           = [ "kubernetes",
                          "kubernetes.default",
                          "kubernetes.default.svc",
                          "kubernetes.default.svc.cluster.local",
                          "127.0.0.1",
                          "${var.kubernetes["service_ip"]}",
                          "*.${module.site.region}.compute.internal",                          
                          "*.compute.internal",
                          "*.compute.amazonaws.com",
                          "*.elb.amazonaws.com",
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
                          "${var.kubernetes["service_ip"]}"
  ]
}

module "ssl_kubelet_crt" {
  source                = "../../terraform_modules/ssl_locally_signed_cert"

  validity_period_hours = "${var.kubernetes["kubelet_ssl_valid"]}"

  cert_request_pem      = "${module.ssl_kubelet_csr.cert_request_pem}"
  ca_private_key_pem    = "${module.ssl_ca_key.private_key_pem}"
  ca_cert_pem           = "${module.ssl_ca_crt.cert_pem}"
}

##############################################################################################

module "ssl_kubelet_crt_24" {
  source                = "../../terraform_modules/ssl_locally_signed_cert"

  validity_period_hours = "24"

  cert_request_pem      = "${module.ssl_kubelet_csr.cert_request_pem}"
  ca_private_key_pem    = "${module.ssl_ca_key.private_key_pem}"
  ca_cert_pem           = "${module.ssl_ca_crt.cert_pem}"
}

resource "null_resource" "ssl_kubelet_crt_24" {
  triggers {
    ssl_ca_crt              = "${module.ssl_kubelet_crt.cert_pem}"
  }
  provisioner "local-exec" { command = "cat > ../../config/kubelet_24.crt <<EOL\n${module.ssl_kubelet_crt_24.cert_pem}\nEOL\n" }
}

module "ssl_kubeapi_crt_24" {
  source                = "../../terraform_modules/ssl_locally_signed_cert"

  validity_period_hours = "24"

  cert_request_pem      = "${module.ssl_kubeapi_csr.cert_request_pem}"
  ca_private_key_pem    = "${module.ssl_ca_key.private_key_pem}"
  ca_cert_pem           = "${module.ssl_ca_crt.cert_pem}"
}

resource "null_resource" "ssl_kubeapi_crt_24" {
  triggers {
    ssl_ca_crt              = "${module.ssl_kubeapi_crt.cert_pem}"
  }
  provisioner "local-exec" { command = "cat > ../../config/kubeapi_24.crt <<EOL\n${module.ssl_kubeapi_crt_24.cert_pem}\nEOL\n" }
}
##############################################################################################

resource "null_resource" "ssl_kubelet_key" {
  triggers {
    ssl_ca_crt              = "${module.ssl_kubelet_key.private_key_pem}"
  }
  provisioner "local-exec" { command = "cat > ../../config/kubelet.key <<EOL\n${module.ssl_kubelet_key.private_key_pem}\nEOL\n" }
}

resource "null_resource" "ssl_kubelet_crt" {
  triggers {
    ssl_ca_crt              = "${module.ssl_kubelet_crt.cert_pem}"
  }
  provisioner "local-exec" { command = "cat > ../../config/kubelet.crt <<EOL\n${module.ssl_kubelet_crt.cert_pem}\nEOL\n" }
}

# ##############################################################################################

module "kubelet_launch_configuration" {
  source               = "../../terraform_modules/launch_configuration"
  
  name_prefix          = "kubelet-${module.site.project}-${module.site.environment}-"

  image_id             = "${data.aws_ami.ubuntu_ami.id}"
  instance_type        = "${var.instance["kubelet"]}"
  iam_instance_profile = "${module.iam_instance_profile.name}"
  spot_price           = "${var.instance_sport_price["kubelet"]}"

  key_name             = "${module.key_pair.ssh_name_key}"

  volume_size          = "20"

  ebs_optimized        = false

  associate_public_ip_address = true

  user_data_base64     = "${data.template_cloudinit_config.instance-kubelet.rendered}"
  
  security_groups      = [ "${module.sg_gress_kubernetes.id}" ]
}

data "template_file" "kubelet_cloudformation" {
  template              = "${file("../../04_kubelet/terraform/templates/kubelet-cloudformation.tpl")}"

  vars {
    cluster_name        = "${var.kubernetes["name"]}-${module.site.environment}"
    environment         = "${module.site.environment}"
    resource_name       = "${var.kubernetes["name"]}${module.site.environment}kubelet"
    subnet_ids          = "${join(",", module.subnet_public.id)}"
    launch_name         = "${module.kubelet_launch_configuration.name}"
    max_size            = "${var.instance_count["kubelet"]}"
    min_size            = "${var.instance_count["kubelet_min"]}"
    pause_time          = "PT60S"
  }
}

module "kubelet_cloudformation_stack" {
  source               = "../../terraform_modules/cloudformation_stack"

  name                 = "${module.site.project}${module.site.environment}kubelet"
  template_body        = "${data.template_file.kubelet_cloudformation.rendered}"
}

# ##############################################################################################

data "template_file" "instance-kubelet" {
  template             = "${file("../../04_kubelet/terraform/templates/kubelet-cloud-config.tpl")}"

  vars {
    kubernetes_version    = "${var.kubernetes["k8s"]}"

    service_ip            = "${var.kubernetes["service_ip"]}"
    service_ip_range      = "${var.kubernetes["service_ip_range"]}"
    cluster_dns           = "${var.kubernetes["cluster_dns"]}"
    cluster_domain        = "${module.site.domain_name}"

    docker_port           = "${var.ports["docker"]}"
    etcd_endpoint         = "https://${module.route53_record_etcd.fqdn}:2379"
    instance_group        = "${module.site.environment}.${module.site.domain_name}"
    kubeapi_elb           = "https://${module.route53_record_kubeapi.fqdn}"

    cni_plugin_version    = "${var.kubernetes["cni_plugins"]}"

    ssl_kubelet_key       = "${module.ssl_kubelet_key.private_key_pem}"
    ssl_kubelet_crt       = "${module.ssl_kubelet_crt.cert_pem}"
    ssl_ca_crt            = "${module.ssl_ca_crt.cert_pem}"

    ssl_etcd_key          = "${module.ssl_etcd_key.private_key_pem}"
    ssl_etcd_crt          = "${module.ssl_etcd_crt.cert_pem}"
  }
}

data "template_cloudinit_config" "instance-kubelet" {
  gzip          = true
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content      = "${data.template_file.instance-kubelet.rendered}"
  }
}

# ####################################################################

# module "instance_kubelet" {
#   source                      = "../../terraform_modules/instance_spot"

#   availability_zone           = "${element(data.aws_availability_zones.site_avz.names, 0)}"
  
#   count                       = "${var.instance_count["kubelet"]}"

#   ###########################################################################################
#   # Keep in mind that spot instances dont support Tags unless they are created through 
#   # cloudformation / launch configuration.
#   # Prefferably you would like to use the launc configuration aproach
#   ###########################################################################################
#   tags = {
#     kubelet                   = true
#     KubernetesCluster         = "${var.kubernetes["name"]}-${module.site.environment}"
#   }
#   ###########################################################################################
  
#   instance_name               = "${var.project["kubelet"]}"
#   environment                 = "${module.site.environment}"
#   aws_subnet_id               = "${element(module.subnet_public.id, 0)}"

#   ssh_user                    = "ubuntu"
#   ssh_name_key                = "${module.key_pair.ssh_name_key}"
#   ssh_pri_key                 = "${module.site.ssh_pri_key}"

#   region                      = "${module.site.region}"

#   aws_ami                     = "${data.aws_ami.ubuntu_ami.id}"

#   iam_instance_profile        = "${module.iam_instance_profile.name}"

#   root_block_device_size      = "20"

#   spot_price                  = "1.0"
#   wait_for_fulfillment        = true

#   security_groups_ids         = [ "${module.sg_ingress_internal.id}",
#                                   "${module.sg_ingress_management.id}",
#                                   "${module.sg_ingress_external.id}",
#                                   "${module.sg_egress.id}" ]

#   aws_instance_type           = "${var.instance["kubelet"]}"
#   associate_public_ip_address = true

#   user_data_base64            = "${data.template_cloudinit_config.instance-kubelet.rendered}"
# }

# output "kubelet_public_ip" {
#   value = "${module.instance_kubelet.public_ip}"
# }

# output "kubelet_private_ip" {
#   value = "${module.instance_kubelet.private_ip}"
# }

# output "kubelet_public_dns" {
#   value = "${module.instance_kubelet.public_dns}"
# }