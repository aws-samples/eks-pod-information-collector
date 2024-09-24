# AWS EKS IP Usage Analysis

This Python script analyzes the IP usage and related configurations of an Amazon Elastic Kubernetes Service (EKS) cluster. It provides detailed information about subnet utilization, EC2 instance IPs, Pod IPs, and various settings related to the Amazon VPC CNI plugin.

## Supported Features

1. **EC2**: The script retrieves the private IP addresses of EC2 instances in the EKS cluster's managed node groups.
2. **Node Groups**: The analysis includes IP usage information for managed and self managed within the EKS cluster.
3. **Custom Networking**: If custom networking is enabled in the cluster, the script fetches and displays details about the ENIConfig custom resource, including the associated subnet IDs and their usage information.

## In Progress

1. Fargate (not needed -> detect and advise "add new subnet")
2. Windows
3. IPv6

## Requirements

- Python 3.x
- AWS CLI (configured with appropriate credentials)
- Kubernetes Python client (`kubernetes` package)
- Tabulate Python package (`tabulate`)

Scope:
1. Network overview over chat/call or cx to get a summary of IP usage when there is an issue
2. Faster resolution / Cx Sentiment
3. IRSA/ Custom Networking/ IP Exhaustion/ Prefix delegation ==> Validations
....
