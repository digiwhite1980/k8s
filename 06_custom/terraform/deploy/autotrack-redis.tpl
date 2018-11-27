apiVersion: v1
kind: Service
metadata:
  namespace: ${namespace}
  annotations:
    service.alpha.kubernetes.io/tolerate-unready-endpoints: "true"
  labels:
    app: redis
  name: redis
spec:
  clusterIP: None
  ports:
    - port: 6379
  selector:
    component: redis
---
apiVersion: v1
kind: Service
metadata:
  namespace: ${namespace}
  labels:
    name: sentinel
  name: redis-sentinel
spec:
  ports:
    - port: 26379
  selector:
    component: redis
---
apiVersion: "apps/v1"
kind: StatefulSet
metadata:
  namespace: ${namespace}
  labels:
    name: redis
    component: redis
  name: redis
spec:
  selector:
    matchLabels:
      component: redis
  serviceName: redis
  replicas: 3
  template:
    metadata:
      labels:
        name: redis
        component: redis
    spec:
      imagePullSecrets:
        - name: dockerhub
      containers:
        - name: redis
          image: autotrack/redis
          imagePullPolicy: Always
          env:
            - name: DEBUG
              value: "1"
          ports:
            - containerPort: 6379
          resources:
            limits:
              cpu: "0.1"
              memory: 512Mi
          volumeMounts:
            - mountPath: /redis-data
              name: redis-data
          readinessProbe:
            exec:
              command:
              - sh
              - -c
              - "redis-cli -h localhost ping"
            initialDelaySeconds: 15
            timeoutSeconds: 5
        - name: sentinel
          image: autotrack/redis
          imagePullPolicy: Always
          env:
            - name: SENTINEL
              value: "true"
            - name: DEBUG
              value: "1"
          ports:
            - containerPort: 26379
          resources:
            limits:
              cpu: "0.1"
              memory: 64Mi
      volumes:
      - name: redis-data
        emptyDir: {}
