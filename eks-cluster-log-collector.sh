#!/bin/bash

function print() {
  echo "======================================="
  echo "$@"
  echo "======================================="
}
function append() {
  echo "====================[$(echo $1 | tr '[:lower:]' '[:upper:]')]===================" >> $2
}
function end_append() {
  echo "=== [$1] ============= END ===============================" >> $2
}


# print "Creating a Folder at: $ROOT_OUTPUT_DIR"

#  Creating Output Directory
CLUSTER_INFO=$(kubectl config view --minify -ojsonpath='{.clusters[0]}')
CLUSTERNAME=$(echo $CLUSTER_INFO | sed 's/^[^=]*:cluster\///' | sed 's/..$//')
ROOT_OUTPUT_DIR=$PWD
TIME=$(date "+%Y%m%d-%Hh:%Mm:%Ss")
OUTPUT_DIR_NAME=$(sed 's|r/|r-|g' <<< "${CLUSTERNAME}")_$TIME  # Use '_' while constructing folder/filename
mkdir "$OUTPUT_DIR_NAME"

# Collecting Cluster Details
echo "Collecting Cluster Details: ${CLUSTERNAME}, Review File: Cluster_Info.json "
echo $CLUSTER_INFO > "$CLUSTER_INFO_FILE"

# kubectl config current-context > "$CLUSTER_INFO_FILE"
# append "$CLUSTER_INFO_FILE"
# kubectl cluster-info >> "$CLUSTER_INFO_FILE"

# Output File Names:
CLUSTER_INFO_FILE="${OUTPUT_DIR}/Cluster_Info.json"
CONFIG="${OUTPUT_DIR}/ConfigMaps.yaml"
DAEMONSET="${OUTPUT_DIR}/DaemonSets.yaml"
DEPLOYMENT="${OUTPUT_DIR}/Deployments.yaml"

# OUTPUT_DIR="${OUTPUT_DIR_NAME}"
# EXTENSION='log' # Not sure the usage of this
# print "${CLUSTERNAME} Log Collected In Folder :  $OUTPUT_DIR"
# cd $ROOT_OUTPUT_DIR


KUBE_SYSTEM_CM=(
  aws-auth
  coredns
  kube-proxy
)

# Names of DS and DEPLOY can be replaced with labels - shown in comment

KUBE_SYSTEM_DS=(
  kube-proxy   #  k8s-app=kube-proxy
  aws-node    # app.kubernetes.io/name=aws-node
  ebs-csi-node  # app.kubernetes.io/name=aws-ebs-csi-driver
  efs-csi-node  # app.kubernetes.io/name=aws-efs-csi-driver
  # we can append other add-ons plugins here
)

KUBE_SYSTEM_DEPS=(
  coredns    # k8s-app=kube-dns
  aws-load-balancer-controller #  app.kubernetes.io/name=aws-load-balancer-controller
  ebs-csi-controller  # app.kubernetes.io/name=aws-ebs-csi-driver
  efs-csi-controller # app.kubernetes.io/name=aws-efs-csi-driver
  # we can append other add-ons plugins here
)


# We can remove the clusterName from every line starting with "collecting"
echo "Collecting ConfigMap Details From Cluster: ${CLUSTERNAME}, Review File: ConfigMaps.yaml "
for cm in ${KUBE_SYSTEM_CM[*]}; do
  append " ${cm} " "$CONFIG"
  kubectl get configmap -n kube-system ${cm} -o yaml >> "$CONFIG"
  append "" "$CONFIG"
done



echo "Collecting DaemonSet Details From Cluster: ${CLUSTERNAME}, Review File: DaemonSets.yaml "
for ds in ${KUBE_SYSTEM_DS[*]}; do
  append " ${ds} " "$DAEMONSET"
  kubectl get daemonset -n kube-system ${ds} -o yaml >> "$DAEMONSET"
  append "" "$DAEMONSET"
done



echo "Collecting Deployment Details From Cluster: ${CLUSTERNAME}, Review File: Deployments.yaml "
for deploy in ${KUBE_SYSTEM_DEPS[*]}; do
  append " ${deploy} " "$DEPLOYMENT"
  kubectl get daemonset -n kube-system ${deploy} -o yaml >> "$DEPLOYMENT"
  append "" "$DEPLOYMENT"
done



# Collecting resources for User Desired POD and Namespace Namespace

POD_NAME=${1:-''}   # Do we need a default value here?
NAMESPACE=${2:-'default'}


if [[ $(kubectl get ns $NAMESPACE) ]] && [[ $(kubectl get pod $POD_NAME) ]] ; then ## check if namespace and Pod exists then proceed

  # echo "Collecting All The Running Deployment Details From Namespace: ${NAMESPACE}, Review File: Describe.txt, yaml.txt "
  echo "Collecting Resource related to ${POD_NAME}, Review File: ${POD_NAME}_get.json, ${POD_NAME}_describe.txt"

  POD=$(kubectl get pod $POD_NAME -n $NAMESPACE -ojson) 
  echo $POD > "${OUTPUT_DIR_NAME}/${POD_NAME}_get.json" 
  POD_OWNER_KIND=$(kubectl get pod $POD_NAME -n $NAMESPACE -ojsonpath='{.metadata.ownerReferences[?(@.apiVersion=="apps/v1")].kind}')  # All such repeated kubectl calls can be reduced by using jq
  POD_OWNER_NAME=$(kubectl get pod $POD_NAME -n $NAMESPACE -ojsonpath="{.metadata.ownerReferences[?(@.kind=="\"${POD_OWNER_TYPE}\"")].name}")

  POD_OWNER=$(kubectl get $POD_OWNER_KIND $POD_OWNER_NAME -n $NAMESPACE -o json)  # Get DS/DEPLOY/STS
  

  # Get Service Account details
  POD_SA_NAME=$(kubectl get $POD_OWNER_KIND $POD_OWNER_NAME -n $NAMESPACE -ojsonpath='{.spec.template.spec.serviceAccountName}')
  kubectl get serviceaccount $POD_SA_NAME -n $NAMESPACE -ojson

  # Get Service Details 


  LABELS=$(kubectl get deploy coredns -ojsonpath='{.spec.template.metadata.labels}')
  LABEL_LIST=($(echo $LABELS | jq -r 'keys[] as $k | "\($k)=\(.[$k])"'))   # Fetch Label list


  # Iterate over labels to find the service
  for label in ${LABEL_LIST[*]}; do
    kubectl get svc -n $NAMESPACE -l $label -ojson
    kubectl describe svc -n $NAMESPACE -l $label
  done

  # TODO: Can we get Ingress resources as well?

  # Get PVC/PV for the pod
  VOLUMES=$(kubectl get pod $POD_NAME -n $NAMESPACE -ojson | jq -r '.spec.volumes[] | select (.persistentVolumeClaim)') # Get PVC Names
  
  for volume in $(echo $VOLUMES | jq -r '.persistentVolumeClaim.claimName'); do
    pvc=$(kubectl get pvc $volume -n kube-system -o json)   # Get PVC JSON
    echo $pvc
    kubectl get pv $(echo $pvc | jq -r '.spec.volumeName') -o json  #Get Associated PV JSON
  done

  # Get Mounted ConfigMaps for the pod

  CMS=$(kubectl get pod $POD_NAME -n $NAMESPACE -ojson | jq -r '.spec.volumes[] | select (.configMap)')

  for cm in $(echo $CMS | jq -r '.configMap.name'); do

    kubectl get cm $cm -o json  #Get Associated ConfigMap JSON

  done

fi


