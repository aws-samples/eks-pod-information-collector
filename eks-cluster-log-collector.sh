#!/bin/bash

#Helper Functions

function print() {
  echo -e "$@"
}

function append() {
  echo "====================[$(echo $1 | tr '[:lower:]' '[:upper:]')]===================" >> $2
}

function error() {
  echo -e "\n\t[ERROR] $* \n"
  exit 1
}

function warn() {
  echo -e "\n\t[WARNING] $* \n"
}

#TODO: Can this be optimized?
# Function to validate the inputs
function validate_pod_ns(){
  if [[ -z $1 ]] && [[ -z $2 ]]; then
    warn "POD_NAME & NAMESPACE Both are required!!"
    warn "Collecting Default resources in KUBE-SYSTEM namespace!!" 
  else 
    if [[ ! $(kubectl get ns $2 2> /dev/null) ]] ; then
      error "Namespace ${2} not found!!"
    elif [[ ! $(kubectl get pod $1 -n $2 2> /dev/null) ]]; then
      error "Pod ${1} not found!!"
    fi
    VALID_INPUTS='VALID'
  fi
}

# Default Resrouce Lists
# Names of Default ConfigMaps
KUBE_SYSTEM_CM=(
  aws-auth
  coredns
  kube-proxy
  amazon-vpc-cni
)

# Names of Default Daemonsets and Deployment
KUBE_SYSTEM_DS_DEP=(
  aws-node
  kube-proxy
  coredns
)

# Parse & Validate Arguments
POD_NAME=${1:-''} 
NAMESPACE=${2:-''}
validate_pod_ns $POD_NAME $NAMESPACE

# Creating Output Directory
CLUSTER_INFO=$(kubectl config view --minify -ojsonpath='{.clusters[0]}')
CLUSTERNAME=$(echo $CLUSTER_INFO | sed 's/^[^=]*:cluster\///' | sed 's/..$//')
ROOT_OUTPUT_DIR=$PWD
TIME=$(date "+%Y%m%d-%Hh:%Mm:%Ss")
OUTPUT_DIR_NAME=$(sed 's|r/|r-|g' <<< "${CLUSTERNAME}")_$TIME  
mkdir "$OUTPUT_DIR_NAME"
OUTPUT_DIR="$PWD/${OUTPUT_DIR_NAME}"

# Default Output File Names:
CLUSTER_INFO_FILE="${OUTPUT_DIR}/Cluster_Info.json"
CONFIG="${OUTPUT_DIR}/ConfigMaps.yaml"
DAEMONSET="${OUTPUT_DIR}/DaemonSets.yaml"
DEPLOYMENT="${OUTPUT_DIR}/Deployments.yaml"

# Collecting Cluster Details
print "Collecting information in Directory: ${OUTPUT_DIR}"
print "Collecting Cluster Details, Review File: Cluster_Info.json "
echo $CLUSTER_INFO > "$CLUSTER_INFO_FILE"

# Collecting Default resources in KUBE-SYSTEM
print "Collecting Default resources in KUBE-SYSTEM, Review Files ConfigMaps.yaml, DaemonSets.yaml, Deployments.yaml"

for resource in ${KUBE_SYSTEM_CM[*]}; do
  append " ${resource} " "$CONFIG"
  kubectl get configmap -n kube-system ${resource} -o yaml >> "$CONFIG"
  append "" "$CONFIG"
done

for resource in ${KUBE_SYSTEM_DS_DEP[*]}; do
  if [[ ${resource} == 'coredns' ]] ; then 
    append " ${resource} " "$DEPLOYMENT"
    kubectl get deployment -n kube-system ${resource} -o yaml >> "$DEPLOYMENT"
    append "" "$DEPLOYMENT"
  else
    append " ${resource} " "$DAEMONSET"
    kubectl get daemonset -n kube-system ${resource} -o yaml >> "$DAEMONSET"
    append "" "$DAEMONSET"
  fi
done

