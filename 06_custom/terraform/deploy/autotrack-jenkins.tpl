apiVersion: v1
kind: Secret
metadata:
  namespace: ${namespace}
  name: jenkins-admin
type: Opaque
data:
  username: YWRtaW4=
  password: YWRtaW4=
---
kind: Service
apiVersion: v1
metadata:
  namespace: ${namespace}
  name: jenkins-ui
spec:
  type: ClusterIP
  selector:
    app: jenkins
  ports:
    - protocol: TCP
      port: 8080
      targetPort: 8080
      name: ui

---
kind: Service
apiVersion: v1
metadata:
  namespace: ${namespace}
  name: jenkins-discovery
spec:
  selector:
    app: jenkins
  ports:
    - protocol: TCP
      port: 50000
      targetPort: 50000
      name: slaves
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: jenkins
  namespace: ${namespace}
spec:
  replicas: 1
  revisionHistoryLimit: 5
  selector:
    matchLabels:
      app: jenkins
  template:
    metadata:
      labels:
        app: jenkins
    spec:
      containers:
      - name: jenkins
        image: digiwhite/jenkins
        imagePullPolicy: Always
        ports:
        - containerPort: 8080
        - containerPort: 50000
        resources:
          requests:
            cpu: 0.5
            memory: 512Mi
        env:
          - name: SEEDJOB_GIT
            value: "git@github.com:Persgroep/atk8s.git"
          - name: GIT_USERNAME
            value: "jenkins-autotrack"
          - name: GIT_SSH_PASSWORD
            value: ""
          - name: GIT_SSH_PRIVATE_KEY
            valueFrom:
              secretKeyRef:
                name: github-ssh
                key: ssh-key-private
          - name: DOCKER_REGISTRY
            value: "${docker_registry}"
          - name: CLIENT_CERTIFICATE
            value: "/var/certificates/client.crt"
        volumeMounts:
        - mountPath: /root
          name: jenkins-storage
        - mountPath: /var/run/docker.sock
          name: jenkins-docker
        - mountPath: /var/jenkins_home/.docker
          readOnly: true
          name: jenkins-dockerregistry
        - mountPath: /var/secrets
          name: jenkins-admin
        - mountPath: /var/certificates
          name: ssl-client
        - mountPath: /etc/kubernetes
          name: kubeconfig
      volumes:
      - name: jenkins-storage
        emptyDir: {}
      - name: jenkins-docker
        hostPath:
          path: /var/run/docker.sock
      - name: jenkins-dockerregistry
        emptyDir: {}
      - name: jenkins-admin
        secret:
          secretName: jenkins-admin
          items:
          - key: username
            path: jenkins-user
          - key: password
            path: jenkins-pass
      - name: ssl-client
        secret:
          secretName: ssl-client
          items:
          - key: certificate
            path: client.crt
      - name: kubeconfig
        secret:
          secretName: kubeconfig
---
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: ingress-${namespace}
  namespace: ${namespace}
  annotations:
    nginx.ingress.kubernetes.io/whitelist-source-range: "${whitelist}"
spec:
  rules:
  - host: jenkins.${domain}
    http:
      paths:
        - path: /
          backend:
            serviceName: jenkins-ui
            servicePort: 8080
---
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: jenkins
  namespace: ${namespace}
spec:
  podSelector:
    matchLabels:
      app: jenkins
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: "ingress-nginx"
