---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: default-http-backend
  labels:
    app: default-http-backend
  namespace: ${namespace}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: default-http-backend
  template:
    metadata:
      labels:
        app: default-http-backend
    spec:
      terminationGracePeriodSeconds: 60
      containers:
      - name: default-http-backend
        # Any image is permissible as long as:
        # 1. It serves a 404 page at /
        # 2. It serves 200 on a /healthz endpoint
        image: gcr.io/google_containers/defaultbackend:1.4
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
            scheme: HTTP
          initialDelaySeconds: 30
          timeoutSeconds: 5
        ports:
        - containerPort: 8080
        resources:
          limits:
            cpu: 10m
            memory: 20Mi
          requests:
            cpu: 10m
            memory: 20Mi
---
apiVersion: v1
kind: Service
metadata:
  name: default-http-backend
  namespace: ${namespace}
  labels:
    app: default-http-backend
spec:
  ports:
  - port: 80
    targetPort: 8080
  selector:
    app: default-http-backend
---
kind: ConfigMap
apiVersion: v1
metadata:
  name: tcp-services
  namespace: ${namespace}
---
kind: ConfigMap
apiVersion: v1
metadata:
  name: udp-services
  namespace: ${namespace}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nginx-ingress-serviceaccount
  namespace: ${namespace}
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: nginx-ingress-controller
  namespace: ${namespace}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ingress-nginx
  template:
    metadata:
      labels:
        app: ingress-nginx
      annotations:
        prometheus.io/port: '10254'
        prometheus.io/scrape: 'true'
    spec:
      serviceAccountName: nginx-ingress-serviceaccount
      containers:
        - name: nginx-ingress-controller
          image: quay.io/kubernetes-ingress-controller/nginx-ingress-controller:0.15.0
          args:
            - /nginx-ingress-controller
            - --default-backend-service=\$(POD_NAMESPACE)/default-http-backend
            - --configmap=\$(POD_NAMESPACE)/nginx-configuration
            - --tcp-services-configmap=\$(POD_NAMESPACE)/tcp-services
            - --udp-services-configmap=\$(POD_NAMESPACE)/udp-services
            - --publish-service=\$(POD_NAMESPACE)/ingress-nginx
            - --annotations-prefix=nginx.ingress.kubernetes.io
          env:
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: POD_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
          ports:
          - name: http
            containerPort: 80
          - name: https
            containerPort: 443
          livenessProbe:
            failureThreshold: 3
            httpGet:
              path: /healthz
              port: 10254
              scheme: HTTP
            initialDelaySeconds: 10
            periodSeconds: 10
            successThreshold: 1
            timeoutSeconds: 1
          readinessProbe:
            failureThreshold: 3
            httpGet:
              path: /healthz
              port: 10254
              scheme: HTTP
            periodSeconds: 10
            successThreshold: 1
            timeoutSeconds: 1
          securityContext:
            runAsNonRoot: false
---
kind: Service
apiVersion: v1
metadata:
  name: ingress-nginx
  namespace: ${namespace}
  labels:
    app: ingress-nginx
  annotations:
    # Enable PROXY protocol
    service.beta.kubernetes.io/aws-load-balancer-proxy-protocol: '*'
    # Increase the ELB idle timeout to avoid issues with WebSockets or Server-Sent Events.
    service.beta.kubernetes.io/aws-load-balancer-connection-idle-timeout: '3600'
spec:
  type: LoadBalancer
  selector:
    app: ingress-nginx
  ports:
  - name: http
    port: 80
    targetPort: http
  - name: https
    port: 443
    targetPort: https
---
kind: ConfigMap
apiVersion: v1
metadata:
  name: nginx-configuration
  namespace: ${namespace}
  labels:
    app: ingress-nginx
data:
  use-proxy-protocol: "true"