# Collecting resources for User Desired POD and Namespace
if [[ ${VALID_INPUTS} == 'VALID' ]] ; then 

  # Creating POD specific output directory
  POD_OUTPUT_DIR="${OUTPUT_DIR}/${POD_NAME}_${NAMESPACE}"
  mkdir "$POD_OUTPUT_DIR"

  print "Collecting Resource related to ${POD_NAME}, Review Files in Directory: ${POD_NAME}_${NAMESPACE}"
  
  #Get Pod Details 
  kubectl get pod $POD_NAME -n $NAMESPACE -ojson > "${POD_OUTPUT_DIR}/Pod_${POD_NAME}.json" 
  kubectl describe pod  $POD_NAME -n $NAMESPACE > "${POD_OUTPUT_DIR}/Pod_${POD_NAME}.txt"
  

  # Get NODE Info.
  NODE=$(kubectl get pod $POD_NAME -n $NAMESPACE -ojsonpath='{.spec.nodeName}') 
  kubectl get node $NODE -ojson > "${POD_OUTPUT_DIR}/Node_${NODE}.json"
  kubectl describe node $NODE > "${POD_OUTPUT_DIR}/Node_${NODE}.txt"

  # TODO: Add support for non apps/v1 resources

  # Get Owner Details of DS/RS/Deploy/STS
  POD_OWNER_KIND=$(kubectl get pod $POD_NAME -n $NAMESPACE -ojsonpath='{.metadata.ownerReferences[?(@.apiVersion=="apps/v1")].kind}')  # All such repeated kubectl calls can be reduced by using jq
  POD_OWNER_NAME=$(kubectl get pod $POD_NAME -n $NAMESPACE -ojsonpath="{.metadata.ownerReferences[?(@.kind=="\"${POD_OWNER_KIND}\"")].name}")
  kubectl get $POD_OWNER_KIND $POD_OWNER_NAME -n $NAMESPACE -o json > "${POD_OUTPUT_DIR}/${POD_OWNER_KIND}_${POD_OWNER_NAME}.json"
  kubectl describe $POD_OWNER_KIND $POD_OWNER_NAME -n $NAMESPACE > "${POD_OUTPUT_DIR}/${POD_OWNER_KIND}_${POD_OWNER_NAME}.txt"

  # TODO: Can this be achieved using while?
  if [[ $(kubectl get $POD_OWNER_KIND $POD_OWNER_NAME -n $NAMESPACE -ojsonpath={.metadata.ownerReferences}) ]] ; then
    SUPER_OWNER_KIND=$(kubectl get $POD_OWNER_KIND $POD_OWNER_NAME -n $NAMESPACE -ojsonpath='{.metadata.ownerReferences[?(@.apiVersion=="apps/v1")].kind}')
    SUPER_OWNER_NAME=$(kubectl get $POD_OWNER_KIND $POD_OWNER_NAME -n $NAMESPACE -ojsonpath="{.metadata.ownerReferences[?(@.kind=="\"${SUPER_OWNER_KIND}\"")].name}")
    kubectl get $SUPER_OWNER_KIND $SUPER_OWNER_NAME -n $NAMESPACE -o json > "${POD_OUTPUT_DIR}/${SUPER_OWNER_KIND}_${SUPER_OWNER_NAME}.json"
    kubectl describe $SUPER_OWNER_KIND $SUPER_OWNER_NAME -n $NAMESPACE > "${POD_OUTPUT_DIR}/${SUPER_OWNER_KIND}_${SUPER_OWNER_NAME}.txt"
  fi

  # Get Service Account details
  POD_SA_NAME=$(kubectl get $POD_OWNER_KIND $POD_OWNER_NAME -n $NAMESPACE -ojsonpath='{.spec.template.spec.serviceAccountName}')
  kubectl get serviceaccount $POD_SA_NAME -n $NAMESPACE -ojson > "${POD_OUTPUT_DIR}/SA_${POD_SA_NAME}.json"

  # Get Service Details 
  LABEL_LIST=$(kubectl get pod $POD_NAME -n $NAMESPACE --show-labels --no-headers | awk '{print $NF}' | sed 's/\,/\n/g')

  # Iterate over labels to find the service because their no direct reference to service and deployment
  for label in ${LABEL_LIST[*]}; do
    kubectl get svc -n $NAMESPACE -l $label -ojson >> "${POD_OUTPUT_DIR}/Services.json"
    kubectl describe svc -n $NAMESPACE -l $label >> "${POD_OUTPUT_DIR}/Services.txt"
  done

  # TODO: Can we get Ingress resources as well?

  # Get PVC/PV for the pod
  VOLUMES_CLAIMS=$(kubectl get pod $POD_NAME -n $NAMESPACE -ojsonpath='{range .spec.volumes[*]}{.persistentVolumeClaim.claimName}{"\n"}{end}') # Get PVC Names
  for claim in ${VOLUMES_CLAIMS[*]}; do
    kubectl get pvc $claim -n $NAMESPACE -ojson > "${POD_OUTPUT_DIR}/PVC_${claim}.json"
    kubectl describe pvc $claim -n $NAMESPACE > "${POD_OUTPUT_DIR}/PVC_${claim}.json"
    PV=$(kubectl get pvc $claim -n $NAMESPACE -o jsonpath={'.spec.volumeName'})
    kubectl get pv $PV -o json > "${POD_OUTPUT_DIR}/PV_${PV}.json"  #Get Associated PV JSON
    kubectl describe pv $PV > "${POD_OUTPUT_DIR}/PV_${PV}.txt"
  done

  # Get Mounted ConfigMaps for the pod
  # TODO: Should we get/read the configMap as well?
  CMS=$(kubectl get pod $POD_NAME -n $NAMESPACE -ojsonpath='{range .spec.volumes[*]}{.configMap.name}{"\n"}{end}')
  for cm in ${CMS[*]}; do
    if [[ ! $(kubectl get cm $cm -n $NAMESPACE) ]] ; then  #Get Associated ConfigMap JSON
      echo "ConfigMap ${cm} is missing"
    fi
  done
  
fi


