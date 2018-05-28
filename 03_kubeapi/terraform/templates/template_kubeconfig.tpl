apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: ${ssl_ca_crt}
    server: https://${elb_name}
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    namespace: default
    user: kubernetes-admin
  name: kubernetes
users:
  - name: kubernetes-admin
    user:
      client-certificate-data: ${ssl_kubeapi_crt}
      client-key-data: ${ssl_kubeapi_key}
current-context: kubernetes
