###################################################################################3
# EFS 
###################################################################################3
# module "efs_generic" {
#   source                     = "../../terraform_modules/efs"

#   project                    = "${module.site.project}"
#   environment                = "${module.site.environment}"
# }

# module "efs_target_generic" {
#   source              = "../../terraform_modules/efs_target"

#   mount_count         = 2
#   file_system_id      = "${module.efs_generic.id}"
  
#   subnet_ids          = "${module.subnet_public.id}"
#   security_groups     = [ "${module.sg_ingress_internal.id}" ,
#                           "${module.sg_egress.id}" ]
# }

# output "efs_target_generic" {
#   value = "${module.efs_target_generic.id}"
# }

# module "route53_record_efs" {
#   source              = "../../terraform_modules/route53_record"

#   type                = "CNAME"
#   zone_id             = "${module.route53_zone.id}"
#   name                = "efs.${module.site.environment}.${module.site.domain_name}"
#   records             = [ "${module.efs_target_generic.dns_name}" ]
# }

# data "template_file" "custom_efs" {
#   template             = "${file("deploy/autotrack-efs.tpl")}"

#   vars {
#     filesystem_id      = "${module.efs_generic.id}"
#     region             = "${var.aws_region}"
#     ##################################################################
#     # We cannot use a generic DNS name because efs-provisioner 
#     # constructs the url to mount
#     # server             = "${module.route53_record_efs.fqdn}"
#     ##################################################################
#     server             = "${module.route53_record_efs.fqdn}"
#     domain             = "${module.site.environment}.${var.domainname}"
#     namespace          = "${module.site.environment}"
#   }
# }
###################################################################################3

data "template_file" "custom_ingress" {
  template             = "${file("../../deploy/templates/06_ingress_backend.tpl")}"

  vars {
    namespace          = "${module.site.environment}"
  }
}

data "template_file" "custom_secrets" {
  template             = "${file("deploy/autotrack-secrets.tpl")}"

  vars {
    namespace 	       = "${module.site.environment}"
  }
}

data "template_file" "custom_autotrack_redis" {
  template             = "${file("deploy/autotrack-redis.tpl")}"

  vars {
    namespace          = "${module.site.environment}"
  }
}

data "template_file" "custom_autotrack_mongodb" {
  template             = "${file("deploy/autotrack-mongodb.tpl")}"

  vars {
    namespace          = "${module.site.environment}"
  }
}

data "template_file" "custom_autotrack_jenkins" {
  template             = "${file("deploy/autotrack-jenkins.tpl")}"

  vars {
    domain             = "${module.site.environment}.${module.site.domain_name}"
    namespace          = "${module.site.environment}"
    whitelist 			   = "${var.kubernetes["whitelist"]}"
    docker_registry    = "${module.route53_record_docker_registry.fqdn}"
  }
}

resource "null_resource" "custom_services"{ 
  provisioner "local-exec" { command = "cat > ../../deploy/k8s/custom_secrets.yaml <<EOL\n${data.template_file.custom_secrets.rendered}\nEOL\n" }
  # provisioner "local-exec" { command = "cat > ../../deploy/k8s/custom_efs.yaml <<EOL\n${data.template_file.custom_efs.rendered}\nEOL\n" } 
  provisioner "local-exec" { command = "cat > ../../deploy/k8s/custom_ingress.yaml <<EOL\n${data.template_file.custom_ingress.rendered}\nEOL\n" }

	provisioner "local-exec" { command = "cat > ../../deploy/k8s/custom_autotrack_redis.yaml <<EOL\n${data.template_file.custom_autotrack_redis.rendered}\nEOL\n" }
  provisioner "local-exec" { command = "cat > ../../deploy/k8s/custom_autotrack_mongodb.yaml <<EOL\n${data.template_file.custom_autotrack_mongodb.rendered}\nEOL\n" }
  provisioner "local-exec" { command = "cat > ../../deploy/k8s/custom_autotrack_jenkins.yaml <<EOL\n${data.template_file.custom_autotrack_jenkins.rendered}\nEOL\n" }
}

resource "null_resource" "custom_kubectl" {
  ######################################################################################################################################################
  # Generic resources which can be used by multiple components
  ######################################################################################################################################################
  provisioner "local-exec" { command = "kubectl --kubeconfig ../../config/kubeconfig apply -f ../../deploy/k8s/custom_secrets.yaml; true" }
  provisioner "local-exec" { command = "kubectl --kubeconfig ../../config/kubeconfig apply -f ../../deploy/k8s/custom_ingress.yaml; true" }

	######################################################################################################################################################
  # Custom resources which hold all config in YAML file
  ######################################################################################################################################################
	provisioner "local-exec" { command = "kubectl --kubeconfig ../../config/kubeconfig apply -f ../../deploy/k8s/custom_autotrack_redis.yaml; true" }
  provisioner "local-exec" { command = "kubectl --kubeconfig ../../config/kubeconfig apply -f ../../deploy/k8s/custom_autotrack_mongodb.yaml; true" }
  provisioner "local-exec" { command = "kubectl --kubeconfig ../../config/kubeconfig apply -f ../../deploy/k8s/custom_autotrack_jenkins.yaml; true" }

	triggers = {
		provisioner = "${null_resource.custom_services.id}"
	}
}
