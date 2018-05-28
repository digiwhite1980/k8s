kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: pvc-fs-demo
  namespace: ${namespace}
spec:
  accessModes:
    - ReadWriteOnce
  volumeMode: Filesystem
  resources:
    requests:
      storage: 2Gi
  storageClassName: slow
---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: pvc-block-demo
  namespace: ${namespace}
spec:
  accessModes:
    - ReadWriteOnce
  volumeMode: Block
  resources:
    requests:
      storage: 2Gi
  storageClassName: slow
