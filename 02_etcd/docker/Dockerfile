FROM alpine:3.4
MAINTAINER Raymond Otto <otto@digiwhite.nl> GIThub: digiwhite1980
##############################################################################
# We dont use variables which start with ETCD_. These are reserved
# by ETCD
##############################################################################
ENV ED_VERSION=v3.3.2
ENV ED_URL="https://github.com/coreos/etcd/releases/download/${ED_VERSION}/etcd-${ED_VERSION}-linux-amd64.tar.gz"

ENV ED_HOME="/etcd"
ENV ED_DATA="${ED_HOME}/data"
ENV ED_WAL="${ED_HOME}/wal"
ENV ED_SSL="${ED_HOME}/ssl"
ENV PATH=${PATH}:${ED_HOME}/bin

WORKDIR /tmp

RUN apk --update add ca-certificates openssl tar tzdata bash jq curl docker && \
    mkdir -p /etcd/data && \
	 mkdir -p /etcd/wal && \
	 mkdir -p /etcd/ssl && \
    mkdir -p /etcd/bin

RUN wget ${ED_URL} && \
    tar zxf etcd-* && \
	 rm *.tar.gz && \
	 mv etcd-*/* ${ED_HOME}/bin

ADD entrypoint.sh /entrypoint.sh

ENTRYPOINT [ "/entrypoint.sh" ]
