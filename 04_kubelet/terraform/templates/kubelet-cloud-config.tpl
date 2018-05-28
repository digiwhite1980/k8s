#cloud-config
package_upgrade: true
packages:
  - docker.io
  - bridge-utils
  - socat
  - ntp
  - jq
  - nfs-common
  - util-linux

datasource:
  ec2:
    timeout : 50
    max_wait : 120
    metadata_urls:
      - http://169.254.169.254:80

write_files:
  - path: /etc/logrotate.d/containers
    content: |
      /var/lib/docker/containers/*/*-json.log {
          rotate 5
          copytruncate
          missingok
          notifempty
          compress
          maxsize 10M
          daily
          create 0644 root root
      }

  - path: /usr/local/bin/cni-plugins.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      [[ ! -d /opt/cni/bin ]] && mkdir -p /opt/cni/bin
      cd /opt/cni/bin
      if [ -f loopback ]; then
        echo "CNI plugins already installed."
      else
        curl -s -L https://github.com/containernetworking/plugins/releases/download/${cni_plugin_version}/cni-plugins-amd64-${cni_plugin_version}.tgz | tar xzf -
      fi

  - path: /etc/systemd/system/cni-plugins.service
    content: |
      [Unit]
      Description=CNI plugin download script
      Before=docker.service
      [Service]
      Type=oneshot
      ExecStart=/usr/local/bin/cni-plugins.sh
      RemainAfterExit=true
      StandardOutput=journal
      [Install]
      WantedBy=multi-user.target

  - path: /etc/systemd/system/local-ipv4.service
    content: |
      [Unit]
      Description=Oneshot service for local ipv4 in /etc/environment
      Before=docker.service
      [Service]
      Type=oneshot
      ExecStart=/bin/bash -c "echo PRIVATE_IPV4=$(curl http://169.254.169.254/latest/meta-data/local-ipv4) >> /etc/environment"
      RemainAfterExit=true
      StandardOutput=journal
      [Install]
      WantedBy=multi-user.target
  
  - path: /etc/systemd/system/docker-tcp.socket
    content: |
      [Unit]
      Description=Docker Secured Socket for the API
      [Socket]
      ListenStream=${docker_port}
      Service=docker.service
      [Install]
      WantedBy=sockets.target

  - path: /etc/systemd/system/docker.service.d/10-docker-opts.conf
    content: |
      [Service]
      LimitNOFILE=1048576
      LimitNPROC=104857
      #Environment="DOCKER_OPTS=--tlsverify --tlscacert=/etc/docker/ca.pem --tlscert=/etc/docker/docker.pem --tlskey=/etc/docker/docker.key"
      #Environment="DOCKER_OPTS=--storage-driver=overlay --iptables=false --ip-masq=false --bridge=none"

  - path: /etc/systemd/system/kubelet.service
    content: |
      [Unit]
      After=docker.service
      Requires=docker.service
      BindsTo=docker.service
      [Service]
      Restart=always
      RestartSec=10
      ExecStartPre=-/bin/umount /var/lib/kubelet
      ExecStartPre=-/bin/bash -c 'modprobe ip_tables ip_conntrack'
      ExecStartPre=-/bin/mkdir -p /var/lib/kubelet
      ExecStartPre=/bin/mount --bind /var/lib/kubelet /var/lib/kubelet
      ExecStartPre=/bin/mount --make-shared /var/lib/kubelet
      ExecStartPre=-/bin/mkdir -p /etc/kubernetes/manifests
      ExecStartPre=-/usr/bin/docker rm -f kubelet
      ExecStart=/usr/bin/docker run \
        --net=host \
        --pid=host \
        --privileged \
        --name=kubelet \
        -v /dev:/dev:ro \
        -v /sys:/sys:rw \
        -v /var/run:/var/run:rw \
        -v /var/lib/docker/:/var/lib/docker:rw \
        -v /var/lib/kubelet/:/var/lib/kubelet:rw,shared \
        -v /var/log:/var/log:shared \
        -v /etc/ssl/certs:/etc/ssl/certs \
        -v /srv/kubernetes:/srv/kubernetes:ro \
        -v /etc/kubernetes:/etc/kubernetes:ro  \
        -v /etc/cni/:/etc/cni/ \
        -v /opt/cni/:/opt/cni/ \
        gcr.io/google-containers/hyperkube:${kubernetes_version} \
          kubelet \
            --allow-privileged \
            --cloud-provider=aws \
            --cluster-dns=${cluster_dns} \
            --cluster-domain=${cluster_domain} \
            --enable-controller-attach-detach=false \
            --kubeconfig=/etc/kubernetes/kubeconfig.yaml \
            --network-plugin=cni \
            --node-labels="instance-group=${instance_group},instance-type=node" \
            --pod-manifest-path=/etc/kubernetes/manifests \
            --register-schedulable=true \
            --tls-cert-file=/etc/kubernetes/ssl/kubelet.pem \
            --tls-private-key-file=/etc/kubernetes/ssl/kubelet-key.pem \
            --v=4
      [Install]
      WantedBy=multi-user.target

  - path: /etc/systemd/system/kube-proxy.service
    content: |
      [Unit]
      Description=Kubernetes Kube Proxy
      Documentation=https://github.com/GoogleCloudPlatform/kubernetes
      After=docker.service kubelet.service
      Requires=docker.service
      BindsTo=docker.service
      [Service]
      ExecStartPre=-/usr/bin/docker rm -f kube-proxy
      ExecStart=/usr/bin/docker run \
        --name kube-proxy \
        --net=host \
        --volume=/etc/ssl/certs:/etc/ssl/certs \
        --volume=/etc/kubernetes:/etc/kubernetes \
        --privileged \
        gcr.io/google-containers/hyperkube:${kubernetes_version} \
          kube-proxy \
          --logtostderr=true \
          --kubeconfig=/etc/kubernetes/kubeconfig.yaml \
          --proxy-mode=iptables \
          --v=3
      Restart=on-failure
      RestartSec=5
      [Install]
      WantedBy=multi-user.target

  - path: /etc/kubernetes/ssl/kubelet.pem
    encoding: base64
    content: "${base64encode("${ssl_kubelet_crt}")}"
  - path: /etc/kubernetes/ssl/kubelet-key.pem
    encoding: base64
    content: "${base64encode("${ssl_kubelet_key}")}"

  - path: /etc/kubernetes/ssl/etcd-server.pem
    encoding: base64
    content: "${base64encode("${ssl_etcd_crt}")}"
  - path: /etc/kubernetes/ssl/etcd-server-key.pem
    encoding: base64
    content: "${base64encode("${ssl_etcd_key}")}"

  - path: /etc/kubernetes/ssl/ca.pem
    encoding: base64
    content: "${base64encode("${ssl_ca_crt}")}"

  - path: /etc/kubernetes/kubeconfig.yaml
    content: |
      apiVersion: v1
      kind: Config
      clusters:
      - name: local
        cluster:
          certificate-authority: /etc/kubernetes/ssl/ca.pem
          server: ${kubeapi_elb}
      users:
      - name: kubelet
        user:
          client-certificate: /etc/kubernetes/ssl/kubelet.pem
          client-key: /etc/kubernetes/ssl/kubelet-key.pem
      contexts:
      - context:
          cluster: local
          user: kubelet
        name: kubelet-context
      current-context: kubelet-context

runcmd:
  - [ systemctl, enable, local-ipv4.service ]
  - [ systemctl, start, local-ipv4.service ]
  - [ systemctl, enable, cni-plugins.service ]
  - [ systemctl, start, cni-plugins.service ]
  - [ systemctl, enable, docker ]
  - [ systemctl, start, docker]
  - [ systemctl, enable, kubelet ]
  - [ systemctl, start, kubelet ]
  - [ systemctl, enable, kube-proxy ]
  - [ systemctl, start, kube-proxy ]
  - [ systemctl, disable, iscsid ]
  - [ systemctl, stop, iscsid ]
  - [ systemctl, disable, snapd ]
  - [ systemctl, stop, snapd ]
  - [ systemctl, disable, accounts-daemon ]
  - [ systemctl, stop, accounts-daemon ]  
  - [ systemctl, disable, mdadm ]
  - [ systemctl, stop, mdadm ] 