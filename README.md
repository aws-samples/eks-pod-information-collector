[![CI](https://github.com/aws-samples/eks-pod-information-collector/actions/workflows/CI.yml/badge.svg?branch=dev)](https://github.com/aws-samples/eks-pod-information-collector/actions/workflows/CI.yml)

##  EKS Pod Information Collector (EPIC)

This project is created to collect information related to kubernetes pod such as Configurations/Specification, PV/PVC etc. in Amazon EKS cluster for troubleshooting Amazon EKS customer support cases.

### Prerequisite

In order to run this script successfully:
1. Install [Kubectl utility](https://docs.aws.amazon.com/eks/latest/userguide/install-kubectl.html) and configure [KUBECONFIG](https://docs.aws.amazon.com/eks/latest/userguide/create-kubeconfig.html) on local machine prior to executing this script.
2. Set the `kubectl` context to desired cluster

### Usage

At a high level, this script can be executed in local terminal against the desired EKS cluster and it will collect information related to the specified pod, service & ingress. The user will have an option to create a Tarball (Archive) bundle of collected information.

:warning: ***NOTE:***
+ The script requires at least Read-only permissions (RBAC) to capture the kubernetes resource manifests
+ The script will create a folder under your current working directory ($PWD) with your EKS cluster name and timestamp - **<EKS_Cluster_Name>_<Current_Timestamp-UTC>**. Please delete/remove the folder and corresponding archive file after sharing it with AWS Support.

#### Run this project as shown below:

```
curl -O https://raw.githubusercontent.com/aws-samples/eks-pod-information-collector/main/eks-pod-information-collector.sh

bash eks-pod-information-collector.sh -p <pod_name> -n <pod_namespace> -s [service_name] -i [ingress_name]
OR
bash eks-pod-information-collector.sh --podname <pod_name> --namespace <pod_namespace> --service [service_name] --ingress [ingress_name]

NOTE: -p or --podname & -n or --namespace are mandatory input parameters
```

### List of files generated by the script

The directory will have following folder Structure:

```
├── Cluster_Info.json             // Cluster ARN and control plane server URL
├── EPIC-Script.log               // Script Execution logs
├── default                       // Directory for kube-system resources
│   ├── MutatingWebhook.json
│   ├── Storage_Classes.json
│   ├── ValidatingWebhook.json
│   ├── configmap_aws-auth.json
│   ├── configmap_aws-auth.txt
│   ├── configmap_coredns.json
│   ├── configmap_coredns.txt
│   ├── configmap_kube-proxy.json
│   ├── configmap_kube-proxy.txt
│   ├── daemonset_aws-node.json
│   ├── daemonset_aws-node.txt
│   ├── daemonset_kube-proxy.json
│   ├── daemonset_kube-proxy.txt
│   ├── deployment_coredns.json
│   └── deployment_coredns.txt
└── {pod_name}_{namespace}         // Directory for pod related resources
    ├── Deployment_name.json
    ├── Deployment_name.txt
    ├── Node_name.json
    ├── Node_name.txt
    ├── Pod_name.json
    ├── Pod_name.txt
    ├── ReplicaSet_name.json
    ├── ReplicaSet_name.txt
    ├── SA_name.json

    --- OPTIONAL ---

    ├── Service_{service_name}.json
    ├── Service_{service_name}.txt
    ├── Ingress_{ingress_name}.json
    ├── Ingress_{ingress_name}.txt
    ├── PVC_pvc_name.json
    ├── PVC_pvc_name.txt
    ├── PV_pv_name.json
    ├── PV_pv_name.txt
    ├── ebs/efs-csi-controller.json
    ├── ebs/efs-csi-container.log
    ├── aws_lbc.json
    └── aws-lbc.log
```


### Examples

#### Example 1 : Get help
```
$ bash ./eks-pod-information-collector.sh --help

Usage: ./eks-pod-information-collector.sh -p <Podname> -n <Namespace of the pod> -s [Service Name] -i [Ingress Name]

Required:
  -p, --podname         Pod name (Required)
  -n, --namespace       Pod Namespace (Required)

OPTIONAL:
  -s, --service         Service name associated with the Pod
  -i, --ingress         Ingress name associated with the Pod
  -h, --help            Show Help menu
```

#### Example 2 : To collect pod logs and create Archived (Tarball) file
```
$ bash eks-pod-information-collector.sh -p pod_name -n pod_namespace -s service_name

Script execution started...
Validating input arguments...
Collected Cluster Name: "{Cluster_name}}" from current context...
Collecting information in directory: "Cluster_name_2023-11-03T06:56:10_UTC"
Collecting additional Cluster infromation...
Collecting version...
Collecting Default resources in KUBE-SYSTEM namespace...
Collecting information related to configmap: "aws-auth"...
Collecting information related to configmap: "coredns"...
Collecting information related to configmap: "kube-proxy"...
Collecting information related to daemonset: "aws-node"...
Collecting information related to daemonset: "kube-proxy"...
Collecting information related to deployment: "coredns"...
Collecting information related to pod: "{pod_name}}"...
Collecting information related to node: "{node_name}}"...
Collecting information related to serviceaccount: "{service_account}}"...
Collecting information related to service: "{service_name}}"...
Service: "{service_name}}" is using AWS Load Balancer Controller...
Collecting AWS Load Balancer Controller deployment information & logs...
******** ATTENTION ********
 Please type "Yes" and press ENTER if you want to archive the collected information, To Skip just press ENTER
***************************

Do you want to create a Tarball of the collected information?
>yes
Archiving collected information...

        Done!! Archived information is located in "./<Cluster_Name_Start_Timestamp>.tar.gz"
        Check the execution logs in file ./<Cluster_Name_Start_Timestamp>/EPIC-Script_<Start_Timestamp>>.log!!"
```

#### Example 3 : If input arguments not specified
```
$ bash eks-pod-information-collector.sh

Usage: ./eks-pod-information-collector.sh -p <Podname> -n <Namespace of the pod> -s [Service Name] -i [Ingress Name]

Required:
  -p, --podname         Pod name (Required)
  -n, --namespace       Pod Namespace (Required)

OPTIONAL:
  -s, --service         Service name associated with the Pod
  -i, --ingress         Ingress name associated with the Pod
  -h, --help            Show Help menu

        [ERROR]: POD_NAME & NAMESPACE Both arguments are required!!
        [ERROR]: Check logs in file ./EPIC-Script_<Start_Timestamp>.log
```
