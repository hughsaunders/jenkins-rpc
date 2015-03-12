#!/usr/bin/env bash

set -e

CREDS_FILE=${CREDS_FILE:-cloud10}
JENKINS_RPC_URL=${JENKINS_RPC_URL:-git@github.com:rcbops/jenkins-rpc.git}
JENKINS_RPC_BRANCH=${JENKINS_RPC_BRANCH:-master}


env

# Set HOME to /root
export HOME=/root

# Switch to home directory
cd

# We haven't trapped yet
trapped=0

# Trap setter; passes signal name as $1
set_trap() {
      func=$1; shift
  for sig; do
    trap "$func $sig" "$sig"
  done
}

# Cleanup trap
cleanup() {
  # If first trap
  if [[ $trapped -eq 0 ]]
  then
    # We've trapped now
    trapped=1
    # Store exit code
    case $1 in
      INT|TERM|ERR)
        retval=1;; # exit 1 on INT, TERM, ERR
      *)
        retval=$1;; # specified code otherwise
    esac
    # Kill process group, retriggering trap
    kill 0
  fi
  # Disable trap
  trap - INT TERM ERR

  # Exit
  exit $retval
}

# Set the trap
set_trap cleanup INT TERM ERR

# Clone jenkins-rpc repo
git clone -b $JENKINS_RPC_BRANCH $JENKINS_RPC_URL & wait %1

# Move into jenkins-rpc
pushd jenkins-rpc/playbooks

# Read creds for cloud account, used for glance-swift
# /var/creds is mounted from the host using -v
# when the docker instance is started.
[[ -e /var/creds/${CREDS_FILE} ]] && source /var/creds/${CREDS_FILE}

# Prepare the lab
# No need to export env vars, as they will be inherited anyway
bash ../scripts/commit-multinode.sh

popd

# run ansible-lxc-rpc
ssh $(<target.ip) ./target.sh & wait %1

cleanup 0
