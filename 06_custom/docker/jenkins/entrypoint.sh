#!/bin/bash
############################################################################
# Because we use self-signed certificates we will read the certificate and 
# add it to the jenkins keystore 
############################################################################

KEYSTORE="/etc/ssl/certs/java/cacerts"

if [ -f "${CLIENT_CERTIFICATE}" ]; then
	echo "Imorting client certificate ${CLIENT_CERTIFICATE} into keystore"
	keytool -import -noprompt -trustcacerts -keystore ${KEYSTORE} -storepass changeit -alias client -import -file ${CLIENT_CERTIFICATE}
fi

tini -s -- /usr/local/bin/jenkins.sh
