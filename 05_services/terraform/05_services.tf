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

module "s3_docker_registry" {
  source                     = "../../terraform_modules/s3/"

  bucket                     = "${module.site.project}-${module.site.environment}-registry"
  s3_policy                  = "${data.aws_iam_policy_document.s3default.json}"

  project                    = "${module.site.project}"
  environment                = "${module.site.environment}"
}

output "s3_docker_registry_arn" {
  value = "${module.s3_docker_registry.arn}"
}

# ####################################################################

data "template_file" "k8s_namespaces" {
  template             = "${file("../../deploy/templates/00_namespaces.tpl")}"
}

data "template_file" "k8s_secrets" {
  template             = "${file("../../deploy/templates/00_secrets.tpl")}"

  vars {
    aws_region         = "${base64encode("${var.aws_region}")}"
    aws_access         = "${base64encode("${var.aws_access}")}"
    aws_secret         = "${base64encode("${var.aws_secret}")}"
  }
}

data "template_file" "k8s_storageclass" {
  template             = "${file("../../deploy/templates/00_storageclass.tpl")}"
}

data "template_file" "k8s_kubedns" {
  template             = "${file("../../deploy/templates/01_kubeDNS.tpl")}"

  vars {
    cluster_ip_dns        = "${lookup(local.kubernetes_public, "dns.0")}"
    kubedns_version       = "${var.kubernetes["kubedns"]}"
    kubedns_domain        = "${var.kubernetes["cluster_domain"]}"
    kubednsmaq_version    = "${var.kubernetes["kubednsmasq"]}"
    exechealthz_version   = "${var.kubernetes["exechealthz"]}"
  }
}

data "template_file" "k8s_coredns" {
  template             = "${file("../../deploy/templates/01_coreDNS.tpl")}"

  vars {
    cluster_ip_dns        = "${lookup(local.kubernetes_public, "dns.0")}"
    coredns_version       = "${var.kubernetes["coredns"]}"
    kubedns_domain        = "${var.kubernetes["cluster_domain"]}"
  }
}

data "template_file" "k8s_busybox" {
  template             = "${file("../../deploy/templates/01_busybox.tpl")}"
}

data "template_file" "k8s_dashboard" {
  template             = "${file("../../deploy/templates/02_dashboard.tpl")}"

  vars {
    dashboard_version  = "${var.kubernetes["dashboard"]}"
  }
}

data "template_file" "k8s_heapster" {
  template             = "${file("../../deploy/templates/03_heapster.tpl")}"

  vars {
    cluster_domain     = "${var.kubernetes["cluster_domain"]}"
  }
}

data "template_file" "k8s_influxdb" {
  template             = "${file("../../deploy/templates/03_influxdb.tpl")}"
}

data "template_file" "k8s_state-metrics" {
  template             = "${file("../../deploy/templates/05_kube-state-metrics.tpl")}"

  vars {
    statemetrics_version = "${var.kubernetes["state-metrics"]}"
    addonresizer-version = "${var.kubernetes["addon-resizer"]}"
  }
}

data "template_file" "k8s_ingress" {
  template             = "${file("../../deploy/templates/06_ingress_backend.tpl")}"

  vars {
    namespace          = "${var.kubernetes["namespace_demo"]}"
  }
}

data "template_file" "k8s_ingress_demo" {
  template             = "${file("../../deploy/templates/06_ingress_demo.tpl")}"

  vars {
    namespace          = "${var.kubernetes["namespace_demo"]}"
  }
}

data "template_file" "k8s_docker-registry" {
  template             = "${file("../../deploy/templates/10_docker-registry.tpl")}"

  vars {
    registry_s3_bucket = "${module.s3_docker_registry.bucket}"
    kubeproxy_version  = "${var.kubernetes["proxy"]}"
  }
}

