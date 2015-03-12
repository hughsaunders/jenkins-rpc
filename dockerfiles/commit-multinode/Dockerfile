FROM ubuntu:14.04.2
MAINTAINER Evan Callicoat <apsu@propter.net>

# Make apt quiet
ENV DEBIAN_FRONTEND noninteractive

# Update, upgrade and install deps for RPC
RUN apt-get update
RUN apt-get upgrade -y
RUN apt-get install -y curl git python python-dev ssh-client

RUN curl https://bootstrap.pypa.io/get-pip.py > get-pip.py
RUN python get-pip.py

# Install ansible
RUN git clone --recursive --branch v1.8.4 https://github.com/ansible/ansible
RUN cd ansible; pip install . ; cd ..

# Add entrypoint script
ADD job.sh /root/job.sh

# Add ssh keys
ADD id_rsa /root/.ssh/id_rsa
ADD id_rsa.pub /root/.ssh/id_rsa.pub

# Add ssh config
ADD ssh_config /root/.ssh/config

# Shell entry-point
CMD ["/root/job.sh"]
