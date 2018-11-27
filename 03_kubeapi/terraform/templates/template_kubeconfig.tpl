apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: ${ssl_ca_crt}
    server: https://${elb_name}
  name: ${clustername}
contexts:
- context:
    cluster: ${clustername}
    namespace: ${namespace}
    user: kubernetes-admin
  name: ${clustername}
users:
  - name: kubernetes-admin
    user:
      client-certificate-data: ${ssl_kubeapi_crt}
      client-key-data: ${ssl_kubeapi_key}
current-context: ${clustername}
