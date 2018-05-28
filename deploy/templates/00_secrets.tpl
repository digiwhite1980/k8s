apiVersion: v1
kind: Secret
metadata:
  name: aws-credentials
  namespace: kube-system
type: Opaque
data:
  aws_region: ${aws_region}
  aws_access: ${aws_access}
  aws_secret: ${aws_secret}
