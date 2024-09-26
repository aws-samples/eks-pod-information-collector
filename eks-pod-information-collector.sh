#!/bin/bash

set -o pipefail

# export KUBECONFIG='config'
# Default Resrouce Lists
# ConfigMaps
KUBE_SYSTEM_CM=(
  aws-auth
  coredns
  kube-proxy
)

# Daemonsets and Deployment
KUBE_SYSTEM_DS_DEP=(
  aws-node
  kube-proxy
  coredns
)

#Helper Functions

colorClear='\033[0m'
colorError='\033[1;31m'
colorWarning='\033[1;33m'
colorAttention='\033[1;36m'
colorDone='\033[1;32m'

function print() {
  echo -e "$@"
}

function log() {
  local TIME
  TIME=$(date -u "+%Y-%m-%dT%H:%M:%S_%Z")
  if [[ ${1} == '-p' ]]; then
    print "${2}..."
    print "${TIME}: $2" >> "${LOG_FILE}"
  else
    print "${TIME}: $*" >> "${LOG_FILE}"
  fi
}

function append() {
  print "====================[$(echo "${1}" | tr '[:lower:]' '[:upper:]')]===================" >> "${2}"
}

function error() {
  print "\n\t${colorError}[ERROR]: $* \n\t${colorError}[ERROR]: Check logs in file ./${LOG_FILE} ${colorClear}\n"
  log "[ERROR]: $*"
  rm -rf "${OUTPUT_DIR}"
  exit 1
}

function warn() {
  print "\n\t${colorWarning}[WARNING]: $* ${colorClear}\n"
  log "[WARNING]: $*"
}

function prompt() {
  print "${colorAttention}******** ATTENTION ********${colorClear}"
  print "${colorAttention} $* ${colorClear}"
  print "${colorAttention}***************************\n${colorClear}"
  log "Giving prompt message to user - $*"
}

function help() {
  print "\nUsage: ./$(basename "${0}") -p <Podname> -n <Namespace of the pod> -s [Service Name] -i [Ingress Name] "
  print "\nRequired:"
  print "  -p, --podname \tPod name \t(Required)"
  print "  -n, --namespace \tPod Namespace \t(Required)"
  print "\nOPTIONAL:"
  print "  -s, --service \tService name associated with the Pod"
  print "  -i, --ingress \tIngress name associated with the Pod"
  print "  -h, --help \t\tShow Help menu"
}

function get_filename() {
  local TIME
  TIME=$(date -u "+%Y-%m-%dT%H:%M:%S_%Z")
  local FILE
  FILE="${OUTPUT_DIR}/${1}-${TIME}.${2}"
  echo "${FILE}"
}

function get_object() {
  local KIND=$1
  local NAME=$2
  local NS=$3

  if [[ "${NS}" == "" ]]; then
    NS="${NAMESPACE}"
  fi

  if [[ -n "${NAME}" ]]; then
    log -p "Collecting information related to ${KIND}: \"${NAME}\""

    log "Getting ${KIND}: \"${NAME}\""
    local FILE
    FILE=$(get_filename "${KIND}_${NAME}" "json")
    OBJECT=$(kubectl get "${KIND}" -n "${NS}" "${NAME}" -ojson | sed -e '/"env": \[/,/]/d; s/"kubectl.kubernetes.io\/last-applied-configuration": .*/"kubectl.kubernetes.io\/last-applied-configuration": ""/')

    if [ "$OUTPUT" = "yaml" ]; then
      FILE_YAML=$(get_filename "${KIND}_${NAME}" "yaml")
      OBJECT_YAML=$(kubectl get "${KIND}" -n "${NS}" "${NAME}" -oyaml)
      echo "${OBJECT_YAML}" >> "${FILE_YAML}"
    else
      echo "${OBJECT}" >> "${FILE}"
    fi

    log "Describing ${KIND}: \"${NAME}\""
    local FILE
    FILE=$(get_filename "${KIND}_${NAME}" "txt")
    kubectl describe "${KIND}" -n "${NS}" "${NAME}" | sed '/Environment:/,/Mounts:/ { /Mounts:/!d; }' >> "${FILE}"
  fi
}

