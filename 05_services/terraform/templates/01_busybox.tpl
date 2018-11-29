apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: busybox
  namespace: ${namespace}
spec:
  replicas: 1
  template:
    metadata:
      labels:
        k8s-app: busybox
    spec:
      containers:
      - image: busybox
        command:
          - sleep
          - "3600"
        imagePullPolicy: IfNotPresent
        name: busybox
      restartPolicy: Always
---
apiVersion: v1
kind: Service
metadata:
  name: busybox
  namespace: ${namespace}
  labels:
    k8s-app: busybox
spec:
  selector:
    k8s-app: busybox
  ports:
  - port: 80
    targetPort: 80
