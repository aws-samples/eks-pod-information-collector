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
FILENAME="${OUTPUT_DIR}/ClusterDetails.txt"
append "$FILENAME"
kubectl config current-context >> "$FILENAME"
append "$FILENAME"
kubectl cluster-info >> "$FILENAME"
append "$FILENAME"

echo "Collecting ConfigMap Details From Kubernetes Cluster: ${CLUSTERNAME}, Review File: ConfigMap_Info.txt "
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

echo "Collecting AWS-Node & Kube-Proxy DaemonSet Details From Kubernetes Cluster: ${CLUSTERNAME}, Review File: DaemonSet_Info.txt "
DAEMONSET="${OUTPUT_DIR}/DaemonSet_Info.txt"
echo "===[1] =========== AWS-Node DaemonSet Details ===============" > "$DAEMONSET"
kubectl describe daemonset aws-node -n kube-system >> "$DAEMONSET"
end_append "1" "$DAEMONSET"

echo "===[2] =========== Kube-Proxy DaemonSet Details ===============" >> "$DAEMONSET"
kubectl describe daemonset kube-proxy -n kube-system >> "$DAEMONSET"
end_append "2" "$DAEMONSET"

# Collecting All the PODs descriptions/logs running in User Desired Namespace Or by default it will collect pods log running in default namespace
Default_Namespace=${1:-'default'}
echo "Collecting All The Running POD Logs and POD Description From  Namespace:  ${Default_Namespace} "
kubectl get ns --no-headers | while read -r line; do
NAMESPACE=$(echo "$line" | awk '{print $1}')
if [[ "$NAMESPACE" = "$Default_Namespace" ]];then
    kubectl get pods -n "$NAMESPACE" --no-headers | while read -r lines; do
            POD_NAME=$(echo "$lines" | awk '{print $1}')
            FILENAME1="${OUTPUT_DIR}/${NAMESPACE}.${POD_NAME}.describe.txt"
            kubectl describe pod -n "$NAMESPACE" "$POD_NAME" > "$FILENAME1"
            for CONTAINER in $(kubectl get po -n "$NAMESPACE" "$POD_NAME" -o jsonpath="{.spec.containers[*].name}"); do
            FILENAME_PREFIX="${OUTPUT_DIR}/${NAMESPACE}.${POD_NAME}.${CONTAINER}"
            
            echo "Collecting Pod "{$POD_NAME}" Logs From "{$NAMESPACE}" Namespace "
            FILENAME2="${FILENAME_PREFIX}.current.${EXTENSION}"
            kubectl logs -n "$NAMESPACE" "$POD_NAME" --all-containers=true >"$FILENAME2"   
        done 
    done

# Collecting All the K8 resources deployed in user specified namespace 
        echo "Collecting Information About All Other Deployed Resources in "{$NAMESPACE}" Namespace , Review File: AllResourcesInfo.txt"
            FILENAME3="${OUTPUT_DIR}/AllResourcesInfo.txt"
            append "$FILENAME3" 
            kubectl get all -n "$NAMESPACE" >>"$FILENAME3" 
            append "$FILENAME3" 

        echo "Collecting Recent Events Log That Took Place Within Namespace ${NAMESPACE}, Review File: EventsInfo.txt"
            FILENAME4="${OUTPUT_DIR}/EventsInfo.txt"
            kubectl get events --sort-by=.metadata.creationTimestamp -n "$NAMESPACE" > "$FILENAME4" 
 fi  
done

echo "******* NOTE *******"
print "Please Enter "yes" Or "y" If Your Current Issue Involves Kubernetes Resource Such As "{PVC, SC, PV, WorkerNode, WebHook}" So Script Can Continue Collect These Resource Information To Troubleshoot otherwise Enter "no" or "n""
echo "*********************"
read user_input
input='yes'
input2='y'
if [ "$user_input" = "$input" ] || [ "$user_input" = "$input2" ];then

    echo "Collecting Information About All The Presently Running Worker Node In ${CLUSTERNAME}, Review File: WorkerNodeInfo.txt "
    FILENAME6="${OUTPUT_DIR}/WorkerNodeInfo.txt"
    kubectl describe node -A > "$FILENAME6"

    # Collecting All the information about Persistent volume and storage class.

    echo "Collecting Information About All The Persistent Volume & Storage Class Deployed In ${CLUSTERNAME}, Review File: StorageInfo.txt  "
    FILENAME7="${OUTPUT_DIR}/StorageInfo.txt"
    echo "=== [1] ===========Storage Class Details===============" > "$FILENAME7"
    kubectl get sc -A >> "$FILENAME7"
    append "$FILENAME7"
    kubectl describe sc -A >> "$FILENAME7"
    end_append "1" "$FILENAME7"

    echo "=== [2] ===========PersistentVolume Details===============" >> "$FILENAME7"
    kubectl get pv -A >> "$FILENAME7"
    append "$FILENAME7"
    kubectl describe pv -A >> "$FILENAME7"
    end_append "2" "$FILENAME7"
   
    echo "=== [3] ===========PersistentVolume Claim Details===============" >> "$FILENAME7"
    kubectl get pvc -A >> "$FILENAME7"
    append "$FILENAME7"
    kubectl describe pvc -A >> "$FILENAME7"
    end_append "3" "$FILENAME7"

    echo "Collecting Information About All Configured WebHooks In ${CLUSTERNAME}, Review File: WebHookInfo.txt  "
    FILENAME8="${OUTPUT_DIR}/WebHookInfo.txt"
    append "$FILENAME8"
    kubectl describe validatingwebhookconfigurations.admissionregistration.k8s.io -A >> "$FILENAME8"
    append "$FILENAME8"
    kubectl describe mutatingwebhookconfigurations.admissionregistration.k8s.io -A >> "$FILENAME8"
    append "$FILENAME8"
fi

CWD=$(pwd)
cd $ROOT_OUTPUT_DIR || exit 1

echo " ******* INITIALIZING TARBALLING  ********"

print "======= Collecting All Recently Occurring Errors and Failure In ${CLUSTERNAME}  , Review File: FoundErrors.txt ===" 
FILENAME9="${OUTPUT_DIR}/FoundErrors.txt"
egrep -Ein "fail|err|off" "${OUTPUT_DIR}"/*.${EXTENSION} > "$FILENAME9"
egrep -Ein "fail|err|off" "${OUTPUT_DIR}"/*.txt >> "$FILENAME9"
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
