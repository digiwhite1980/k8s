apiVersion: v1
kind: Secret
metadata:
  name: aws-credentials
  namespace: ${namespace}
type: Opaque
data:
  aws_region: ${aws_region}
  aws_access: ${aws_access}
  aws_secret: ${aws_secret}
---
apiVersion: v1
kind: Secret
metadata:
  name: ssl-docker-registry
  namespace: ${namespace}
type: Opaque
data:
  certificate: ${docker-registry-crt}
  key: ${docker-registry-key}
---
apiVersion: v1
kind: Secret
metadata:
  name: ssl-ca
  namespace: ${namespace}
type: Opaque
data:
  certificate: ${ca-cert}
---
apiVersion: v1
kind: Secret
metadata:
  name: ssl-client
  namespace: ${namespace}
type: Opaque
data:
  certificate: ${client-cert}
---
apiVersion: v1
kind: Secret
metadata:
  name: kubeconfig
  namespace: ${namespace}
type: Opaque
data:
  kubeconfig: ${kubeconfig}