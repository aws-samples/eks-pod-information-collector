#!/bin/bash

function print() {
  echo "======================================="
  echo "$@"
  echo "======================================="
}
function append() {
  echo "=======================================" >> $1
}
function end_append() {
  echo "=== [$1] ============= END ===============================" >> $2
}

ROOT_OUTPUT_DIR=$PWD
print "Creating a Folder at: $ROOT_OUTPUT_DIR"
kubectl config current-context > clusterName.txt
CLUSTERNAME=$(sed 's/^[^=]*://' clusterName.txt)
TIME=$(date "+%Y%m%d-%Hh:%Mm:%Ss")
OUTPUT_DIR_NAME=$(sed 's|r/|r-|g' <<< "${CLUSTERNAME}").$TIME
OUTPUT_DIR="${OUTPUT_DIR_NAME}"
EXTENSION='log'
print "${CLUSTERNAME} Log Collected In Folder :  $OUTPUT_DIR"
cd $ROOT_OUTPUT_DIR
mkdir "$OUTPUT_DIR"

echo "Collecting Information About Kubernetes Cluster: ${CLUSTERNAME}, Review File: ClusterDetails.txt "
CLUSTER_INFO_FILE="${OUTPUT_DIR}/ClusterDetails.txt"
kubectl config current-context > "$CLUSTER_INFO_FILE"
append "$CLUSTER_INFO_FILE"
kubectl cluster-info >> "$CLUSTER_INFO_FILE"


echo "Collecting ConfigMap Details From Cluster: ${CLUSTERNAME}, Review File: ConfigMap_Info.txt "
CONFIG="${OUTPUT_DIR}/ConfigMap_Info.txt"
echo "===[1] =========== AWS-Auth ConfigMap Details ===============" > "$CONFIG"
kubectl describe configmap aws-auth -n kube-system >> "$CONFIG"
end_append "1" "$CONFIG"

echo "===[2] =========== CoreDNS ConfigMap Details ===============" >> "$CONFIG"
kubectl describe configmap coredns -n kube-system >> "$CONFIG"
end_append "2" "$CONFIG"

echo "===[3] =========== Kube-Proxy ConfigMap Details ===============" >> "$CONFIG"
kubectl describe configmap kube-proxy -n kube-system >> "$CONFIG"
end_append "3" "$CONFIG"

echo "Collecting AWS-Node & Kube-Proxy DaemonSet Details From Cluster: ${CLUSTERNAME}, Review File: DaemonSet_Info.txt "
DAEMONSET="${OUTPUT_DIR}/DaemonSet_Info.txt"
echo "===[1] =========== AWS-Node DaemonSet Details ===============" > "$DAEMONSET"
kubectl describe daemonset aws-node -n kube-system >> "$DAEMONSET"
end_append "1" "$DAEMONSET"

echo "===[2] =========== Kube-Proxy DaemonSet Details ===============" >> "$DAEMONSET"
kubectl describe daemonset kube-proxy -n kube-system >> "$DAEMONSET"
end_append "2" "$DAEMONSET"

echo "Collecting CoreDNS Deployment Details From Cluster: ${CLUSTERNAME}, Review File: CoreDNS_Info.txt "
COREDNS="${OUTPUT_DIR}/CoreDNS_Info.txt"
echo "===[1] =========== CoreDNS Deployment Details ===============" > "$COREDNS"
kubectl describe deployment coredns -n kube-system >> "$COREDNS"
end_append "1" "$COREDNS"

# Collecting All the deployment descriptions/ yaml file  deployed in User Desired Namespace Or by default it will collect pods log running in default namespace
Default_Namespace=${1:-'default'}
i=0
for NAMESPACE in $(kubectl get ns --no-headers); do
        if [[ "$NAMESPACE" = "$Default_Namespace" ]] ; then
            (( i++ ))
            echo "Collecting All The Running Deployment Details From Namespace: ${NAMESPACE}, Review File: Describe.txt, yaml.txt "
            kubectl get deployment -n "$NAMESPACE" --no-headers | while read -r lines; do
            DEPLOYMENT_NAME=$(echo "$lines" | awk '{print $1}')
            DEPLOYMENT="${OUTPUT_DIR}/${NAMESPACE}.${DEPLOYMENT_NAME}.describe.txt"
            kubectl describe deployment -n "$NAMESPACE" "$DEPLOYMENT_NAME" > "$DEPLOYMENT"

            DEPLOYMENT_YAML="${OUTPUT_DIR}/${NAMESPACE}.${DEPLOYMENT_NAME}.yaml.txt"
            kubectl get deployment -n "$NAMESPACE" "$DEPLOYMENT_NAME" -o yaml > "$DEPLOYMENT_YAML"
            done

         # Collecting All the K8 resources deployed in user specified namespace 
          echo "Collecting All The Deployed Kubernetes Resources Details From Namespace: ${NAMESPACE}, Review File: AllResourcesInfo.txt"
           NS_RESOURCE_INFO="${OUTPUT_DIR}/AllResourcesInfo.txt"
           append "$NS_RESOURCE_INFO" 
           kubectl get all -n "$NAMESPACE" >>"$NS_RESOURCE_INFO" 
           append "$NS_RESOURCE_INFO" 

          echo "Collecting Recent Events Log Details From Namespace: ${NAMESPACE}, Review File: EventsInfo.txt"
            EVENT_INFO_FILE="${OUTPUT_DIR}/EventsInfo.txt"
             kubectl get events --sort-by=.metadata.creationTimestamp -n "$NAMESPACE" > "$EVENT_INFO_FILE" 
        fi

