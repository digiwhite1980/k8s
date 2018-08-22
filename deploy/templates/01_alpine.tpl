apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: alpine
  namespace: default
spec:
  replicas: 1
  template:
    metadata:
      labels:
        k8s-app: alpine
    spec:
      containers:
      - image: alpine
        command:
          - sleep
          - "3600"
        imagePullPolicy: IfNotPresent
        name: alpine
      restartPolicy: Always

