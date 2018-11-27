{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["ec2:*"],
      "Resource": ["*"]
    },
    {
      "Effect": "Allow",
      "Action": ["elasticloadbalancing:*"],
      "Resource": ["*"]
    },
    {
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": ["*"]
    },
    {
      "Effect": "Allow",
      "Action": "sqs:*",
      "Resource": ["*"]
    },
    {
      "Effect": "Allow",
      "Action": "sns:*",
      "Resource": ["*"]
    },
    {
      "Effect": "Allow",
      "Action": "autoscaling:*",
      "Resource": ["*"]
    },
    {
      "Effect": "Allow",
      "Action": "logs:*",
      "Resource": ["*"]
    },
    {
      "Effect": "Allow",
      "Action": "es:*",
      "Resource": ["*"]
    },
    {
      "Effect": "Allow",
      "Action": "route53:*",
      "Resource": ["*"]
    }
  ]
}