# Parse Input Parameters
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -h | --help)
      help && exit 0
      ;;
    -p | --podname)
      POD_NAME=$2
      shift
      shift
      ;;
    -n | --namespace)
      NAMESPACE=$2
      shift
      shift
      ;;
    -s | --service)
      SERVICE_NAME=$2
      shift
      shift
      ;;
    -i | --ingress)
      INGRESS_NAME=$2
      shift
      shift
      ;;
    -o | --output)
      OUTPUT=$2
      shift
      shift
      ;;
    *)
      help && exit 1
      shift
      shift
      ;;
  esac
done

# Main functions
#Verify KUBECTL command installation
function check_Kubectl() {
  if (! command -v kubectl >> /dev/null); then
    error "KUBECTL not found. Please install KUBECTL or make sure the PATH variable is set correctly. For more information: https://docs.aws.amazon.com/eks/latest/userguide/install-kubectl.html"
  fi

  local CONFIG
  CONFIG=$(kubectl config view --minify 2> /dev/null)
  if [[ -z $CONFIG ]]; then
    error "Make sure to set KUBECONFIG & Current Context. For more information visit: https://docs.aws.amazon.com/eks/latest/userguide/create-kubeconfig.html "
  fi
}

function check_permissions() {
  if [[ $(kubectl auth can-i 'list' '*' -A 2> /dev/null) == 'no' || $(kubectl auth can-i 'get' '*' -A 2> /dev/null) == 'no' ]]; then
    error "Please make sure you have Read (get,list) permission for the EKS cluster!!"
  fi
}

# Validate the inputs
function validate_args() {
  log -p "Validating input arguments"
  if [[ -z $POD_NAME ]] || [[ -z "${NAMESPACE}" ]]; then
    help
    error "POD_NAME & NAMESPACE Both arguments are required!!"
  else
    log "Getting Namespace: \"${NAMESPACE}\" to verify if it exists"
    if [[ ! $(kubectl get ns "${NAMESPACE}" 2> /dev/null) ]]; then
      error "Namespace ${NAMESPACE} not found!!"
    else
      log "Getting Pod: \"${POD_NAME}\" to verify if it exists"
      if [[ ! $(kubectl get pod "${POD_NAME}" -n "${NAMESPACE}" 2> /dev/null) ]]; then
        error "Pod ${POD_NAME} not found!!"
      fi
      if [[ -n "${SERVICE_NAME}" ]]; then
        log "Getting Service: \"${SERVICE_NAME}\" to verify if it exists"
        if [[ ! $(kubectl get service "${SERVICE_NAME}" -n "${NAMESPACE}" 2> /dev/null) ]]; then
          error "Service ${SERVICE_NAME} not found!!"
        fi
      fi
      if [[ -n "${INGRESS_NAME}" ]]; then
        log "Getting Ingress: \"${INGRESS_NAME}\" to verify if it exists"
        if [[ ! $(kubectl get ingress "${INGRESS_NAME}" -n "${NAMESPACE}" 2> /dev/null) ]]; then
          error "Ingress ${INGRESS_NAME} not found!!"
        fi
      fi
      export VALID_INPUTS='VALID'
      log "All arguments are valid, proceeding with execution"
    fi
  fi
}

