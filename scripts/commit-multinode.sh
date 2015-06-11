#!/usr/bin/env bash

### -------------- [ Variables ] --------------------
TAGS=${TAGS:-prepare,run,test}
OS_ANSIBLE_URL=${OS_ANSIBLE_URL:-https://github.com/stackforge/os-ansible-deployment}
OS_ANSIBLE_BRANCH=${OS_ANSIBLE_BRANCH:-master}
GERRIT_REFSPEC=${GERRIT_REFSPEC:-refs/changes/87/139087/14}
ANSIBLE_OPTIONS=${ANSIBLE_OPTIONS:--v}
TEMPEST_SCRIPT_PARAMETERS=${TEMPEST_SCRIPT_PARAMETERS:-scenario}
### -------------- [ Functions ] --------------------

env

cluster_tool(){
python - $@ <<EOP
import requests
import argparse
import sys
import os

def cluster_for_claim(clusters, claim):
        for cluster in clusters.json():
            if cluster.get('claim') == claim:
                print(cluster['short_name'])
                return 0
        return 1

def check_release(clusters, name):
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

get_infra_1_ip(){
  #Find the first node ip from the inventory
  grep -o -m 1 '10.127.[0-9]\+.[0-9]\+' \
    < inventory/commit-cluster-$CLUSTER_NUMBER
}

ssh_command(){
  infra_1_ip=$(get_infra_1_ip)
  : >> /tmp/env
  scp script_env $infra_1_ip:/tmp/env
  echo "Running command ${1}"
  ssh root@$infra_1_ip ". /tmp/env; ${1}"
}

ssh_osad_script(){
  echo "Running script ${1} from os-ansible-deployment/scripts."
  ssh_command "cd ~/rpc_repo; bash scripts/${1}.sh"
}

prepare(){
  run_jenkins_rpc_playbook_tag prepare
}

run(){
  echo "export DEPLOY_TEMPEST=yes" > script_env
  ssh_osad_script run-playbooks
}

test(){
  echo "export TEMPEST_SCRIPT_PARAMETERS=${TEMPEST_SCRIPT_PARAMETERS}" > script_env
  ssh_osad_script run-tempest

  # Get junit xml results from tempest so they can be interpreted by jenkins
  run_jenkins_rpc_playbook_tag get_tempest_report
}

clean(){
  run_jenkins_rpc_playbook_tag clean
}

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

claim(){
  until _claim | tee cluster | grep claimed
  do
    sleep 5
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

upgrade(){
  ssh_command "curl $UPGRADE_SCRIPT_URL >~/rpc_repo/scripts/upgrade_script.sh; cd ~/rpc_repo; bash scripts/upgrade_script.sh"
}

# A propterties file (Java key=value format) is produced to be read by the
# parent jenkins job. This is then used to inject CLUSTER_{NAME,CLAIM} into
# the env for the cleanup job, so the correct cluster is cleaned and released
write_properties(){
  {
    for var in $@
    do
      echo "${var}=${!var}"
    done
  } > properties
}


### -------------- [ Main ] --------------------

export CLUSTER_NUMBER=${CLUSTER_NAME#dev_sat6_jenkins_}

# Write properties is called early even though claim has not run yet, as
# CLUSTER_NAME may have been passed in. Write properties is also called after
# each tag incase claim has run. Its important that write_properties runs as
# early as possible as cleanup will fail if the necessary info has not been written.
write_properties CLUSTER_NAME CLUSTER_CLAIM

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

exit $rc
