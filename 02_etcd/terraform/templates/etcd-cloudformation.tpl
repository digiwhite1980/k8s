{
  "Resources": {
    "${resource_name}": {
      "Type": "AWS::AutoScaling::AutoScalingGroup",
      "Properties": {
        "VPCZoneIdentifier": ["${subnet_ids}"],
        "LaunchConfigurationName": "${launch_name}",
        "MaxSize": "${max_size}",
        "MinSize": "${min_size}",
        "LoadBalancerNames" : [ "${loadbalancer}" ],
        "TerminationPolicies": ["OldestLaunchConfiguration", "OldestInstance"],
        "Tags": [{
          "Key": "Name",
          "Value": "${resource_name}",
          "PropagateAtLaunch": "true"
        },
        {
          "Key": "KubernetesCluster",
          "Value": "${cluster_name}",
          "PropagateAtLaunch": "true"
        },
        {
          "Key": "Environment",
          "Value": "${environment}",
          "PropagateAtLaunch": "true"
        },
        {
          "Key": "etcd",
          "Value": "${etcd_tag}",
          "PropagateAtLaunch": "true"
        },
        {
          "Key": "etcdVersion",
          "Value": "${etcd_version}",
          "PropagateAtLaunch": "true"
        }]
      },
      "UpdatePolicy": {
        "AutoScalingRollingUpdate": {
          "MaxBatchSize": "1",
          "PauseTime": "${pause_time}"
        }
      }
    }
  }
}