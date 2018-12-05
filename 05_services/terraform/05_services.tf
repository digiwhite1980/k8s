# ####################################################################

data "aws_iam_policy_document" "s3default" {
  statement {
    sid             = "1"

    effect          = "Allow"

    actions         = [ "s3:ListBucket",
                        "s3:GetBucketLocation",
                        "s3:ListBucketMultipartUploads",
                        "s3:PutObject",
                        "s3:GetObject",
                        "s3:DeleteObject",
                        "s3:ListMultipartUploadParts",
                        "s3:AbortMultipartUpload" ]
    principals {
      type          = "AWS"
      identifiers   = [ "${data.aws_caller_identity.main.arn}" ]
    }
    resources       = [ "arn:aws:s3:::${lower(module.site.project)}-${lower(module.site.environment)}-registry",
                        "arn:aws:s3:::${lower(module.site.project)}-${lower(module.site.environment)}-registry/*" ]
  }
}

# ####################################################################

module "ssl_docker_registry_key" {
  source              = "../../terraform_modules/ssl_private_key"
  rsa_bits            = 4096
}

module "ssl_docker_registry_csr" {
  source              = "../../terraform_modules/ssl_cert_request"

  private_key_pem     = "${module.ssl_docker_registry_key.private_key_pem}"

  common_name         = "*"
  organization        = "Docker registry" 
  organizational_unit = "${module.site.project} - ${module.site.environment}"
  street_address      = [ ]
  locality            = "Amsterdam"
  province            = "Noord-Holland"
  country             = "NL"

  dns_names           = [ "docker-registry",
                          "docker-registry.${module.site.environment}",
                          "docker-registry.${module.site.environment}.svc",
                          "docker-registry.${module.site.environment}.svc.${var.kubernetes["cluster_domain"]}",
                          "registry",
                          "registry.${module.site.environment}",
                          "registry.${module.site.environment}.${module.site.domain_name}",
                          "127.0.0.1",
                          "localhost",
                          "*.${module.site.domain_name}",
                          "${var.kubernetes["name"]}",
                          "*.${var.aws_region}.elb.amazonaws.com"
                        ]
  ip_addresses          = [ "127.0.0.1" ]
}

module "ssl_docker_registry_crt" {
  source                = "../../terraform_modules/ssl_locally_signed_cert"

  cert_request_pem      = "${module.ssl_docker_registry_csr.cert_request_pem}"
  ca_private_key_pem    = "${module.ssl_ca_key.private_key_pem}"
  ca_cert_pem           = "${module.ssl_ca_crt.cert_pem}"

  validity_period_hours = "${var.kubernetes["kubeapi_ssl_valid"]}"

  allowed_uses = [
    "key_encipherment",
    "server_auth",
    "client_auth",
  ]
}

resource "null_resource" "ssl_docker_registry_key" {
  triggers {
    ssl_ca_crt              = "${module.ssl_docker_registry_key.private_key_pem}"
  }
  provisioner "local-exec" { command = "cat > ../../config/docker-registry.key <<EOL\n${module.ssl_docker_registry_key.private_key_pem}\nEOL\n" }
}

resource "null_resource" "ssl_docker_registry_crt" {
  triggers {
    ssl_ca_crt              = "${module.ssl_docker_registry_crt.cert_pem}"
  }
  provisioner "local-exec" { command = "cat > ../../config/docker-registry.crt <<EOL\n${module.ssl_docker_registry_crt.cert_pem}\nEOL\n" }
}

# ####################################################################

data "template_file" "k8s_namespaces" {
  template             = "${file("../../05_services/terraform/templates/00_namespaces.tpl")}"

  vars {
    environment        = "${module.site.environment}"
  }
}

data "template_file" "k8s_secrets" {
  template             = "${file("templates/00_secrets.tpl")}"

  vars {
    namespace          = "${module.site.environment}"
    aws_region         = "${base64encode("${var.aws_region}")}"
    aws_access         = "${base64encode("${var.aws_access}")}"
    aws_secret         = "${base64encode("${var.aws_secret}")}"
    docker-registry-key= "${base64encode("${module.ssl_docker_registry_key.private_key_pem}")}"
    docker-registry-crt= "${base64encode("${module.ssl_docker_registry_crt.cert_pem}")}"
    ca-cert            = "${base64encode("${module.ssl_ca_crt.cert_pem}")}"
    client-cert        = "${base64encode("${module.ssl_kubelet_crt.cert_pem}")}"
    kubeconfig         = "${base64encode("${data.template_file.kubeconfig.rendered}")}"
  }
}

data "template_file" "k8s_storageclass" {
  template             = "${file("../../05_services/terraform/templates/00_storageclass.tpl")}"

  vars {
    hdd_class          = "${var.kubernetes["storage_hdd"]}"
    ssd_class          = "${var.kubernetes["storage_ssd"]}"
  }
}

