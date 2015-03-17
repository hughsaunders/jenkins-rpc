FROM ubuntu:14.04
MAINTAINER Evan Callicoat <apsu@propter.net>

# Make apt quiet
ENV DEBIAN_FRONTEND noninteractive

# Update and grab curl and make sure we can apt over https
RUN apt-get update
RUN apt-get install -y curl apt-transport-https

# Jenkins repo and key -- per jenkins installation page
RUN echo deb http://pkg.jenkins-ci.org/debian binary/ > /etc/apt/sources.list.d/jenkins.list
RUN curl -s http://pkg.jenkins-ci.org/debian/jenkins-ci.org.key | apt-key add -

# Docker repo and key -- per docker installation page
RUN echo deb https://get.docker.io/ubuntu docker main > /etc/apt/sources.list.d/docker.list
RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 36A1D7869245C8950F966E92D8576A8BA88D21E9

# Update again
RUN apt-get update

# Upgrade and install things
RUN apt-get upgrade -y
RUN apt-get install -y jenkins git ssh-client lxc-docker unzip python build-essential python-dev libssl-dev libffi-dev

# install pip
RUN curl https://bootstrap.pypa.io/get-pip.py > get-pip.py
RUN python get-pip.py

# Install Requests
RUN pip install requests pyyaml virtualenv ansible==1.8.4 jinja2

# Add ssh keys
ADD id_rsa /root/.ssh/id_rsa
ADD id_rsa.pub /root/.ssh/id_rsa.pub

# Add ssh config
ADD ssh_config /root/.ssh/config

# Use volume for Jenkins home
ENV JENKINS_HOME /opt/jenkins
VOLUME /opt/jenkins

# Extract slave.jar to /root
RUN unzip -j /usr/share/jenkins/jenkins.war WEB-INF/slave.jar -d /root

# Fire up jenkins
CMD java -jar /root/slave.jar -jnlpUrl http://${JENKINS_MASTER}/computer/${JENKINS_SLAVE}/slave-agent.jnlp -secret ${JENKINS_SECRET}