# Collect Cluster & IAM information
function get_cluster_iam() {
  log "Collecting kubectl EXEC configuration from KUBECONFIG"
  local EXEC_COMMAND
  local EXEC_ARGS
  local PROFILE
  local CLUSTER
  local REGION
  local ROLE
  EXEC_COMMAND=$(kubectl config view --minify -ojsonpath='{.users[0].user.exec.command}' | sed 's/.*\///')
  EXEC_ARGS=$(kubectl config view --minify -ojsonpath='{.users[0].user.exec.args}')
  log "Collecting CLUSTER_NAME & IAM_ARN information"
  if [[ ! $(kubectl config view --minify -ojsonpath='{.users[0].user.exec.env}') == '<nil>' ]]; then
    log "Identifying if AWS_PROFILE is used in EXEC configuration"
    PROFILE=$(kubectl config view --minify -ojsonpath='{.users[0].user.exec.env[?(@.name=="AWS_PROFILE")].value}')
  fi
  if [[ ${EXEC_COMMAND} == 'aws' ]]; then
    CLUSTER=$(echo "${EXEC_ARGS}" | sed -n -e 's/.*"--cluster-name","\([^"]*\)".*/\1/p; s/.*"--cluster-id","\([^"]*\)".*/\1/p')
    REGION=$(echo "${EXEC_ARGS}" | sed -n -e 's/.*"--region","\([^"]*\)".*/\1/p')
    ROLE=$(echo "${EXEC_ARGS}" | sed -n -e 's/.*"--role-arn","\([^."]*\).*,/\1/p' | sed 's/".*//')
    log -p "Collected Cluster Name: \"${CLUSTER}\" from current context"
    if [[ -z $ROLE ]]; then
      log "Performing aws sts get-caller-identity"
      if [[ -z $PROFILE ]]; then
        ROLE=$(aws sts get-caller-identity --region "${REGION}" --query "Arn" --output text)
      else
        ROLE=$(aws sts get-caller-identity --profile "${PROFILE}" --region "${REGION}" --query "Arn" --output text)
      fi
    fi
    log "Identified IAM-ARN ${ROLE}"
  elif [[ ${EXEC_COMMAND} == 'aws-iam-authenticator' ]]; then
    CLUSTER=$(echo "${EXEC_ARGS}" | sed -n -e 's/.*"-i","\([^"]*\)".*/\1/p; s/.*"--cluster-id","\([^"]*\)".*/\1/p')
    REGION=$(echo "${EXEC_ARGS}" | sed -n -e 's/.*"--region","\([^"]*\)".*/\1/p')
    if [[ -z $REGION ]]; then
      REGION=$(kubectl config view --minify -ojsonpath='{.users[0].user.exec.env[?(@.name=="AWS_DEFAULT_REGION")].value}')
    fi
    ROLE=$(echo "${EXEC_ARGS}" | sed -n -e 's/.*"-r","\([^"]*\)".*/\1/p; s/.*"--role","\([^"]*\)".*/\1/p')
    log -p "Collected Cluster Name: \"${CLUSTER}\" from current context"
    if [[ -z $ROLE ]]; then
      local TOKEN
      log "Capturing aws-iam-authenticator token for IAM ARN identification"
      if [[ -z $PROFILE ]]; then
        TOKEN=$(aws-iam-authenticator token -i "${CLUSTER}" --region "${REGION}" --token-only)
      else
        export AWS_PROFILE="${PROFILE}"
        TOKEN=$(aws-iam-authenticator token -i "${CLUSTER}" --region "${REGION}" --token-only)
        unset AWS_PROFILE
      fi
      log "Performing token verification for IAM ARN identification using aws-iam-authenticator"
      ROLE=$(aws-iam-authenticator verify --token "${TOKEN}" -i "${CLUSTER}" -ojson | sed -n 's/.*"CanonicalARN": "\(.*\)".*/\1/p')
    fi
    log "Identified IAM-ARN ${ROLE}"
  fi

  if [[ -z $ROLE ]]; then
    local ROLE='<unknown>'
    log "Could not identify IAM-ARN, setting IAM-ARN to ${ROLE}"
  fi
  export CLUSTER_NAME="${CLUSTER}"
  export IAM_ARN="${ROLE}"
}

# Collect Cluster Info
function get_cluster_info() {
  # Creating Output Directory
  OUTPUT_DIR_NAME="${CLUSTER_NAME}_${START_TIME}"
  OUTPUT_DIR="$PWD/${OUTPUT_DIR_NAME}"
  mkdir "${OUTPUT_DIR}"
  print "Collecting information in directory: \"${OUTPUT_DIR_NAME}\""
  log -p "Collecting additional Cluster infromation"
  local CLUSTER_INFO_FILE
  CLUSTER_INFO_FILE=$(get_filename "Cluster_Info" "json")
  local CLUSTER_INFO
  CLUSTER_INFO=$(kubectl config view --minify -ojsonpath='{.clusters[0]}')
  local VERSION
  log -p "Collecting version"
  VERSION=$(kubectl version --short 2> /dev/null)
  if [[ -z $VERSION ]]; then
    VERSION=$(kubectl version 2> /dev/null)
  fi
  local CLUSTER_VERSION
  CLUSTER_VERSION=$(echo "$VERSION" | sed -nE 's/.*Server Version: v([0-9]+\.[0-9]+\.[0-9]+).*/\1/p')
  local KUBECTL_VERSION
  KUBECTL_VERSION=$(echo "$VERSION" | sed -nE 's/.*Client Version: v([0-9]+\.[0-9]+\.[0-9]+).*/\1/p')
  local CLUSTER_INFO
  CLUSTER_INFO=${CLUSTER_INFO%?}",\"serverVersion\": \"${CLUSTER_VERSION}\", \"clientVersion\": \"${KUBECTL_VERSION}\",\"iamARN\": \"${IAM_ARN}\"}"
  echo "${CLUSTER_INFO}" > "${CLUSTER_INFO_FILE}"
  unset CLUSTER_NAME
  unset IAM_ARN
  unset START_TIME
}