data "template_file" "k8s_kubedns" {
  template             = "${file("../../05_services/terraform/templates/01_kubeDNS.tpl")}"

  vars {
    cluster_ip_dns        = "${lookup(local.kubernetes_private, "dns.0")}"
    kubedns_version       = "${var.kubernetes["kubedns"]}"
    kubedns_domain        = "${var.kubernetes["cluster_domain"]}"
    kubednsmaq_version    = "${var.kubernetes["kubednsmasq"]}"
    exechealthz_version   = "${var.kubernetes["exechealthz"]}"
  }
}

data "template_file" "k8s_coredns" {
  template             = "${file("../../05_services/terraform/templates/01_coreDNS.tpl")}"

  vars {
    cluster_ip_dns        = "${lookup(local.kubernetes_private, "dns.0")}"
    coredns_version       = "${var.kubernetes["coredns"]}"
    kubedns_domain        = "${var.kubernetes["cluster_domain"]}"
    route53_domain        = "${module.site.environment}.${var.domainname}"
    route53_zoneid        = "${module.route53_zone.id}"
  }
}

data "template_file" "k8s_busybox" {
  template                = "${file("../../05_services/terraform/templates/01_busybox.tpl")}"

  vars {
    namespace             = "${module.site.environment}"
  }
}

data "template_file" "k8s_alpine" {
  template             = "${file("../../05_services/terraform/templates/01_alpine.tpl")}"
}

data "template_file" "k8s_dashboard" {
  template             = "${file("../../05_services/terraform/templates/02_dashboard.tpl")}"

  vars {
    namespace          = "${var.kubernetes["namespace_sys"]}"
    dashboard_version  = "${var.kubernetes["dashboard"]}"
  }
}

data "template_file" "k8s_heapster" {
  template             = "${file("../../05_services/terraform/templates/03_heapster.tpl")}"

  vars {
    namespace          = "${var.kubernetes["namespace_sys"]}"
    cluster_domain     = "${var.kubernetes["cluster_domain"]}"
  }
}

data "template_file" "k8s_influxdb" {
  template             = "${file("../../05_services/terraform/templates/03_influxdb.tpl")}"
}

data "template_file" "k8s_state-metrics" {
  template             = "${file("../../05_services/terraform/templates/05_kube-state-metrics.tpl")}"

  vars {
    statemetrics_version = "${var.kubernetes["state-metrics"]}"
    addonresizer-version = "${var.kubernetes["addon-resizer"]}"
  }
}

data "template_file" "k8s_ingress" {
  template             = "${file("../../05_services/terraform/templates/06_ingress_backend.tpl")}"

  vars {
    namespace          = "${module.site.environment}"
  }
}

data "template_file" "k8s_ingress_demo" {
  template             = "${file("../../05_services/terraform/templates/06_ingress_demo.tpl")}"

  vars {
    domainname         = "${module.site.domain_name}"
    namespace          = "${module.site.environment}"
  }
}

#############################################################################################
module "s3_docker_registry" {
  source                     = "../../terraform_modules/s3/"

  bucket                     = "${module.site.project}-${module.site.environment}-registry"
  s3_policy                  = "${data.aws_iam_policy_document.s3default.json}"

  force_destroy              = "true"

  project                    = "${module.site.project}"
  environment                = "${module.site.environment}"
}

output "s3_docker_registry_arn" {
  value = "${module.s3_docker_registry.arn}"
}

data "template_file" "k8s_docker-registry" {
  template             = "${file("../../05_services/terraform/templates/10_docker-registry.tpl")}"

  vars {
    namespace             = "${module.site.environment}"
    registry_s3_bucket    = "${module.s3_docker_registry.bucket}"
    kubeproxy_version     = "${var.kubernetes["proxy"]}"
    registry_version      = "${var.kubernetes["docker_registry_version"]}"
    kubernetes_domain     = "${var.kubernetes["cluster_domain"]}"
    loadbalancer_ip       = "${lookup(local.kubernetes_private, "registry.0")}"
  }
}

module "route53_record_docker_registry" {
  source              = "../../terraform_modules/route53_record"

  type                = "A"
  zone_id             = "${module.route53_zone.id}"
  name                = "registry.${module.site.environment}.${module.site.domain_name}"
  records             = [ "${lookup(local.kubernetes_private, "registry.0")}" ]
}

#############################################################################################

