apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ssd
  labels:
    kubernetes.io/cluster-service: "true"
  annotations: 
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: kubernetes.io/aws-ebs
reclaimPolicy: Delete
parameters:
  type: gp2