function get_default_resources() {
  OUTPUT_DIR="${OUTPUT_DIR_NAME}/default"
  mkdir "${OUTPUT_DIR}"
  log -p "Collecting Default resources in KUBE-SYSTEM namespace"
  log "Collecting KUBE-SYSTEM configMaps"
  for resource in "${KUBE_SYSTEM_CM[@]}"; do
    get_object "configmap" "${resource}" "kube-system"
  done

  log "Collecting KUBE-SYSTEM deployments & daemonsets"
  for resource in "${KUBE_SYSTEM_DS_DEP[@]}"; do
    if [[ ${resource} == 'coredns' ]]; then
      get_object "deployment" "${resource}" "kube-system"
    else
      get_object "daemonset" "${resource}" "kube-system"
    fi
  done

  # Collect Webhooks
  MUTATING_WEBHOOKS_FILE=$(get_filename "MutatingWebhook" "json")
  VALIDATING_WEBHOOKS_FILE=$(get_filename "ValidatingWebhook" "json")
  log "Collecting MutattingWebhookConfigurations"
  kubectl get mutatingwebhookconfiguration -ojsonpath='{.items}' > "$MUTATING_WEBHOOKS_FILE"
  log "Collecting ValidatingWebhookConfigurations"
  kubectl get validatingwebhookconfiguration -ojsonpath='{.items}' > "$VALIDATING_WEBHOOKS_FILE"

  # Collect StorageClasses
  STORAGE_CLASSES_FILE=$(get_filename "Storage_Classes" "json")
  log "Collecting StorageClasses"
  kubectl get sc -ojsonpath='{.items}' > "${STORAGE_CLASSES_FILE}"
}

function get_pod() {
  # Creating POD specific output directory
  OUTPUT_DIR="${OUTPUT_DIR_NAME}/${POD_NAME}_${NAMESPACE}"
  mkdir "$OUTPUT_DIR"
  #Get Pod Details
  get_object "pod" "${POD_NAME}"
  local POD=$OBJECT
  NODE_NAME=$(echo "$POD" | sed -n 's/.*"nodeName": "\([^"]*\)".*/\1/p')
  get_object "node" "${NODE_NAME}"

  log "Identifying Owner References of Pod: \"${POD_NAME}\""
  POD_OWNER_KIND=$(echo "$POD" | sed -n '/"ownerReferences"/,/^[[:space:]]*}/ s/.*"kind": "\(.*\)".*/\1/p' | sed 's/".*//')
  POD_OWNER_NAME=$(echo "$POD" | sed -n '/"ownerReferences"/,/^[[:space:]]*}/ s/.*"kind": "\(.*\)".*"name": "\(.*\)", "uid":.*/\2/p' | sed 's/".*//')

  while [ ! "${POD_OWNER_KIND}" == '' ]; do
    get_object "$POD_OWNER_KIND" "$POD_OWNER_NAME"
    local OWNER=$OBJECT
    POD_OWNER_KIND=$(echo "$OWNER" | sed -n '/"ownerReferences"/,/^[[:space:]]*}/ s/.*"kind": "\(.*\)".*/\1/p' | sed 's/".*//')
    POD_OWNER_NAME=$(echo "$OWNER" | sed -n '/"ownerReferences"/,/^[[:space:]]*}/ s/.*"kind": "\(.*\)".*"name": "\(.*\)", "uid":.*/\2/p' | sed 's/".*//')
  done

  # Get Service Account details
  POD_SA_NAME=$(echo "$POD" | sed -n 's/.*"serviceAccountName": "\([^"]*\)".*/\1/p')
  get_object serviceaccount "$POD_SA_NAME"
}

