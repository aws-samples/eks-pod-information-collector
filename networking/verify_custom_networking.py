import boto3
from kubernetes import client, config
from collections import defaultdict
from tabulate import tabulate
from network_overview import *
import os
from datetime import datetime

def write_table_to_file(table_data, headers):
    print("\nWriting table to file...")
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"eniconfig_worker_subnet_mapping_{timestamp}.txt"
    
    try:
        with open(filename, 'w') as f:
            f.write("ENIConfig and Worker Node Subnet Mapping:\n\n")
            f.write(tabulate(table_data, headers=headers, tablefmt="grid", colalign=("left", "left", "left")))
        print(f"Table successfully written to file: {os.path.abspath(filename)}")
    except IOError as e:
        print(f"Error writing to file: {e}")


def get_eniconfig_data(custom_objects, ec2_client):
    print("\nFetching ENIConfig data...")
    eniconfig_subnets = get_eniconfig_subnet_ids(custom_objects) 
    eniconfig_subnet_data = defaultdict(list)
    for subnet_id in eniconfig_subnets:
        eniconfig_subnet_data[subnet_id].append(get_subnet_usage_info(ec2_client, subnet_id))
    print("ENIConfig data fetched successfully.")
    return eniconfig_subnet_data

def get_worker_subnet_data(v1, ec2_client):
    print("\nFetching worker subnet data...")
    _, worker_subnet_info = get_cluster_worker_node_ips(v1, ec2_client)
    print("Worker subnet data fetched successfully.")
    return worker_subnet_info

def create_table_data(eniconfig_subnet_data, worker_subnet_info):
    print("\nCreating table data...")
    table_data = []
    all_azs = set()

    # Collect all AZs
    for subnet_info in eniconfig_subnet_data.values():
        all_azs.add(subnet_info[0][0])
    for subnet_info in worker_subnet_info.values():
        all_azs.add(subnet_info[0])

    # Create table rows
    for az in sorted(all_azs):
        worker_subnets = []
        eniconfig_subnets = []

        # Find worker subnets for this AZ
        for subnet_id, info in worker_subnet_info.items():
            if info[0] == az:
                worker_subnets.append(f"{subnet_id} ({info[1]})")

        # Find ENIConfig subnets for this AZ
        for subnet_id, info in eniconfig_subnet_data.items():
            if info[0][0] == az:
                eniconfig_subnets.append(f"{subnet_id} ({info[0][1]})")

        worker_subnet_str = "\n".join(worker_subnets) if worker_subnets else "N/A"
        eniconfig_subnet_str = "\n".join([f"{i+1}: {subnet}" for i, subnet in enumerate(eniconfig_subnets)]) if eniconfig_subnets else "N/A"

        table_data.append([
            az,
            worker_subnet_str,
            eniconfig_subnet_str
        ])

    print("Table data created successfully.")
    return table_data

def print_table(table_data):
    headers = ["Availability Zone", "Worker Node Subnet(s)", "ENIConfig Name(s) and Subnet(s)"]
    print("\nENIConfig and Worker Node Subnet Mapping:")
    print(tabulate(table_data, headers=headers, tablefmt="grid", colalign=("left", "left", "left")))

def main():
    print("Initializing boto3 clients...")
    eks_client = boto3.client('eks')
    ec2_client = boto3.client('ec2')
    print("Boto3 clients initialized successfully.")
    
    print("\nLoading Kubernetes config...")
    config.load_kube_config()
    v1 = client.CoreV1Api()
    api_instance = client.AppsV1Api()
    custom_objects = client.CustomObjectsApi()
    print("Kubernetes config loaded successfully.")

    eniconfig_subnet_data = get_eniconfig_data(custom_objects, ec2_client)
    worker_subnet_info = get_worker_subnet_data(v1, ec2_client)

    #implement

    check_cni_var(api_instance, "AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG")
    check_cni_var(api_instance, "ENI_CONFIG_LABEL_DEF")

    table_data = create_table_data(eniconfig_subnet_data, worker_subnet_info)
    print_table(table_data)

    headers = ["Availability Zone", "Worker Node Subnet(s)", "ENIConfig Name(s) and Subnet(s)"]
    write_table_to_file(table_data, headers)

if __name__ == "__main__":
    main()