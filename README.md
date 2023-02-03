## AWS EKS Cluster log Collector Script.

- You can pull this script and run it from your local machine against your EKS cluster with "ADMIN RBAC permission".
- Run command: ./eks-cluster-log-collector.sh <namespace-name>
- By default script will create a folder in your present directory with name <cluster-<Your-EKS-Cluster>.<DATE>-<TimeStamp>>
- By default script will collect all the Pods logs and resources info that are running in "DEFAULT" Namespace if user does not provide Namespace detail.
- It will create following list of files within the folder.
  1. ClusterDetails.txt --> It will include current EKS Cluster context information such as  Cluster ARN and control plan server
  
  2. ConfigMap.txt --> It will include AWS-Auth , CoreDNS, Kube-Proxy config map information
  
  3. EventsInfo.txt --> It will include all the recent k8 API events took place in this namespace
  
  4. FoundErrors.txt --> It will include all the presently occurring Errors and Failure in this nampespace with exact errormessage and file/resource info
  
  5. StorageInfo.txt --> It will include all the SC, PV, PVC deployed within  EKS cluster
  
  6. WebHookInfo.txt --> It will include all the configured webhook information within  EKS cluster
  
  7. WorkerNodeInfo.txt --> It will include all the Worknode info and top command output running within  EKS cluster
  
  8. AllResourceInfo.txt--> It will include all the info about deployed SVC , DP , DE, RS, PODS running within Namespace
  
  9. <namespace>.<Pod-Name>.describe.txt --> --> It will include the description of the running Pod
  
  10. <namespace>.<Pod-Name>.<deployemnt-name>.current.log --> It will include the logs of the running Pod
  
  11. cluster-<Your-EKS-Cluster>.<DATE>-<TimeStamp>.tar.gz --> It is the Archived version of all the above-mentioned files which you can share on your EKS support case for AWS support engineer review so they can efficiently assit you to troubleshoot your EKS related issue

 

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the LICENSE file.