function get_svc_ingress() {
  # Get Service Details
  if [[ -n $SERVICE_NAME ]]; then
    get_object service "$SERVICE_NAME"
    local SERVICE=$OBJECT
    log "Identifying Anotation & Spec of Service: \"${SERVICE_NAME}\""
    ANN=$(echo "$SERVICE" | sed -n 's/.*"service.beta.kubernetes.io\/aws-load-balancer-type": "\(.*\)".*/\1/p' | sed 's/".*//')
    SPEC=$(echo "$SERVICE" | sed -n 's/.*"loadBalancerClass": "\(.*\)".*/\1/p' | sed 's/",.*//')
    [[ ! $ANN ]] && INGRESS_CLASS=$SPEC || INGRESS_CLASS=$ANN

    if [[ ${INGRESS_CLASS} == 'external' || ${INGRESS_CLASS} == 'service.k8s.aws/nlb' ]]; then
      log -p "Service: \"${SERVICE_NAME}\" is using AWS Load Balancer Controller"
      COLLECT_LBC_LOGS='YES'
    fi
  fi

  if [[ -n $INGRESS_NAME ]]; then
    get_object ingress "$INGRESS_NAME"
    local INGRESS=$OBJECT
    log "Identifying Anotation & Spec of Service: \"${INGRESS_NAME}\""
    ANN=$(echo "$INGRESS" | sed -n 's/.*"kubernetes.io\/ingress.class": "\(.*\)".*/\1/p' | sed 's/".*//')
    SPEC=$(echo "$INGRESS" | sed -n 's/.*"ingressClassName": "\(.*\)".*/\1/p' | sed 's/".*//')
    [[ ! $ANN ]] && INGRESS_CLASS=$SPEC || INGRESS_CLASS=$ANN

    if [[ ${INGRESS_CLASS} == 'alb' ]]; then
      log -p "Ingress: \"${INGRESS_NAME}\" is using AWS Load Balancer Controller"
      COLLECT_LBC_LOGS='YES'
    fi
  fi

  if [[ ${COLLECT_LBC_LOGS} == 'YES' ]]; then
    AWS_LBC_FILE=$(get_filename "aws-lbc" "json")
    log -p "Collecting AWS Load Balancer Controller deployment information & logs"
    log "Getting AWS Load Balancer Controller deployment"
    kubectl get deployment -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller -ojsonpath='{.items}' > "${AWS_LBC_FILE}"
    AWS_LBC_LOG_FILE=$(get_filename "aws-lbc" "log")
    log "Getting AWS Load Balancer Controller deployment logs"
    kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=-1 > "${AWS_LBC_LOG_FILE}"
  fi
}

