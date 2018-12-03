# ##############################################################################################

module "ssl_kubelet_key" {
  source              = "../../terraform_modules/ssl_private_key"
  rsa_bits            = 4096
}

module "ssl_kubelet_csr" {
  source              = "../../terraform_modules/ssl_cert_request"

  private_key_pem     = "${module.ssl_kubelet_key.private_key_pem}"

  common_name         = "kubelet"
  organization        = "node" 
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
                          "${lookup(local.kubernetes_private, "api.0")}",
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
                          "${lookup(local.kubernetes_private, "api.0")}"
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

  #####################################################################################
  #Disable this line if on-demand instances are needed / to be used
  #####################################################################################
  spot_price           = "${var.instance_spot_price["kubelet"]}"

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
    kubernetes_version  = "${var.kubernetes["k8s"]}"
    environment         = "${module.site.environment}"
    resource_name       = "${var.kubernetes["name"]}${module.site.environment}kubelet"
    subnet_ids          = "${join(",", module.subnet_private.id)}"
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

    service_ip            = "${lookup(local.kubernetes_private, "api.0")}"
    service_ip_range      = "${lookup(local.cidr_private, "avz.0")}"
    cluster_dns           = "${lookup(local.kubernetes_private, "dns.0")}"
    cluster_domain        = "${var.kubernetes["cluster_domain"]}"

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

    environment           = "${module.site.environment}"
    cluster_name          = "${var.kubernetes["name"]}-${module.site.environment}"
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

# ##############################################################################################
# # Here we add the kublet user (used in o=node/cn=user SSL certificate) to clusterRoles:
# # - system:node
# # - system:node-proxier
# ##############################################################################################

data "template_file" "kubelet-rolebindings" {
  template             = "${file("../../04_kubelet/terraform/templates/roleBindings.tpl")}"
}

resource "null_resource" "wait_for_kubeapi" {
  provisioner "local-exec" { command = "while [ $(kubectl cluster-info > /dev/null 2>&1; echo $?) -ne 0 ]; do sleep 10; done" }

  ############################################################################################
  # We wait untill kubectl is downloaded
  ############################################################################################
  triggers {
    provisioner = "${null_resource.kubectl.id}"
  }
}

resource "null_resource" "kubelet-rolebindings-apply" {

  provisioner "local-exec" { command = "kubectl --kubeconfig ../../config/kubeconfig apply -f - <<EOL\n${data.template_file.kubelet-rolebindings.rendered}\nEOL\n" }
  # kubectl create clusterrolebinding kubelet --clusterrole=system:node --user=kubelet
  # kubectl create clusterrolebinding kubelet-proxy --clusterrole=system:node-proxier --user=kubelet
  triggers = {
    provisioner = "${null_resource.wait_for_kubeapi.id}"
  }
}
