#!/usr/bin/env bash

# ---------------------- [ shopts ] --------------------------------
set -e
set -x


# ---------------------- [ parameters ] --------------------------------
JENKINS_RPC_URL=${JENKINS_RPC_URL:-https://github.com/rcbops/jenkins-rpc}
JENKINS_RPC_BRANCH=${JENKINS_RPC_BRANCH:-master}
#STAGE (no default)
PLAYBOOK_DIR=${PLAYBOOK_DIR:-playbooks}
CREDS_FILE=${CREDS_FILE:-/var/creds/cloud10}


# ---------------------- [ common ] --------------------------------
# log environment
env

# Set HOME to /root
export HOME=/root
cd

# Clone jenkins-rpc repo
git clone git@github.com:rcbops/jenkins-rpc.git & wait %1
pushd jenkins-rpc/${PLAYBOOK_DIR}

# Source creds if available
[[ -f $CREDS_FILE ]] && source $CREDS_FILE

# Set build stage
export TAGS=$STAGE

# Set build cluster
export CLUSTER_NUMBER=${HOSTNAME#commit-cluster-}
bash ../scripts/commit-multinode.sh
