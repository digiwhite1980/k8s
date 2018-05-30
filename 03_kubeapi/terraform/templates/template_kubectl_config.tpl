apiVersion: v1
clusters:
- cluster:
    certificate-authority: ${root_path}/config/ca.crt
    server: ${kubeapi_url}
  name: ${clustername}
contexts:
- context:
    cluster: ${clustername}
    user: ${clustername}
  name: ${clustername}
- context:
    cluster: ${clustername}
    namespace: kube-public
    user: ${clustername}-admin
  name: ${clustername}
current-context: ${clustername}
kind: Config
preferences: {}
users:
- name: ${clustername}-admin
  user:
    client-certificate: ${root_path}/config/kubeapi.crt
    client-key: ${root_path}/config/kubeapi.key