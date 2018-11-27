FROM jenkins/jenkins:lts-alpine

ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"

USER root
RUN apk update && \
    apk add docker && \
    apk add py-pip && \
	 pip install --upgrade pip && \
	 pip install docker-compose
 
COPY security.groovy /usr/share/jenkins/ref/init.groovy.d/1.security.groovy
COPY csrf.groovy /usr/share/jenkins/ref/init.groovy.d/2.csrf.groovy
######################################################################################
#def git_url = System.getenv('SEEDJOB_GIT')
#def git_username = System.getenv("GIT_USERNAME")
#def git_ssh_password = System.getenv("GIT_SSH_PASSWORD")
#def git_ssh_private_key = System.getenv("GIT_SSH_PRIVATE_KEY")
######################################################################################
COPY create-seed-job.groovy /usr/share/jenkins/ref/init.groovy.d/2.create-seed-job.groovy

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN /usr/local/bin/install-plugins.sh < /usr/share/jenkins/ref/plugins.txt

COPY entrypoint.sh /

ENTRYPOINT ["/entrypoint.sh"]
