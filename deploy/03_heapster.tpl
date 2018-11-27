apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: heapster-binding
  labels:
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:heapster
subjects:
- kind: ServiceAccount
  name: heapster
  namespace: ${namespace}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: heapster
  namespace: ${namespace}
  labels:
    kubernetes.io/cluster-service: "true"
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: heapster
  namespace: ${namespace}
  labels:
    k8s-app: heapster
    kubernetes.io/cluster-service: "true"
    task: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      k8s-app: heapster
      task: monitoring
  template:
    metadata:
      name: heapster
      labels:
        k8s-app: heapster
        task: monitoring
    spec:
      containers:
      - name: heapster
        image: gcr.io/google_containers/heapster-amd64:v1.4.0
        imagePullPolicy: IfNotPresent
        command:
        - /heapster
        - --source=kubernetes:https://kubernetes.default.svc.${cluster_domain}
        - --sink=influxdb:http://monitoring-influxdb.kube-system.svc.${cluster_domain}:8086
        ports:
        - containerPort: 8082
      serviceAccountName: heapster
---
apiVersion: v1
kind: Service
metadata:
  name: heapster
  namespace: ${namespace}
  labels:
    kubernetes.io/cluster-service: 'true'
    addonmanager.kubernetes.io/mode: Reconcile
    kubernetes.io/name: Heapster
spec:
  selector:
    k8s-app: heapster
  ports:
  - port: 80
    targetPort: 8082
