[![CI_dev](https://github.com/aws-samples/eks-pod-information-collector/actions/workflows/CI_dev.yml/badge.svg?branch=dev-punkwalker)](https://github.com/aws-samples/eks-pod-information-collector/actions/workflows/CI_dev.yml)

##  EKS Pod Information Collector (EPIC)

This project was created to collect Amazon EKS resource information related to a specific POD such as Configurations/Specification, PV/PVC etc., logs _(optional)_ etc. for troubleshooting Amazon EKS customer support cases.

### Usage

At a high level, you run this script from your local machine's terminal against the desired EKS cluster and it will collect information related to the specified pod. The user will have an option to create a Tarball file. This collected information will help AWS support and service team engineers in assisting AWS Customers with their EKS cluster related issues.

```NOTE: User must have Cluster-Admin permissions (RBAC) to view/access the kubernetes resources in their respective EKS cluster```

* Run this project with as shown below:

```NOTE: `-p or --podname & -n or --namespace are mandatory input parameters```

```
curl -O https://raw.githubusercontent.com/aws-samples/eks-pod-information-collector/main/eks-pod-information-collector.sh

sudo bash eks-pod-information-collector.sh -p <Pod_Name> -n <Pod_Namespace>
OR
sudo bash eks-pod-information-collector.sh --podname <Pod_Name> --namespace <Pod_Namespace>
```

### List of files that gets generated by the script

The will create a main folder under your current directory ($PWD) with your EKS cluster name and time stamp - **<EKS_Cluster_Name>_<Current_Timestamp-UTC>**. The directory will contain following file:

Folder Structure:
```
├── Cluster_Info.json                  // Cluster ARN and control plane server URL
├── ConfigMaps.yaml                    // AWS-Auth , CoreDNS, Kube-Proxy config map information.
├── DaemonSets.yaml                    // Manifests of default Daemonsets such as aws-node,kube-proxy
├── Deployments.yaml                   // Manifests of default Deployment such as corends
├── MutatingWebhook.json               // Manifests of All MutatingWebhookConfigurations
├── Storage_Classes.json               // Manifests of All StorageClasses
├── ValidatingWebhook.json             // Manifests of All ValidatingWebhookConfigurations
└── pod_name_namespace                 // Directory for Pod Specific Resources
    ├── Deployment_name.json           // Manifests of Deployemnt of Pod
    ├── Deployment_name.txt            // Describe of Deployemnt of Pod
    ├── Node_name.json                 // Manifests of Node where Pod is running
    ├── Node_name.txt                  // Describe of Node where Pod is running
    ├── Pod_name.json                  // Describe of Pod
    ├── Pod_name.txt                   // Manifests of Pod
    ├── ReplicaSet_name.json           // Manifests of Replicaset of Pod
    ├── ReplicaSet_name.txt            // Describe of Replicaset of Pod
    ├── SA_name.json                   // Manifests of Serviceaccount used by the Pod

    --- OPTIONAL ---

    ├── Services.json                     // Manifests of Services backed by the Pod
    ├── Services.txt                      // Describe of Services backed by the Pod
    ├── Ingress.json                      // Manifests of Ingresses backed by the Pod
    ├── Ingress.txt                       // Describe of Ingresses backed by the Pod
    ├── aws_lbc.json                      // Manifests of AWS Load Balancer Controller Deployment
    ├── aws_lbc.log                       // Logs of AWS Load Balancer Controller Deployment
    ├── PVC_{PVC_NAME}.json               // Manifest of PVC(s) used by the Pod
    ├── PVC_{PVC_NAME}.txt                // Describe of PVC(s) used by the Pod
    ├── PV_{PV_NAME}.json                 // Manifest of PV(s) used by the Pod
    ├── PV_{PV_NAME}.txt                  // Describe of PV(s) used by the Pod
    ├── ebs/efs-csi-controller.json       // Manifests of EBS/EFS CSI Controller Deployment
    ├── ebs/efs-csi-{container}}.log      // Logs of EBS/EFS CSI Controller Deployment containers
    ├── aws_lbc.log                       // Logs of AWS Load Balancer Controller Deployment
    └── pod_name.log                      // Pod Logs
```


### Examples

#### Example 1 : Get help
```
$ sudo bash ./eks-pod-information-collector.sh --help

USAGE: ./eks-pod-information-collector.sh -p <Podname> -n <Namespace of the pod> are Mandatory Flags

MANDATORY FLAGS NEEDS TO BE PROVIDED IN THE SAME ORDER

   -p  Pass this flag to provide the EKS pod name

   -n  Pass this flag to provide the Namespace in which above specified pod is running

OPTIONAL:
   -h Or -help to Show this help message.
```

#### Example 2 : To collect pod logs and create Archived (Tarball) file
```
$ sudo bash eks-pod-information-collector.sh -p coredns-6ff9c46cd8-gdhbh -n kube-system

Collecting information in Directory: /Users/advaitt/Documents/Work/EKS/eks-pod-information-collector/cni-np_2023-06-14_2353-UTC
Collecting Cluster Details, Review File: Cluster_Info.json
Collecting Default resources in KUBE-SYSTEM, Review Files ConfigMaps.yaml, DaemonSets.yaml, Deployments.yaml
Collecting Resource related to coredns-6ff9c46cd8-gdhbh, Review Files in Directory: coredns-6ff9c46cd8-gdhbh_kube-system
******** ATTENTION ********
 Please type yes Or y and press ENTER if you want to collect the logs of Pod , To Skip just press ENTER
***************************

Do you want to collect the Pod logs ?
>yes
Collecting logs of Pod

	[WARNING]: Please Remove any Confidential/Sensitive information (e.g. Logs, Passwords, API Tokens etc) and Bundle the logs using below Command

******** ATTENTION ********
 Please type yes Or y and press ENTER if you want to Create a Shareable TARBALL of the collected logs , To Skip just press ENTER
***************************

Do you want to create a Tarball of the collected logs ?
>yes
Archiving collected information

	Done!! your archived information is located in ${PWD}/<Cluster_Name>_2023-06-14_2353-UTC.tar.gz
```

#### Example 3 : If input arguments not specified
```
$ sudo bash eks-pod-information-collector.sh

USAGE: ./aws-eks-pod-information-collector-script.sh -p <Podname> -n <Namespace of the pod> are Mandatory Flags

Required FLAGS NEEDS TO BE PROVIDED IN THE SAME ORDER

	-p OR --podname 	Pass this flag to provide the EKS pod name
	-n OR --namespace	Pass this flag to provide the Namespace in which above specified pod is running

OPTIONAL:
	-h  To Show this help message.

	[ERROR]: POD_NAME & NAMESPACE Both are required!!

```