function get_volumes() {
  # Get PVC/PV for the pod
  log "Getting Pod: ${POD_NAME} to determine PVC names"
  VOLUMES_CLAIMS=$(kubectl get pod "$POD_NAME" -n "${NAMESPACE}" -ojsonpath='{range .spec.volumes[*]}{.persistentVolumeClaim.claimName}{"\n"}{end}') # Get PVC Names
  if [[ "${#VOLUMES_CLAIMS[@]}" -gt 0 ]]; then
    for claim in "${VOLUMES_CLAIMS[@]}"; do
      get_object pvc "$claim"
      local PVC=$OBJECT
      log "Identifying StorageClass of PVC: \"${claim}\""
      CSI=$(echo "$PVC" | sed -n 's/.*storage-provisioner": "\([^"]*\)".*/\1/p' | head -1)
      PV_NAME=$(echo "$PVC" | sed -n 's/.*"volumeName": "\(.*\)".*/\1/p' | sed 's/".*//')
      get_object pv "$PV_NAME"

      if [[ ${CSI} == 'ebs.csi.aws.com' ]]; then
        log -p "PV: \"${PV_NAME}\" is using EBS CSI Controller"
        COLLECT_EBS_CSI_LOGS='YES'
      fi

      if [[ ${CSI} == 'efs.csi.aws.com' ]]; then
        log -p "PV: \"${PV_NAME}\" is using EFS CSI Controller"
        COLLECT_EFS_CSI_LOGS='YES'
      fi
    done
  fi

  if [[ ${COLLECT_EBS_CSI_LOGS} == 'YES' ]]; then
    log -p "Collecting EBS CSI Controller deployment information & logs"
    EBS_CSI_FILE=$(get_filename "ebs-csi-controller" "json")
    log "Getting EBS CSI Controller deployment"
    kubectl get deployment -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver -ojsonpath='{.items}' >> "${EBS_CSI_FILE}"

    if [[ -n $NODE_NAME ]]; then
      log "Getting EBS CSI Node Pod"
      EBS_CSI_NODE_POD=$(kubectl get pod -n kube-system --field-selector spec.nodeName="${NODE_NAME}" -l app=ebs-csi-node --no-headers | awk '{print $1}')
      log "Getting ${EBS_CSI_NODE_POD} pod logs for all containers"
      EBS_CSI_LOG_FILE=$(get_filename "ebs-node" "log")
      kubectl logs "$EBS_CSI_NODE_POD" -n kube-system --all-containers --tail=-1 > "${EBS_CSI_LOG_FILE}"
    else
      log "Skipping EBS CSI Node pod information as the nodeName was not found"
    fi

    log "Getting EBS CSI Controller deployment logs of all containers"
    EBS_CSI_LOG_FILE=$(get_filename "ebs-csi" "log")
    kubectl logs -n kube-system -l app=ebs-csi-controller --all-containers --tail=-1 > "${EBS_CSI_LOG_FILE}"
  fi

  if [[ ${COLLECT_EFS_CSI_LOGS} == 'YES' ]]; then
    log -p "Collecting EFS CSI Controller deployment information & logs"
    EFS_CSI_FILE=$(get_filename "efs-csi-controller" "json")
    log "Getting EFS CSI Controller deployment"
    kubectl get deployment -n kube-system -l app.kubernetes.io/name=aws-efs-csi-driver -ojsonpath='{.items}' > "${EFS_CSI_FILE}"

    if [[ -n $NODE_NAME ]]; then
      log "Getting EFS CSI Node Pod"
      EFS_CSI_NODE_POD=$(kubectl get pod -n kube-system --field-selector spec.nodeName="${NODE_NAME}" -l app=efs-csi-node --no-headers | awk '{print $1}')

      log "Getting ${EFS_CSI_NODE_POD} pod logs for all containers"
      EFS_CSI_LOG_FILE=$(get_filename "efs-node" "log")
      kubectl logs "$EFS_CSI_NODE_POD" -n kube-system --all-containers --tail=-1 > "${EFS_CSI_LOG_FILE}"
    else
      log "Skipping EFS CSI Node pod information as the nodeName was not found"
    fi

    log "Getting EBS CSI Controller deployment logs of all containers"
    EFS_CSI_LOG_FILE=$(get_filename "efs-csi" "log")
    kubectl logs -n kube-system -l app=efs-csi-controller --all-containers --tail=-1 > "${EFS_CSI_LOG_FILE}"
  fi

  # Check Mounted ConfigMaps for the pod are present
  log "Getting Pod: ${POD_NAME} to determine ConfigMap names"
  CMS=$(kubectl get pod "$POD_NAME" -n "${NAMESPACE}" -ojsonpath='{range .spec.volumes[*]}{.configMap.name}{"\n"}{end}')
  if [[ "${#CMS[@]}" -eq 0 ]]; then
    for cm in "${CMS[@]}"; do
      log -p "Getting information related to ConfigMap: ${cm}"
      if [[ ! $(kubectl get configmap "$cm" -n "${NAMESPACE}") ]]; then #Check Associated ConfigMap JSON
        error "ConfigMap ${cm} is missing"
      fi
    done
  fi
}