resource "null_resource" "k8s_services" {
  ###############################################################################
  # For regenaration use $terraform taint null_resource.k8s_services
  ###############################################################################
  # Any change to UUID (every apply) triggers re-provisioning
  # triggers {
  #   #filename = "test-${uuid()}"
  #   elb_controller_dns_name = "${module.elb_kubeapi_internal.dns_name}"
  # }
  provisioner "local-exec" { command = "kubectl config set-context ${module.site.environment}-${var.kubernetes["name"]} --namespace=${module.site.environment}" }
  provisioner "local-exec" { command = "curl -L -o ../../deploy/00_weavenet.yaml 'https://cloud.weave.works/k8s/net?k8s-version=${var.kubernetes["k8s"]}'" }
  provisioner "local-exec" { command = "curl -L -o /usr/bin/linkerd https://github.com/linkerd/linkerd2/releases/download/stable-${var.kubernetes["linkerd"]}/linkerd2-cli-stable-${var.kubernetes["linkerd"]}-linux" }
  provisioner "local-exec" { command = "cat > ../../deploy/00_namespaces.yaml <<EOL\n${data.template_file.k8s_namespaces.rendered}\nEOL\n" }
  provisioner "local-exec" { command = "cat > ../../deploy/00_secrets.yaml <<EOL\n${data.template_file.k8s_secrets.rendered}\nEOL\n" }
  provisioner "local-exec" { command = "cat > ../../deploy/00_storageclass.yaml <<EOL\n${data.template_file.k8s_storageclass.rendered}\nEOL\n" }
  provisioner "local-exec" { command = "cat > ../../deploy/01_kubeDNS.yaml <<EOL\n${data.template_file.k8s_kubedns.rendered}\nEOL\n" }
  provisioner "local-exec" { command = "cat > ../../deploy/01_coreDNS.yaml <<EOL\n${data.template_file.k8s_coredns.rendered}\nEOL\n" }
  provisioner "local-exec" { command = "cat > ../../deploy/01_busybox.yaml <<EOL\n${data.template_file.k8s_busybox.rendered}\nEOL\n" }
  provisioner "local-exec" { command = "cat > ../../deploy/01_alpine.yaml <<EOL\n${data.template_file.k8s_alpine.rendered}\nEOL\n" }
  provisioner "local-exec" { command = "cat > ../../deploy/02_dashboard.yaml <<EOL\n${data.template_file.k8s_dashboard.rendered}\nEOL\n" }
  provisioner "local-exec" { command = "cat > ../../deploy/03_heapster.yaml <<EOL\n${data.template_file.k8s_heapster.rendered}\nEOL\n" }
  provisioner "local-exec" { command = "cat > ../../deploy/03_influxdb.yaml <<EOL\n${data.template_file.k8s_influxdb.rendered}\nEOL\n" }
  provisioner "local-exec" { command = "cat > ../../deploy/05_kube-state-metrics.yaml <<EOL\n${data.template_file.k8s_state-metrics.rendered}\nEOL\n" }
  provisioner "local-exec" { command = "cat > ../../deploy/06_ingress_backend.yaml <<EOL\n${data.template_file.k8s_ingress.rendered}\nEOL\n" }
  provisioner "local-exec" { command = "cat > ../../deploy/06_ingress_demo.yaml <<EOL\n${data.template_file.k8s_ingress_demo.rendered}\nEOL\n" }
  provisioner "local-exec" { command = "cat > ../../deploy/10_docker-registry.yaml <<EOL\n${data.template_file.k8s_docker-registry.rendered}\nEOL\n" }
}

resource "null_resource" "k8s_context" {
  provisioner "local-exec" { command = "kubectl config set-context ${module.site.environment}-${var.kubernetes["name"]} --namespace=${module.site.environment}" }
}

resource "null_resource" "k8s_cni" {
  ################################################################################
  # In order for Kubernetes to work properly we need to deploy the overlany / cni
  # network. In this repo we chose for Weavenet.
  # We also depend on kubectl (we expect it to be avialable within your path)
  ################################################################################
  provisioner "local-exec" { command = "kubectl --kubeconfig ../../config/kubeconfig apply -f ../../deploy/00_namespaces.yaml; true" }
  provisioner "local-exec" { command = "kubectl --kubeconfig ../../config/kubeconfig apply -f ../../deploy/00_weavenet.yaml; true" }
  provisioner "local-exec" { command = "kubectl --kubeconfig ../../config/kubeconfig apply -f ../../deploy/00_secrets.yaml; true" }
  provisioner "local-exec" { command = "kubectl --kubeconfig ../../config/kubeconfig apply -f ../../deploy/00_storageclass.yaml; true" }
  provisioner "local-exec" { command = "kubectl --kubeconfig ../../config/kubeconfig apply -f ../../deploy/01_coreDNS.yaml; true" }
  provisioner "local-exec" { command = "kubectl --kubeconfig ../../config/kubeconfig apply -f ../../deploy/02_dashboard.yaml; true" }
  provisioner "local-exec" { command = "kubectl --kubeconfig ../../config/kubeconfig apply -f ../../deploy/10_docker-registry.yaml; true" }

  triggers = {
    provisioner = "${null_resource.k8s_services.id}"
  }
}