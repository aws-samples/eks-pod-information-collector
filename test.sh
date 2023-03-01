#!/bin/bash

POD_NAME=${1:-''}   # Do we need a default value here?
NAMESPACE=${2:-'kube-system'}

function error() {
  echo -e "\n[ERROR] $* \n"
  exit 1
}

function warn() {
  echo -e "\n\t[WARNING] $* \n"
}

function validate_pod_ns(){
  if [[ -z $1 ]] || [[ -z $2 ]]; then
    warn "POD_NAME & NAMESPACE Both are required!!"
    warn "Collecting Default resources in KUBE-SYSTEM namespace" 
  fi
  echo $2
  if [[ ! $(kubectl get ns $2 2> /dev/null) ]] && [[ "$2" != 'kube-system' ]] ; then
    error "Namespace ${2} not found!!"
  elif [[ $(kubectl get pod $1 -n $2 2> /dev/null) ]]; then
    error "Pod ${1} not found!!"
  fi

  VALID_INPUTS="VALID"
}

echo $NAMESPACE
validate_pod_ns "${POD_NAME}" "${NAMESPACE}"
echo $VALID_INPUTS

if [[ "${VALID_INPUTS}" == 'VALID' ]]; then 
    echo "VALID_INPUTS"
else
    echo "NOT VALID"
fi