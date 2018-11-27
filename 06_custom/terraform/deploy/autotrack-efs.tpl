apiVersion: v1
kind: ConfigMap
metadata:
  name: efs-provisioner
  namespace: ${namespace}
data:
  file.system.id: ${filesystem_id}
  aws.region: ${region}
  provisioner.name: ${domain}/efs-provisioner
---
kind: Deployment
apiVersion: extensions/v1beta1
metadata:
  name: efs-provisioner
  namespace: ${namespace}
spec:
  replicas: 1
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: efs-provisioner
    spec:
      containers:
        - name: efs-provisioner
          image: quay.io/external_storage/efs-provisioner:latest
          env:
            - name: FILE_SYSTEM_ID
              valueFrom:
                configMapKeyRef:
                  name: efs-provisioner
                  key: file.system.id
            - name: AWS_REGION
              valueFrom:
                configMapKeyRef:
                  name: efs-provisioner
                  key: aws.region
            - name: PROVISIONER_NAME
              valueFrom:
                configMapKeyRef:
                  name: efs-provisioner
                  key: provisioner.name
          volumeMounts:
            - name: pv-volume
              mountPath: /persistentvolumes
      volumes:
        - name: pv-volume
          nfs:
            server: "${server}"
            path: /
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: aws-efs
  namespace: ${namespace}
provisioner: ${domain}/efs-provisioner
---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: efs
  namespace: ${namespace}
  annotations:
    volume.beta.kubernetes.io/storage-class: "aws-efs"
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Mi
---
