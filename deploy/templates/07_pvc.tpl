kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: pvc-aws-demo
  namespace: ${namespace}
  annotations:
    volume.beta.kubernetes.io/storage-class: "aws-efs"
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 2Gi