resource "null_resource" "k8s_services" {
  ###############################################################################
  # For regenaration use $terraform taint null_resource.k8s_services
  ###############################################################################
  # Any change to UUID (every apply) triggers re-provisioning
  # triggers {
  #   #filename = "test-${uuid()}"
  #   elb_controller_dns_name = "${module.elb_kubeapi_internal.dns_name}"
  # }
  provisioner "local-exec" { command = "curl -L -o /usr/bin/kubectl https://storage.googleapis.com/kubernetes-release/release/${var.kubernetes["k8s"]}/bin/linux/amd64/kubectl" }
  provisioner "local-exec" { command = "chmod 755 /usr/bin/kubectl" }
  provisioner "local-exec" { command = "curl -L -o ../../deploy/k8s/00_weavenet.yaml 'https://cloud.weave.works/k8s/net?k8s-version=${var.kubernetes["k8s"]}'" }
  provisioner "local-exec" { command = "cat > ../../deploy/k8s/00_namespaces.yaml <<EOL\n${data.template_file.k8s_namespaces.rendered}\nEOL\n" }
  provisioner "local-exec" { command = "cat > ../../deploy/k8s/00_secrets.yaml <<EOL\n${data.template_file.k8s_secrets.rendered}\nEOL\n" }
  provisioner "local-exec" { command = "cat > ../../deploy/k8s/00_storageclass.yaml <<EOL\n${data.template_file.k8s_storageclass.rendered}\nEOL\n" }
  provisioner "local-exec" { command = "cat > ../../deploy/k8s/01_kubeDNS.yaml <<EOL\n${data.template_file.k8s_kubedns.rendered}\nEOL\n" }
  provisioner "local-exec" { command = "cat > ../../deploy/k8s/01_coreDNS.yaml <<EOL\n${data.template_file.k8s_coredns.rendered}\nEOL\n" }
  provisioner "local-exec" { command = "cat > ../../deploy/k8s/01_busybox.yaml <<EOL\n${data.template_file.k8s_busybox.rendered}\nEOL\n" }
  provisioner "local-exec" { command = "cat > ../../deploy/k8s/03_heapster.yaml <<EOL\n${data.template_file.k8s_heapster.rendered}\nEOL\n" }
  provisioner "local-exec" { command = "cat > ../../deploy/k8s/03_influxdb.yaml <<EOL\n${data.template_file.k8s_influxdb.rendered}\nEOL\n" }
  provisioner "local-exec" { command = "cat > ../../deploy/k8s/02_dashboard.yaml <<EOL\n${data.template_file.k8s_dashboard.rendered}\nEOL\n" }
  provisioner "local-exec" { command = "cat > ../../deploy/k8s/05_kube-state-metrics.yaml <<EOL\n${data.template_file.k8s_state-metrics.rendered}\nEOL\n" }
  provisioner "local-exec" { command = "cat > ../../deploy/k8s/06_ingress_backend.yaml <<EOL\n${data.template_file.k8s_ingress.rendered}\nEOL\n" }
  provisioner "local-exec" { command = "cat > ../../deploy/k8s/06_ingress_demo.yaml <<EOL\n${data.template_file.k8s_ingress_demo.rendered}\nEOL\n" }
  provisioner "local-exec" { command = "cat > ../../deploy/k8s/10_docker-registry.yaml <<EOL\n${data.template_file.k8s_docker-registry.rendered}\nEOL\n" }
}

resource "null_resource" "k8s_cni" {
  ################################################################################
  # In order for Kubernetes to work properly we need to deploy the overlany / cni
  # network. In this repo we chose for Weavenet.
  # We also depend on kubectl (we expect it to be avialable within your path)
  ################################################################################
  provisioner "local-exec" { command = "kubectl --kubeconfig ../../config/kubeconfig create -f ../../deploy/k8s/00_weavenet.yaml; true" }
  provisioner "local-exec" { command = "kubectl --kubeconfig ../../config/kubeconfig create -f ../../deploy/k8s/00_namespaces.yaml; true" }
  provisioner "local-exec" { command = "kubectl --kubeconfig ../../config/kubeconfig create -f ../../deploy/k8s/00_storageclass.yaml; true" }
  provisioner "local-exec" { command = "kubectl --kubeconfig ../../config/kubeconfig create -f ../../deploy/k8s/00_secrets.yaml; true" }
  provisioner "local-exec" { command = "kubectl --kubeconfig ../../config/kubeconfig create -f ../../deploy/k8s/01_coreDNS.yaml; true" }
  provisioner "local-exec" { command = "kubectl --kubeconfig ../../config/kubeconfig create -f ../../deploy/k8s/02_dashboard.yaml; true" }

  triggers = {
    provisioner = "${null_resource.k8s_services.id}"
  }
}