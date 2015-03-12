#!/usr/bin/env bash
set -x

CLUSTER_NUMBER=${CLUSTER_NUMBER:-1}
TAGS=${TAGS:-prepare,run,test}
OS_ANSIBLE_BRANCH=${OS_ANSIBLE_BRANCH:-master}
OS_ANSIBLE_URL=${OS_ANSIBLE_URL:-master}
GERRIT_REFSPEC=${GERRIT_REFSPEC:-refs/changes/87/139087/14}
ANSIBLE_OPTIONS=${ANSIBLE_OPTIONS:--vv}
VARS_DIR=vars

export PYTHONUNBUFFERED=1
export ANSIBLE_FORCE_COLOR=1

ansible-playbook \
  -i inventory/commit-cluster-$CLUSTER_NUMBER\
  -e@${VARS_DIR}/pip.yml\
  -e@${VARS_DIR}/packages.yml\
  -e@${VARS_DIR}/kernel.yml\
  -e@${VARS_DIR}/commit-multinode.yml\
  -e@${VARS_DIR}/misc.yml\
  -e os_ansible_url=${OS_ANSIBLE_URL}\
  -e os_ansible_branch=${OS_ANSIBLE_BRANCH}\
  -e cluster_number=${CLUSTER_NUMBER}\
  -e gerrit_refspec=${GERRIT_REFSPEC}\
  --tags $TAGS\
  $ANSIBLE_OPTIONS\
  commit-multinode.yml


