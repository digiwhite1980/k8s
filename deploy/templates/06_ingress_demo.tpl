apiVersion: extensions/v1beta1 # for versions before 1.5.7
kind: Deployment
metadata:
  name: nginx-demo
  namespace: ${namespace}
spec:
  selector:
    matchLabels:
      app: nginx-demo
  replicas: 2 # tells deployment to run 2 pods matching the template
  template: # create pods using pod definition in this template
    metadata:
      # unlike pod-nginx.yaml, the name is not included in the meta data as a unique name is
      # generated from the deployment name
      labels:
        app: nginx-demo
    spec:
      containers:
      - name: nginx
        volumeMounts:
        - name: nginx-content
          mountPath: /usr/share/nginx/html
        image: nginx:1.14.0-alpine
        ports:
        - containerPort: 80
      volumes:
        - name: nginx-content
          downwardAPI:
            items:
              - path: "index.html"
                fieldRef:
                  fieldPath: metadata.name
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-demo
  namespace: ${namespace}
  labels:
    app: nginx-demo
spec:
  ports:
  - name: http
    port: 80
    targetPort: 80
  selector:
    app: nginx-demo
---
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: demo
  namespace: ${namespace}
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: demo.example.local
    http:
      paths:
        - path: /
          backend:
            serviceName: nginx-demo
            servicePort: 80
