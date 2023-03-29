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
TIME=$(date -u +%Y-%m-%d_%H%M-%Z)
OUTPUT_DIR_NAME=$(sed 's|r/|r-|g' <<< "${CLUSTERNAME}")_$TIME  
mkdir "$OUTPUT_DIR_NAME"
OUTPUT_DIR="$PWD/${OUTPUT_DIR_NAME}"

# Default Output File Names:
CLUSTER_INFO_FILE="${OUTPUT_DIR}/Cluster_Info.json"
CONFIG="${OUTPUT_DIR}/ConfigMaps.yaml"
DAEMONSET="${OUTPUT_DIR}/DaemonSets.yaml"
DEPLOYMENT="${OUTPUT_DIR}/Deployments.yaml"
MUTATING_WEBHOOKS="${OUTPUT_DIR}/MutatingWebhook.json"
VALIDATING_WEBHOOKS="${OUTPUT_DIR}/ValidatingWebhook.json"
STORAGE_CLASSES="${OUTPUT_DIR}/Storage_Classes.json"

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
  POD_OWNER_KIND='pod'
  POD_OWNER_NAME=${POD_NAME}
  while [ $(kubectl get $POD_OWNER_KIND $POD_OWNER_NAME -n $NAMESPACE -ojsonpath='{.metadata.ownerReferences}') ] ; do
    KIND1=$(kubectl get $POD_OWNER_KIND $POD_OWNER_NAME -n $NAMESPACE -ojsonpath='{.metadata.ownerReferences[?(@.apiVersion=="apps/v1")].kind}')
    POD_OWNER_NAME=$(kubectl get $POD_OWNER_KIND $POD_OWNER_NAME -n $NAMESPACE -ojsonpath="{.metadata.ownerReferences[?(@.kind=="\"${KIND1}\"")].name}")
    POD_OWNER_KIND=${KIND1}
    kubectl get $POD_OWNER_KIND $POD_OWNER_NAME -n $NAMESPACE -ojson > "${POD_OUTPUT_DIR}/${POD_OWNER_KIND}_${POD_OWNER_NAME}.json"
    kubectl describe $POD_OWNER_KIND $POD_OWNER_NAME -n $NAMESPACE > "${POD_OUTPUT_DIR}/${POD_OWNER_KIND}_${POD_OWNER_NAME}.txt"
  done

  # Get Service Account details
  POD_SA_NAME=$(kubectl get po $POD_NAME -n $NAMESPACE -ojsonpath='{.spec.serviceAccountName}')
  kubectl get serviceaccount $POD_SA_NAME -n $NAMESPACE -ojson > "${POD_OUTPUT_DIR}/SA_${POD_SA_NAME}.json"

  # Get Service Details 
  LABEL_LIST=$(kubectl get pod $POD_NAME -n $NAMESPACE --show-labels --no-headers | awk '{print $NF}' | sed 's/\,/\n/g')

  # Iterate over labels to find the service because their no direct reference to service and deployment
  for label in ${LABEL_LIST[*]}; do
    if [[ $(kubectl get svc -n $NAMESPACE -l $label -ojsonpath='{.items[*]}') ]] ; then
      kubectl get svc -n $NAMESPACE -l $label -ojsonpath='{.items}' >> "${POD_OUTPUT_DIR}/Services.json"
      kubectl describe svc -n $NAMESPACE -l $label >> "${POD_OUTPUT_DIR}/Services.txt"
      SVC=$(kubectl get svc -n $NAMESPACE -l $label --no-headers | head -1 | awk '{print $1}')
      ANN=$(kubectl get svc $SVC -n $NAMESPACE -ojsonpath='{.metadata.annotations.service\.beta\.kubernetes\.io/aws-load-balancer-type}')
      SPEC=$(kubectl get svc $SVC -n $NAMESPACE -ojsonpath='{.spec.loadBalancerClass}')
      [[ ! $ANN ]] && INGRESS_CLASS=$SPEC || INGRESS_CLASS=$ANN

      if [[ ${INGRESS_CLASS} == 'external' || ${INGRESS_CLASS} == 'service.k8s.aws/nlb' ]] ; then
        COLLECT_LBC_LOGS='YES'
        echo "Setting COllect LBC YES in SVC"
      fi
    fi

  # Get Ingress resources using labels
    if [[ $(kubectl get ingress -n $NAMESPACE -l $label -ojsonpath='{.items[*]}') ]] ; then
      kubectl get ingress -n $NAMESPACE -l $label -ojsonpath='{.items}' >> "${POD_OUTPUT_DIR}/Ingress.json"
      kubectl describe ingress -n $NAMESPACE -l $label >> "${POD_OUTPUT_DIR}/Services.txt"
      INGRESS=$(kubectl get ingress -n $NAMESPACE -l $label --no-headers | head -1 | awk '{print $1}')
      ANN=$(kubectl get ingress $INGRESS -n $NAMESPACE -ojsonpath='{.metadata.annotations.kubernetes\.io/ingress\.class}')
      SPEC=$(kubectl get ingress $INGRESS -n $NAMESPACE -ojsonpath='{.spec.ingressClassName}')
      [[ ! $ANN ]] && INGRESS_CLASS=$SPEC || INGRESS_CLASS=$ANN

      if [[ ${INGRESS_CLASS} == 'alb' ]] ; then
        COLLECT_LBC_LOGS='YES'
      fi
    fi
  done

  if [[ ${COLLECT_LBC_LOGS} == 'YES' ]] ; then
    kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=-1 > "${POD_OUTPUT_DIR}/aws_lbc.log"
    kubectl get deployment -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller -ojsonpath='{.items}'> "${POD_OUTPUT_DIR}/aws_lbc.json"
  fi

  # Get PVC/PV for the pod
  VOLUMES_CLAIMS=$(kubectl get pod $POD_NAME -n $NAMESPACE -ojsonpath='{range .spec.volumes[*]}{.persistentVolumeClaim.claimName}{"\n"}{end}') # Get PVC Names
  for claim in ${VOLUMES_CLAIMS[*]}; do
    kubectl get pvc $claim -n $NAMESPACE -ojson > "${POD_OUTPUT_DIR}/PVC_${claim}.json"
    kubectl describe pvc $claim -n $NAMESPACE > "${POD_OUTPUT_DIR}/PVC_${claim}.txt"
    PV=$(kubectl get pvc $claim -n $NAMESPACE -o jsonpath={'.spec.volumeName'})
    kubectl get pv $PV -o json > "${POD_OUTPUT_DIR}/PV_${PV}.json"  #Get Associated PV JSON
    kubectl describe pv $PV > "${POD_OUTPUT_DIR}/PV_${PV}.txt" 
    CSI=$(kubectl get pv $PV -ojsonpath='{.spec.csi.driver}')

    if [[ ${CSI} == 'ebs.csi.aws.com' ]] ; then
      COLLECT_EBS_CSI_LOGS='YES'
    fi

    if [[ ${CSI} == 'efs.csi.aws.com' ]] ; then
      COLLECT_EFS_CSI_LOGS='YES'
    fi
  done

  if [[ ${COLLECT_EBS_CSI_LOGS} == 'YES' ]] ; then
    kubectl get deployment -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver -ojsonpath='{.items}'> "${POD_OUTPUT_DIR}/ebs-csi-controller.json"
    EBS_CSI_NODE_POD=$(kubectl get pods -n kube-system --field-selector spec.nodeName=${NODE} -l app=ebs-csi-node --no-headers | awk '{print $1}')
    NODE_CONTAINERS=$(kubectl get daemonset -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver -ojsonpath='{.items[0].spec.template.spec.containers[*].name}')
    DRIVER_CONTAINERS=$(kubectl get deployment -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver -ojsonpath='{.items[0].spec.template.spec.containers[*].name}')
    for container in ${NODE_CONTAINERS}; do
      kubectl logs $EBS_CSI_NODE_POD -n kube-system -c $container --tail=-1 > "${POD_OUTPUT_DIR}/ebs-node-${container}.log"
    done
    for container in ${DRIVER_CONTAINERS}; do
      kubectl logs -n kube-system -l app=ebs-csi-controller -c $container --tail=-1 > "${POD_OUTPUT_DIR}/ebs-csi-${container}.log"
    done
    
  fi

  if [[ ${COLLECT_EFS_CSI_LOGS} == 'YES' ]] ; then
    kubectl get deployment -n kube-system -l app.kubernetes.io/name=aws-efs-csi-driver -ojsonpath='{.items}'> "${POD_OUTPUT_DIR}/efs-csi-controller.json"
    EFS_CSI_NODE_POD=$(kubectl get pods -n kube-system --field-selector spec.nodeName=${NODE} -l app=efs-csi-node --no-headers | awk '{print $1}')
    NODE_CONTAINERS=$(kubectl get daemonset -n kube-system -l app.kubernetes.io/name=aws-efs-csi-driver -ojsonpath='{.items[0].spec.template.spec.containers[*].name}')
    DRIVER_CONTAINERS=$(kubectl get deployment -n kube-system -l app.kubernetes.io/name=aws-efs-csi-driver -ojsonpath='{.items[0].spec.template.spec.containers[*].name}')
    for container in ${NODE_CONTAINERS}; do
      kubectl logs $EFS_CSI_NODE_POD -n kube-system -c $container --tail=-1 > "${POD_OUTPUT_DIR}/efs-node-${container}.log"
    done
    for container in ${DRIVER_CONTAINERS}; do
      kubectl logs -n kube-system -l app=efs-csi-controller -c $container --tail=-1 > "${POD_OUTPUT_DIR}/efs-csi-${container}.log"
    done
  fi 

  # Collect StorageClasses
  kubectl get sc -ojsonpath='{.items}' > $STORAGE_CLASSES 

  # Get Mounted ConfigMaps for the pod
  # TODO: Should we get/read the configMap as well?

  CMS=$(kubectl get pod $POD_NAME -n $NAMESPACE -ojsonpath='{range .spec.volumes[*]}{.configMap.name}{"\n"}{end}')
  for cm in ${CMS[*]}; do
    if [[ ! $(kubectl get cm $cm -n $NAMESPACE) ]] ; then  #Get Associated ConfigMap JSON
      echo "ConfigMap ${cm} is missing"
    fi
  done

  # Collect Webhooks
  kubectl get mutatingwebhookconfiguration -ojsonpath='{.items}' > $MUTATING_WEBHOOKS
  kubectl get validatingwebhookconfiguration -ojsonpath='{.items}' > $VALIDATING_WEBHOOKS

  # Optional log collection
  print "\n******** NOTE ********\n""Please Enter "yes" Or "y" if you want to collect the logs of Pod \"${POD_NAME}\"\n""**********************"
  read COLLECT_LOGS 
  print "**********************\n""Collecting logs of Pod\n"
  COLLECT_LOGS=$(echo "$COLLECT_LOGS" | tr '[:upper:]' '[:lower:]')

  if [[ ${COLLECT_LOGS} == 'yes'  || ${COLLECT_LOGS} = 'y' ]] ; then
    kubectl logs $POD_NAME -n $NAMESPACE --timestamps > "${POD_OUTPUT_DIR}/${POD_NAME}.log"
  fi

fi

print "###\nDone Collecting Information\n###"
print "#### Bundling the file ####"
tar -czf "${PWD}/${OUTPUT_DIR_NAME}.tar.gz" "./${OUTPUT_DIR_NAME}" 
print "\n\tDone... your bundled logs are located in ${PWD}/${OUTPUT_DIR_NAME}.tar.gz\n"