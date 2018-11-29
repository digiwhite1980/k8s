apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${ssd_class}
  labels:
    kubernetes.io/cluster-service: "true"
  annotations: 
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: kubernetes.io/aws-ebs
reclaimPolicy: Delete
parameters:
  type: gp2
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${hdd_class}
  labels:
    kubernetes.io/cluster-service: "true"
provisioner: kubernetes.io/aws-ebs
parameters:
  type: sc1