function get_karpenter() {
  # Checks if Karpenter exists in the cluster and grabs required information from it
  local KARPENTER_COLLECTION
  local NS

  if [[ -n $(kubectl get deployment -n kube-system -l app.kubernetes.io/name=karpenter -ojsonpath='{.items[*].metadata.name}') ]]; then
    KARPENTER_COLLECTION=true
    NS=kube-system
  elif [[ -n $(kubectl get deployment -n karpenter -l app.kubernetes.io/name=karpenter -ojsonpath='{.items[*].metadata.name}') ]]; then
    KARPENTER_COLLECTION=true
    NS=karpenter
  fi

  if [[ "${KARPENTER_COLLECTION}" ]]; then
    OUTPUT_DIR="${OUTPUT_DIR_NAME}/karpenter"
    mkdir "$OUTPUT_DIR"

    log -p "Collecting Karpenter deployment information & logs"
    log "Getting Karpenter deployment logs of all containers"
    KARPENTER_LOG_FILE=$(get_filename "karpenter" "log")
    kubectl logs -l app.kubernetes.io/name=karpenter -n "${NS}" --all-containers --tail=-1 > "${KARPENTER_LOG_FILE}"
    log "Getting Karpenter deployment"
    KARPENTER_DEPLOY_FILE=$(get_filename "karpenter_deployment" "json")
    kubectl get deployment -n "${NS}" -l app.kubernetes.io/name=karpenter -ojsonpath='{.items}' > "${KARPENTER_DEPLOY_FILE}"
    log "Getting Karpenter NodePool"
    KARPENTER_NODEPOOL_FILE=$(get_filename "karpenter_nodepool" "yaml")
    kubectl get nodepool -o yaml >> "${KARPENTER_NODEPOOL_FILE}"
    log "Getting Karpenter EC2 NodeClass"
    KARPENTER_EC2NODECLASS_FILE=$(get_filename "karpenter_ec2nodeclass" "yaml")
    kubectl get ec2nodeclass -o yaml >> "${KARPENTER_EC2NODECLASS_FILE}"
    log "Getting Karpenter NodeClaim"
    KARPENTER_NODECLAIM_FILE=$(get_filename "karpenter_nodeclaim" "yaml")
    kubectl get nodeclaim -o yaml >> "${KARPENTER_NODECLAIM_FILE}"
  fi
}

function finalize() {
  prompt "Please type \"Yes\" and press ENTER if you want to archive the collected information, To Skip just press ENTER"
  read -t 30 -rep $'Do you want to create a Tarball of the collected information?\n>' CREATE_TAR
  CREATE_TAR=$(echo "$CREATE_TAR" | tr '[:upper:]' '[:lower:]')
  if [[ ${CREATE_TAR} == 'yes' || ${CREATE_TAR} = 'y' ]]; then
    log "User entered \"${CREATE_TAR}\" for tarballing the collected information"
    log -p "Archiving collected information"
    cp "${LOG_FILE}" "./${OUTPUT_DIR_NAME}" && rm -rf "${LOG_FILE}"
    LOG_FILE="${OUTPUT_DIR_NAME}/${LOG_FILE}"
    tar -czf "./${OUTPUT_DIR_NAME}.tar.gz" "./${OUTPUT_DIR_NAME}/"
    print "\n\t${colorDone}Done!! Archived information is located in \"./${OUTPUT_DIR_NAME}.tar.gz\"${colorClear}"
    print "\n\t${colorDone}Check the execution logs in file ./${LOG_FILE}!!\"${colorClear}"

  else
    log -p "Skipped archiving collected information"
    print "Check script executionlogs in file ./${LOG_FILE}!!"
    print "\n\t${colorDone}Done!!! \n\tPlease run \"tar -czf ./${OUTPUT_DIR_NAME}.tar.gz ./${OUTPUT_DIR_NAME}/*\" \n\tto create archived file in current directory!!${colorClear}"
  fi
}

# Main Section
START_TIME=$(date -u "+%Y-%m-%dT%H:%M:%S_%Z")
LOG_FILE="EPIC-Script_${START_TIME}.log"
log -p "Script execution started"
trap 'error "Recieved SIGINT cleaning up & terminating"' SIGINT
check_Kubectl
check_permissions
validate_args
get_cluster_iam
get_cluster_info
get_default_resources
get_karpenter

if [[ ${VALID_INPUTS} == 'VALID' ]]; then # Collect resources for User Desired POD and Namespace
  get_pod
  get_svc_ingress
  get_volumes
  finalize
fi