done

if [[ $i -eq 0 ]];then
    echo "******* ERROR: Entered Namespace Value Does Not Exist In ${CLUSTERNAME} , Please Check The Value *******"
fi



echo "******* NOTE *******"
print "Please Enter "yes" Or "y" If Your Current Issue Involves Kubernetes Resource Such As "{PVC, SC, PV, WorkerNode, WebHook}" So Script Can Continue Collect These Resource Information That Are Not Namespace Bound To Troubleshoot,  otherwise Enter "no" or "n""
echo "*********************"
read user_input
user_input=$(echo "$user_input" | tr '[:upper:]' '[:lower:]')

if [ "$user_input" = "yes" ] || [ "$user_input" = "y" ];then

    echo "Collecting Presently Running Worker Node Details From Cluster: ${CLUSTERNAME}, Review File: WorkerNodeInfo.txt "
    NODE_INFO_FILE="${OUTPUT_DIR}/WorkerNodeInfo.txt"
    kubectl describe node -A > "$NODE_INFO_FILE"

    # Collecting All the information about Persistent volume and storage class.

    echo "Collecting The Persistent Volume & Storage Class Details From Cluster: ${CLUSTERNAME}, Review File: StorageInfo.txt  "
    STORAGE_INFO_FILE="${OUTPUT_DIR}/StorageInfo.txt"
    echo "=== [1] ===========Storage Class Details===============" > "$STORAGE_INFO_FILE"
    kubectl get sc -A >> "$STORAGE_INFO_FILE"
    append "$STORAGE_INFO_FILE"
    kubectl describe sc -A >> "$STORAGE_INFO_FILE"
    end_append "1" "$STORAGE_INFO_FILE"

    echo "=== [2] ===========PersistentVolume Details===============" >> "$STORAGE_INFO_FILE"
    kubectl get pv -A >> "$STORAGE_INFO_FILE"
    append "$STORAGE_INFO_FILE"
    kubectl describe pv -A >> "$STORAGE_INFO_FILE"
    end_append "2" "$STORAGE_INFO_FILE"
   
    echo "=== [3] ===========PersistentVolume Claim Details===============" >> "$STORAGE_INFO_FILE"
    kubectl get pvc -A >> "$STORAGE_INFO_FILE"
    append "$STORAGE_INFO_FILE"
    kubectl describe pvc -A >> "$STORAGE_INFO_FILE"
    end_append "3" "$STORAGE_INFO_FILE"

    echo "Collecting Configured WebHooks Details From Cluster: ${CLUSTERNAME}, Review File: WebHookInfo.txt  "
    WEBHOOK_INFO_FILE="${OUTPUT_DIR}/WebHookInfo.txt"
    append "$WEBHOOK_INFO_FILE"
    kubectl describe validatingwebhookconfigurations.admissionregistration.k8s.io -A >> "$WEBHOOK_INFO_FILE"
    append "$WEBHOOK_INFO_FILE"
    kubectl describe mutatingwebhookconfigurations.admissionregistration.k8s.io -A >> "$WEBHOOK_INFO_FILE"
    append "$WEBHOOK_INFO_FILE"
fi

CWD=$(pwd)
cd $ROOT_OUTPUT_DIR || exit 1

echo " ******* INITIALIZING TARBALLING  ********"

print "======= Collecting Recently Occurring Errors and Failure From Cluster: ${CLUSTERNAME}  , Review File: FoundErrors.txt ===" 
FOUND_ERROR_FILE="${OUTPUT_DIR}/FoundErrors.txt"
egrep -Ein "fail|err|off" "${OUTPUT_DIR}"/*.${EXTENSION} > "$FOUND_ERROR_FILE"
egrep -Ein "fail|err|off" "${OUTPUT_DIR}"/*.txt >> "$FOUND_ERROR_FILE"
TARBALL_FILE_NAME="${OUTPUT_DIR_NAME}.tar.gz"
echo "- File Created Successfully:  ${TARBALL_FILE_NAME} "
tar -czf "./${TARBALL_FILE_NAME}" "./${OUTPUT_DIR_NAME}" 
mv "./${TARBALL_FILE_NAME}" "$OUTPUT_DIR" 

echo " ***** FINISHING TARBALLING ***** "
print "==== Please Share  Located Tarball Folder On Your EKS Support Case: "${OUTPUT_DIR}/${TARBALL_FILE_NAME} "   ======="
echo "==== For Further Troubleshooting ======"
echo " - Review Files Located At Folder :  $OUTPUT_DIR"
echo " - Search For FoundErrors.txt File To Check All Cluster Errors and Recent Failure "
echo " - Command to search log:  grep -Ei \"fail|err\" ${OUTPUT_DIR}/*.log"
echo "========================== END OF SCRIPT EXECUTION ========================="
cd "$CWD" || exit 1
