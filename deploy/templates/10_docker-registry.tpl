apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: docker-registry
  namespace: infrastructure
  labels:
    app: docker-registry
    component: deployment
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: docker-registry
        component: deployment
    spec:
      containers:
      - name: registry
        image: registry:2.5
        imagePullPolicy: Always
        resources:
          # keep request = limit to keep this container in guaranteed class
          limits:
            cpu: 100m
            memory: 100Mi
          requests:
            cpu: 100m
            memory: 100Mi
        env:
        - name: REGISTRY_HTTP_ADDR
          value: ":5000"
        - name: REGISTRY_STORAGE_S3_ACCESSKEY
          valueFrom:
            secretKeyRef:
              name: aws-credentials
              key: aws_access
        - name: REGISTRY_STORAGE
          value: "s3"
        - name: REGISTRY_STORAGE_S3_SECRETKEY
          valueFrom:
            secretKeyRef:
              name: aws-credentials
              key: aws_secret
        - name: REGISTRY_STORAGE_S3_REGION
          valueFrom:
            secretKeyRef:
              name: aws-credentials
              key: aws_region
        - name: REGISTRY_STORAGE_S3_BUCKET
          value: "${registry_s3_bucket}"
        - name: REGISTRY_STORAGE_S3_ROOTDIRECTORY
          value: "/registry/v2"
        - name: REGISTRY_STORAGE_S3_ENCRYPT
          value: "true"
        - name: REGISTRY_STORAGE_S3_MULTIPARTCOPYCHUNKSIZE
          value: "33554432"
        - name: REGISTRY_STORAGE_S3_MULTIPARTCOPYMAXCONCURRENCY
          value: "100"
        - name: REGISTRY_STORAGE_S3_MULTIPARTCOPYTHRESHOLDSIZE
          value: "33554432"
        ports:
        - containerPort: 5000
          name: registry
          protocol: TCP
---
apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: docker-registry
  namespace: infrastructure
  labels:
    app: docker-registry
    component: proxy
spec:
  template:
    metadata:
      labels:
        app: docker-registry-proxy
        component: proxy
    spec:
      containers:
      - name: docker-registry-proxy
        image: gcr.io/google_containers/kube-registry-proxy:${kubeproxy_version}
        resources:
          limits:
            cpu: 100m
            memory: 50Mi
        env:
        - name: REGISTRY_HOST
          value: docker-registry.infrastructure.svc
        - name: REGISTRY_PORT
          value: "5000"
        - name: FORWARD_PORT
          value: "5000"
        ports:
        - name: docker-registry
          containerPort: 5000
          hostPort: 5000
---
apiVersion: v1
kind: Service
metadata:
  name: docker-registry
  namespace: infrastructure
  labels:
    app: docker-registry
    component: deployment
spec:
  type: NodePort
  ports:
  - name: docker-registry
    port: 5000
    protocol: TCP
  selector:
    app: docker-registry
    component: deployment
