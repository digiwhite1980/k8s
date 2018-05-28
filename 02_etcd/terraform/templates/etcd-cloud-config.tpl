#cloud-config

package_upgrade: true

packages:
  - docker.io
  - bridge-utils
  - socat
  - ntp
  - jq
  - nfs-common

datasource:
  Ec2:
    timeout : 50
    max_wait : 120
    metadata_urls:
      - http://169.254.169.254:80

write_files:
  - path: /etc/systemd/system/etcd.service
    content: |
      [Unit]
      Description=etcd ${etcd_version} service (Digiwhite)
      Requires=docker.service
      After=docker.service
      [Service]
      ExecStartPre=-/usr/bin/docker pull digiwhite/etcd:${etcd_version}
      ExecStart=/usr/bin/docker run \
        -h etcd \
        --net=host \
        --name=etcd \
        --volume=/var/run/docker.sock:/var/run/docker.sock \
        --volume=/etcd/ssl/:/etcd/ssl/ \
        -e DOCKER_EC2VAL=${EC2value} \
        --rm \
        digiwhite/etcd:${etcd_version}
      ExecStop=/usr/bin/pkill etcd
      [Install]
      WantedBy=multi-user.target

  - path: /usr/bin/etcd_test
    owner: root:root
    permissions: '0744'
    content: |
      #!/bin/bash
      LOCAL_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
      curl -s -k --cacert /etcd/ssl/client_ca.crt --cert /etcd/ssl/client.crt --key /etcd/ssl/client.key https://$${LOCAL_IP}:2379/v2/members | jq -r

  - path: /etcd/ssl/client.crt
    owner: root:root
    encoding: base64
    content: "${base64encode("${ssl_etcd_crt}")}"

  - path: /etcd/ssl/client.key
    owner: root:root
    permissions: '0400'
    encoding: base64
    content: "${base64encode("${ssl_etcd_key}")}"

  - path: /etcd/ssl/client_ca.crt
    owner: root:root
    encoding: base64
    content: "${base64encode("${ssl_ca_crt}")}"

  - path: /etcd/ssl/peer.crt
    owner: root:root
    encoding: base64
    content: "${base64encode("${ssl_etcd_crt}")}"

  - path: /etcd/ssl/peer.key
    owner: root:root
    permissions: '0400'
    encoding: base64
    content: "${base64encode("${ssl_etcd_key}")}"

  - path: /etcd/ssl/peer_ca.crt
    owner: root:root
    encoding: base64
    content: "${base64encode("${ssl_ca_crt}")}"

runcmd:
  - [ systemctl, enable, docker ]
  - [ systemctl, start, docker ]
  - [ systemctl, enable, etcd ]
  - [ systemctl, start, etcd ]
