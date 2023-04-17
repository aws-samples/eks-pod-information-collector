### EKS Cluster Log Collector Script

This project was created to collect Amazon EKS cluster level logs which includes collecting a specific POD Configuration/logs , Cluster setup level configuration such as ConfigMap and Kubernetes resources such as PV,PVC,WebHook, SA for troubleshooting Amazon EKS customer support cases.

#### Usage

At a high level, you run this script from your machine's terminal against your desired EKS cluster and it will collect below included information at a specific directoy location in a Tarball format that will help AWS support and service team engineers in assisting AWS Customers with their EKS cluster related issues. AWS support and service team engineers can use this collected information once provided via a customer support case to investigate/troubleshoot the issue effectively and efficiently.

NOTE: User must have a Admin permission to view/access all the resources in their respective EKS cluster before they run the script.

* Collect EKS logs using SSM agent, jump to below [section](#collect-eks-logs-using-ssm-agent) _(or)_

* Run this project as the root user and `POD_NAME & NAMESPACE` are mandatory input parameter 

```
curl -O https://github.com/aws-samples/aws-eks-cluster-log-collector-script.git
sudo bash eks-cluster-log-collector.sh <Provide Complete POD name> <Provide Complete Namespace Name In which that POD is running>
OR
./eks-cluster-log-collector.sh <Provide Complete POD name> <Provide Complete Namespace Name In which that POD is running>
```

NOTE: If you do not pass the required arguments `POD_NAME & NAMESPACE` , By default script will collect Default resources running in `KUBE-SYSTEM namespace`.

Confirm if the tarball file was successfully created (it can be .tgz or .tar.gz) in your current Directory. `EX: /~/Desktop/<EKS-Cluster-Name>_<CurrentTime-stamp-UTC>.tar.gz`
#### Share the logs Over EKS Support Case

You can run this script prior to creating a EKS support case with AWS and attach the generated Log tarball folder as an attachment on your case.

#### List of files that gets generated by the EKS script

The `aws-eks-cluster-log-collector-script` will create a main folder under your current directory with your EKS cluster name and time stamp(<EKS-Cluster-Name>_<CurrentTime-stamp-UTC>.tar.gz) which will include below listed files with a proper naming convention to segregate captured EKS cluster information and kubernetes resource configuration and logs. 

NOTE: K = Kubectl 
 - Script will create following list of files within the main folder.

  1. `Cluster_Info.json` --> It will include current-context EKS Cluster information such as Cluster ARN and control plan server Url.
  
  2. `ConfigMap.yaml` --> It will include AWS-Auth , CoreDNS, Kube-Proxy config map information.
    
  3. `DaemonSets.yaml` --> It will include AWS-Node, Kube-Proxy DaemonSets information.
  
  4. `Deployments.yaml` --> It will include CoreDNS Deployments information.
  
  5. `MutatingWebhook.json` --> It will include currently configured MutatingWebhook information.`K get mutatingwebhookconfiguration`
  
  6. `ValidatingWebhook.json` --> It will include currently configured ValidatingWebhook information. Output of: `K get validatingwebhookconfiguration`
  
  7. `Storage_Classes.json` --> It will include currently deployed Storage class information. Output of: `K get sc`
 
  8. `Node_${NODE}.txt & Node_${NODE}.json` --> It will include the WorkerNode information on which user provided Pod (Pod name provided as input parameter) is running. Output Of: `K get/describe node`

  9. `SA_${POD_SA_NAME}.json`--> It will include currently configured Service Accounts information. Output of: `K get serviceaccount`
  
  10. `Pod_${POD_NAME}.txt & Pod_${POD_NAME}.json & ${POD_NAME}.log` -->  It will include the configuration spec of the pods and log of that application pod. Output Of: `K get/describe/logs  pod`
  
  11. `Ingress.json` --> It will include the information about the configured ingress. Output Of: `K get/describe ingress` 

  12. `aws_lbc.log & aws_lbc.json` --> It will include the information about the configured AWS ALB Pod spec and Pod logs. Output Of: `K get/describe/log <aws-lb-deployment>`

  13. `ebs-node-${container}.log & ebs-csi-${container}.log` --> It will include the information about the configured ebs-node Pod spec and ebs-csi Pod logs. Output Of: `K get/describe/log <ebs-deployment>`

  14. `efs-node-${container}.log & efs-csi-${container}.log` --> It will include the information about the configured efs-node Pod spec and efs-csi Pod logs. Output Of: `K get/describe/log <efs-deployment>`

  15. `PVC_${claim}.json & PV_${PV}.json & PV_${PV}.txt & PVC_${claim}.txt` --> It will include the information about the configured persistance volume and claims. Output Of: `K get/describe <pv & pvc deployment>`
  
  16. `<Your-EKS-Cluster>.<DATE>-<TimeStamp-UTC>.tar.gz` --> It is the Archived version of all the above-mentioned files which you can share on your EKS support case for AWS support engineer review so they can efficiently assit you to troubleshoot your EKS related issue



#### Use-case Scenarios

This script can be executed from your machine against any AWS EKS cluster and below I have included few execution use-cases for the reference (**Note: User who is running this script must have appropriate Admin permission to access EKS cluster and should configure AWS_Profile with appropriate assume_role prior to running the script**).

```
SCENARIO 1: When you do not include POD_NAME & NAMESPACE

$ sudo ./eks-cluster-log-collector.sh

RESULT:


    [WARNING] POD_NAME & NAMESPACE Both are required!!

	[WARNING] Collecting Default resources in KUBE-SYSTEM namespace!!

Collecting information in Directory: /~/Desktop/<EKS-Cluster-Name>_2023-04-17_2314-UTC
Collecting Cluster Details, Review File: Cluster_Info.json
Collecting Default resources in KUBE-SYSTEM, Review Files ConfigMaps.yaml, DaemonSets.yaml, Deployments.yaml
###
Done Collecting Information
###
#### Bundling the file ####

	Done... your bundled logs are located in /~/Desktop/<EKS-Cluster-Name>_2023-04-17_2314-UTC.tar.gz

```
```
SCENARIO 2: When you include POD_NAME & NAMESPACE

$ sudo ./eks-cluster-log-collector.sh <Provide Complete POD name> <Provide Complete Namespace Name In which that POD is running>

EX:
$ sudo ./eks-cluster-log-collector.sh example-test-pod-123xxxx  test

RESULT:

Collecting information in Directory: /~/Desktop/<EKS-Cluster-Name>_2023-04-17_2314-UTC
Collecting Cluster Details, Review File: Cluster_Info.json
Collecting Default resources in KUBE-SYSTEM, Review Files ConfigMaps.yaml, DaemonSets.yaml, Deployments.yaml
Collecting Resource related to example-test-pod-123xxxx, Review Files in Directory: example-test-pod-123xxxx
******** NOTE ********
Please Enter yes Or y if you want to collect the logs of Pod "example-test-pod-123xxxx"
**********************
y
**********************
Collecting logs of Pod

###
Done Collecting Information
###
#### Bundling the file ####

	Done... your bundled logs are located in /~/Desktop/<EKS-Cluster-Name>_2023-04-17_2314-UTC.tar.gz

```
