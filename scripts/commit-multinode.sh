#!/usr/bin/env bash

# This script is for preparing, deploying and testing RPC/OSAD on SAT6
# Hardware.  TAGS is a list of function that are run until completion or
# something fails FINALLY_TAGS is a list of tags that are run after TAGS, they
# do not affect success of the job, and execution is stopped on failure.

# The idea of the tag system is to be able to have flexible jenkins jobs,
# without complex job relationships in jenkins.

# Example: Standard run: TAGS=claim prepare run test FINALLY_TAGS=clean release
# If clean fails, release will not be run - this is good the cluster will still
# be claimed so no more jobs will be run on the unclean cluster.

# Example 2: Upgrade job: TAGS=claim prepare run test upgrade test
#                         FINALLY_TAGS=clean release

# Example 3: Take cluster out of service: TAGS=claim FINALLY_TAGS=
# Example 4: Return cluster to pool: TAGS=clean release FINALLY_TAGS=

# Example 5: Pre-clean, this delays cleanup till a cluster is next used - good
# for inspecting results of a run, but increases time-to-result when not
# running at capacity: TAGS=claim clean prepare run test
#                       FINALLY_TAGS=release


### -------------- [ Variables ] --------------------
#TAGS
#FINALLY_TAGS
OS_ANSIBLE_URL=${OS_ANSIBLE_URL:-https://github.com/stackforge/os-ansible-deployment}
OS_ANSIBLE_BRANCH=${OS_ANSIBLE_BRANCH:-master}
GERRIT_REFSPEC=${GERRIT_REFSPEC:-refs/changes/87/139087/14}
ANSIBLE_OPTIONS=${ANSIBLE_OPTIONS:--v}
TEMPEST_SCRIPT_PARAMETERS=${TEMPEST_SCRIPT_PARAMETERS:-scenario}
### -------------- [ Functions ] --------------------

env

# python script for interacting with djeep where json interpreation is
# necessary
cluster_tool(){
python - $@ <<EOP
import requests
import argparse
import sys
import os

def cluster_for_claim(clusters, claim):
        """ return the name of the first cluster claimed with the specified string """
        for cluster in clusters.json():
            if cluster.get('claim') == claim:
                print(cluster['short_name'])
                return 0
        return 1

def check_release(clusters, name):
        """ Check that the specified cluster has no claim """
        for cluster in clusters.json():
                if cluster['short_name'] == name and cluster['claim'] == "":
                        return 0
        return 1

def main():
        parser=argparse.ArgumentParser()
        parser.add_argument('command', choices=['cluster_for_claim','check_release'])
        parser.add_argument('arg')

        args = parser.parse_args()

        base_url = "${DJEEP_URL}/api"

        clusters = requests.get('%(base_url)s/clusters' % {'base_url': base_url} )

        router = {'cluster_for_claim': cluster_for_claim,
                  'check_release': check_release}

        return router[args.command](clusters, args.arg)

if __name__ == "__main__":
        sys.exit(main())
EOP
}

run_jenkins_rpc_playbook_tag(){
  echo "Running tag ${1} from jenkins-rpc/commit-multinode.yml"
  ansible-playbook \
    -i inventory/commit-cluster-$CLUSTER_NUMBER\
    -e@vars/packages.yml\
    -e@vars/pip.yml\
    -e@vars/kernel.yml\
    -e@vars/commit-multinode.yml\
    -e cluster_number=${CLUSTER_NUMBER}\
    -e GERRIT_REFSPEC=${GERRIT_REFSPEC}\
    -e os_ansible_url=${OS_ANSIBLE_URL}\
    -e os_ansible_branch=${OS_ANSIBLE_BRANCH}\
    --tags $1\
    $ANSIBLE_OPTIONS\
    commit-multinode.yml
}

# Run a command on the first infra node, $PWD/script_env is scpd and sourced
# before the command is run.
ssh_command(){
  #Find the first node ip from the inventory
  [[ -z $infra_1_ip ]] && infra_1_ip=$(grep -o -m 1 '10.127.[0-9]\+.[0-9]\+' \
                          < inventory/commit-cluster-$CLUSTER_NUMBER)
  : >> /tmp/env
  scp script_env $infra_1_ip:/tmp/env
  echo "Running command ${1}"
  ssh root@$infra_1_ip ". /tmp/env; ${1}"
}

ssh_osad_script(){
  echo "Running script ${1} from os-ansible-deployment/scripts."
  ssh_command "cd ~/rpc_repo; bash scripts/${1}.sh"
}

# Prepare cluster - this step handles all the prereqs for OSAD
prepare(){
  run_jenkins_rpc_playbook_tag prepare
}

# Run OSAD Playbooks
run(){
  echo "export DEPLOY_TEMPEST=yes" > script_env
  ssh_osad_script run-playbooks
}

# Run tempest
test(){
  echo "export TEMPEST_SCRIPT_PARAMETERS=${TEMPEST_SCRIPT_PARAMETERS}" > script_env
  ssh_osad_script run-tempest
}

# Rekick cluster nodes
clean(){
  run_jenkins_rpc_playbook_tag clean
}

# private function for attempting to claim a cluster
_claim(){
  if [[ ! -z "$CLUSTER_NAME" ]]
  then
    echo "Claiming name: $CLUSTER_NAME with claim: $CLUSTER_CLAIM"
    curl -X POST $DJEEP_URL/api/cluster/claim/$CLUSTER_CLAIM/$CLUSTER_NAME 2>/dev/null
  else
    echo "Claiming cluster with prefix $CLUSTER_PREFIX with claim: $CLUSTER_CLAIM"
    curl -X POST $DJEEP_URL/api/cluster/claim/$CLUSTER_CLAIM/prefix/$CLUSTER_PREFIX 2>/dev/null
  fi
}

# Try claiming a cluster indefinitely until one is available. Store name/Number
# in env
claim(){
  until _claim | tee cluster | grep claimed
  do
    sleep 120
  done
  export CLUSTER_NAME=$(awk '/claimed/{print $2}' < cluster)
  export CLUSTER_NUMBER=${CLUSTER_NAME#dev_sat6_jenkins_}

  # Check cluster status to ensure the claim is correct.
  [[ "$CLUSTER_NAME" == "$(cluster_tool cluster_for_claim $CLUSTER_CLAIM)" ]]
}

release(){
  echo "Releasing claim $CLUSTER_CLAIM from $CLUSTER_NAME"
  curl -X DELETE $DJEEP_URL/api/cluster/claim/$CLUSTER_CLAIM/$CLUSTER_NAME 2>/dev/null

  # Check that the claim has been released correctly
  cluster_tool check_release $CLUSTER_NAME
}

# Download and run the specified upgrade script on the first infra node
upgrade(){
  ssh_command "curl $UPGRADE_SCRIPT_URL >~/rpc_repo/scripts/upgrade_script.sh; cd ~/rpc_repo; bash scripts/upgrade_script.sh"
}

# Produce a Java style properties file to store information that may not be
# known before running the job (eg the cluster that is allocated)
write_properties(){
  {
    for var in $@
    do
      echo "${var}=${!var}"
    done
  } > properties
}

### -------------- [ Main ] --------------------

# Strip prefix to obtain cluster number
export CLUSTER_NUMBER=${CLUSTER_NAME#dev_sat6_jenkins_}

# return code
rc=0

# run the tags that are required (from the $TAGS parameter) until something breaks
rc=0
for tag in ${TAGS}
do
  $tag || { rc=1; break; }
  write_properties CLUSTER_NAME CLUSTER_CLAIM
done

# run tags from the list FINALLY_TAGS, these are intended to do cleanup.
for tag in ${FINALLY_TAGS}
do
  $tag || break
done

# Return code is only affected by TAGS, not FINALLY_TAGS
exit $rc
