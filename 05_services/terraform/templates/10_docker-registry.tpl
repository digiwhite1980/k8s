apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: docker-registry
  namespace: ${namespace}
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
        image: registry:${registry_version}
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
        - name: REGISTRY_HTTP_TLS_CERTIFICATE
          value: "/etc/ssl/cert/docker-registry.pem"
        - name: REGISTRY_HTTP_TLS_KEY
          value: "/etc/ssl/key/docker-registry.key"
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
        - name: REGISTRY_STORAGE_DELETE_ENABLED
          value: "true"
        volumeMounts:
        - name: registry-certificate
          mountPath: "/etc/ssl/cert"
          readOnly: true
        - name: registry-key
          mountPath: "/etc/ssl/key"
          readOnly: true
        - name: registry-ca
          mountPath: "/etc/ssl/ca"
          readOnly: true                  
        ports:
        - containerPort: 5000
          name: registry
          protocol: TCP
      volumes:
      - name: registry-certificate
        secret: 
          secretName: ssl-docker-registry
          items:
          - key: certificate
            path: docker-registry.pem 
      - name: registry-key
        secret: 
          secretName: ssl-docker-registry
          items:
          - key: key 
            path: docker-registry.key          
      - name: registry-ca
        secret: 
          secretName: ssl-ca
          items:
          - key: certificate
            path: ca.pem
---
apiVersion: v1
kind: Service
metadata:
  name: docker-registry
  namespace: ${namespace}
  labels:
    app: docker-registry
    component: deployment
spec:
  ports:
  - name: docker-registry
    port: 5000
    protocol: TCP
    targetPort: 5000
  selector:
    app: docker-registry
    component: deployment
---
apiVersion: v1
kind: Service
metadata:
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-internal: 0.0.0.0/0
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
  labels:
    app: docker-registry
    component: deployment
  name: docker-registry-lb
  namespace: ${namespace}
spec:
  ports:
  - name: docker-registry
    port: 5000
    protocol: TCP
    targetPort: 5000
  selector:
    app: docker-registry
    component: deployment
  sessionAffinity: None
  type: LoadBalancer
  clusterIP: ${loadbalancer_ip}
