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
