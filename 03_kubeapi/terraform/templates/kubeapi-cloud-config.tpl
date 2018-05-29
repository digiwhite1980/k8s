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
  - path: /etc/systemd/system/local-ipv4.service
    content: |
      [Unit]
      Description=Oneshot service for local ipv4 in /etc/environment
      Before=docker.service
      [Service]
      Type=oneshot
      ExecStart=/bin/bash -c "echo PRIVATE_IPV4=$(curl http://169.254.169.254/latest/meta-data/local-ipv4) >> /etc/environment"
      RemainAfterExit=true
      [Install]
      WantedBy=multi-user.target

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

  - path: /etc/systemd/system/kube-proxy.service
    content: |
        [Unit]
        Description=Kubernetes Kube Proxy
        Documentation=https://github.com/GoogleCloudPlatform/kubernetes
        After=docker.service kube-apiserver.service
        Requires=docker.service
        BindsTo=docker.service
        [Service]
        ExecStartPre=-/usr/bin/docker rm -f kube-proxy
        ExecStart=/usr/bin/docker run \
          --name kube-proxy \
          --net=host \
          --privileged \
          --volume=/etc/kubernetes/:/etc/kubernetes/ \
          gcr.io/google-containers/hyperkube:${kubernetes_version} \
            /hyperkube proxy \
            --logtostderr=true \
            --kubeconfig=/etc/kubernetes/kubeconfig.yaml \
            --proxy-mode=iptables \
            --v=2
        Restart=on-failure
        RestartSec=5
        [Install]
        WantedBy=multi-user.target
        # --master=http://localhost:8080 \

  - path: /etc/systemd/system/kube-apiserver.service
    content: |
      [Unit]
      Description=Kubernetes API Server
      Documentation=https://github.com/GoogleCloudPlatform/kubernetes
      [Service]
      EnvironmentFile=/etc/environment
      ExecStartPre=-/bin/bash -c 'modprobe ip_tables ip_conntrack'
      ExecStartPre=-/usr/bin/docker rm -f kube-apiserver
      ExecStart=/usr/bin/docker run \
        --net=host \
        --privileged \
        --name=kube-apiserver \
        --volume=/etc/kubernetes/:/etc/kubernetes/ \
        --volume=/etc/ssl/certs:/etc/ssl/certs \
        gcr.io/google-containers/hyperkube:${kubernetes_version} \
          /hyperkube apiserver \
          --admission-control=NamespaceLifecycle,LimitRanger,ServiceAccount,ResourceQuota \
          --allow-privileged=true \
          --bind-address=0.0.0.0 \
          --client-ca-file=/etc/kubernetes/ssl/ca.pem \
          --cloud-provider=aws \
          --enable-swagger-ui=true \
          --etcd-servers=${etcd_endpoint} \
          --etcd-cafile=/etc/kubernetes/ssl/ca.pem \
          --etcd-certfile=/etc/kubernetes/ssl/etcd-server.pem \
          --etcd-keyfile=/etc/kubernetes/ssl/etcd-server-key.pem \
          --logtostderr=true \
          --runtime-config=extensions/v1beta1/networkpolicies=true,extensions/v1beta1/deployments=true,extensions/v1beta1/daemonsets=true,extensions/v1beta1/thirdpartyresources=true,batch/v2alpha1=true \
          --secure-port=443 \
          --service-account-key-file=/etc/kubernetes/ssl/kubeapi-key.pem \
          --service-cluster-ip-range=${service_ip_range} \
          --storage-backend=etcd3 \
          --target-ram-mb=2048 \
          --tls-ca-file=/etc/kubernetes/ssl/ca.pem \
          --tls-cert-file=/etc/kubernetes/ssl/kubeapi.pem \
          --tls-private-key-file=/etc/kubernetes/ssl/kubeapi-key.pem \
          --v=3 \
      Restart=on-failure
      RestartSec=5
      [Install]
      WantedBy=multi-user.target

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
          /hyperkube kubelet \
            --api-servers=${kubeapi_lb_endpoint} \
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
            --tls-cert-file=/etc/kubernetes/ssl/kubeapi.pem \
            --tls-private-key-file=/etc/kubernetes/ssl/kubeapi-key.pem \
            --v=3
      [Install]
      WantedBy=multi-user.target

  - path: /etc/systemd/system/kube-controller-manager.service
    content: |
      [Unit]
      Description=Kubernetes Controller Manager
      Documentation=https://github.com/GoogleCloudPlatform/kubernetes
      [Service]
      ExecStartPre=-/usr/bin/docker rm -f kube-controller-manager
      ExecStart=/usr/bin/docker run \
        --net=host \
        --privileged \
        --volume=/etc/kubernetes/:/etc/kubernetes/ \
        --volume=/etc/ssl/certs:/etc/ssl/certs \
        --name=kube-controller-manager \
          gcr.io/google-containers/hyperkube:${kubernetes_version} \
          /hyperkube controller-manager \
            --kubeconfig=/etc/kubernetes/kubeconfig.yaml \
            --leader-elect=true \
            --service-account-private-key-file=/etc/kubernetes/ssl/kubeapi-key.pem \
            --root-ca-file=/etc/kubernetes/ssl/ca.pem \
            --cloud-provider=aws \
            --v=3
      Restart=on-failure
      RestartSec=5
      [Install]
      WantedBy=multi-user.target

  - path: /etc/systemd/system/kube-scheduler.service
    content: |
      [Unit]
      Description=Kubernetes Scheduler
      Documentation=https://github.com/GoogleCloudPlatform/kubernetes
      [Service]
      ExecStartPre=-/usr/bin/docker rm -f kube-scheduler
      ExecStart=/usr/bin/docker run \
        --net=host \
        --privileged \
        --volume=/etc/kubernetes/:/etc/kubernetes/ \
        --volume=/etc/ssl/certs:/etc/ssl/certs \
        --name=kube-scheduler \
          gcr.io/google-containers/hyperkube:${kubernetes_version} \
        /hyperkube scheduler \
          --leader-elect=true \
          --kubeconfig=/etc/kubernetes/kubeconfig.yaml \
          --v=3
      Restart=on-failure
      RestartSec=5
      [Install]
      WantedBy=multi-user.target

  - path: /etc/kubernetes/kubeconfig.yaml
    content: |
      apiVersion: v1
      kind: Config
      clusters:
      - name: local
        cluster:
          certificate-authority: /etc/kubernetes/ssl/ca.pem
          server: https://localhost:443
      users:
      - name: kubelet
        user:
          client-certificate: /etc/kubernetes/ssl/kubeapi.pem
          client-key: /etc/kubernetes/ssl/kubeapi-key.pem
      contexts:
      - context:
          cluster: local
          user: kubelet
        name: kubelet-context
      current-context: kubelet-context

  - path: /etc/kubernetes/ssl/kubeapi.pem
    encoding: "base64"
    content: "${base64encode("${ssl_kubeapi_crt}")}"
  - path: /etc/kubernetes/ssl/kubeapi-key.pem
    encoding: "base64"
    content: "${base64encode("${ssl_kubeapi_key}")}"

  - path: /etc/kubernetes/ssl/etcd-server.pem
    encoding: "base64"
    content: "${base64encode("${ssl_etcd_crt}")}"
  - path: /etc/kubernetes/ssl/etcd-server-key.pem
    encoding: "base64"
    content: "${base64encode("${ssl_etcd_key}")}"

  - path: /etc/kubernetes/ssl/ca.pem
    encoding: "base64"
    content: "${base64encode("${ssl_ca_crt}")}"

runcmd:
  - [ systemctl, enable, local-ipv4.service ]
  - [ systemctl, start, local-ipv4.service ]
  - [ systemctl, enable, docker-tls-tcp.socket ]
  - [ systemctl, start, docker-tls-tcp.socker ]
  - [ systemctl, enable, docker ]
  - [ systemctl, start, docker ]
  - [ systemctl, enable, kube-apiserver ]
  - [ systemctl, start, kube-apiserver ]
  - [ systemctl, enable, kube-scheduler ]
  - [ systemctl, start, kube-scheduler ]
  - [ systemctl, enable, kube-proxy ]
  - [ systemctl, start, kube-proxy ]
  - [ systemctl, enable, kube-controller-manager ]
  - [ systemctl, start, kube-controller-manager ]
  - [ systemctl, enable, kubelet ]
  - [ systemctl, start, kubelet ]
  - [ systemctl, disable, iscsid ]
  - [ systemctl, stop, iscsid ]
  - [ systemctl, disable, snapd ]
  - [ systemctl, stop, snapd ]
  - [ systemctl, disable, accounts-daemon ]
  - [ systemctl, stop, accounts-daemon ] 
  - [ systemctl, disable, mdadm ]
  - [ systemctl, stop, mdadm ] 