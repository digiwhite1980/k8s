apiVersion: storage.k8s.io/v1beta1
kind: StorageClass
metadata:
  name: ssd
  labels:
    kubernetes.io/cluster-service: "true"
provisioner: kubernetes.io/aws-ebs
parameters:
  type: gp2