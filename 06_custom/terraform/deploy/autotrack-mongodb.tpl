apiVersion: v1
kind: Service
metadata:
  namespace: ${namespace}
  labels:
    app: mongodb
  name: mongodb
  annotations:
    service.alpha.kubernetes.io/tolerate-unready-endpoints: "true"
spec:
  clusterIP: None
  ports:
    - port: 27017
  selector:
    app: mongodb

---
apiVersion: "apps/v1beta1"
kind: StatefulSet
metadata:
  namespace: ${namespace}
  name: mongodb
  labels:
    component: mongodb
spec:
  serviceName: mongodb
  selector:
    matchLabels:
      component: mongodb
  replicas: 3
  template:
    metadata:
      labels:
        app: mongodb
        mongo_rs_name: rs0
        component: mongodb
    spec:
      containers:
      - name: mongo
        image: mongo:3.0
        imagePullPolicy: Always
        livenessProbe:
          tcpSocket:
            port: 27017
          initialDelaySeconds: 30
          timeoutSeconds: 5
          periodSeconds: 120
        resources:
          requests:
            cpu: 1
          limits:
            memory: 1024Mi
        ports:
        - containerPort: 27017
          hostPort: 37017
          name: temp-extra-int
          protocol: TCP
        volumeMounts:
          - mountPath: /data/db
            name: mongodb-data
          - mountPath: /data/configdb
            name: mongodb-config
        command:
          - "bash"
          - "-c"
          - "sleep 10 && mongod --replSet rs0 --wiredTigerCacheSizeGB 1"
      volumes:
        - name: mongodb-data
          emptyDir: {}
        - name: mongodb-config
          emptyDir: {}
