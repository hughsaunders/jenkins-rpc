#!/usr/bin/env bash

export CLUSTER_NUMBER=${CLUSTER_NUMBER:-1}
export TAGS=${TAGS:-prepare,run,test}
export TARGET_BRANCH=${TARGET_BRANCH:-master}
export GERRIT_REFSPEC=${GERRIT_REFSPEC:-refs/changes/87/139087/14}
export ANSIBLE_OPTIONS=${ANSIBLE_OPTIONS:--v}
export PYTHONUNBUFFERED=1
export ANSIBLE_FORCE_COLOR=1

ansible-playbook \
  -i inventory/commit-cluster-$CLUSTER_NUMBER\
  -e@vars/packages.yml\
  -e@vars/pip.yml\
  -e@vars/kernel.yml\
  -e@vars/commit-multinode.yml\
  -e@vars/branch-vars-${TARGET_BRANCH}.yml\
  -e cluster_number=${CLUSTER_NUMBER}\
  -e GERRIT_REFSPEC=${GERRIT_REFSPEC}\
  --tags $TAGS\
  $ANSIBLE_OPTIONS\
  commit-multinode.yml


