import boto3
from kubernetes import client, config
from collections import defaultdict
from tabulate import tabulate
import os, sys
from datetime import datetime

# Global variable to cache the aws-node DaemonSet
cached_aws_node_daemonset = None

def create_usage_bar(current, total, bar_length=10):
    try:
        percentage = (current / total) * 100
        filled_length = int(bar_length * current // total)
        bar = '█' * filled_length + '-' * (bar_length - filled_length)
        return f'|{bar}| {percentage:.1f}%'
    except Exception as e:
        print(f"Error creating usage bar: {str(e)}")
        return "N/A"

# Fetch and cache aws-node DaemonSet
def fetch_aws_node_daemonset(api_instance):
    global cached_aws_node_daemonset
    if cached_aws_node_daemonset is None:
        try:
            print("Fetching aws-node DaemonSet from Kubernetes API to Cache...")
            cached_aws_node_daemonset = api_instance.read_namespaced_daemon_set(name="aws-node", namespace="kube-system")
        except client.ApiException as e:
            print(f"Error fetching aws-node DaemonSet: {e}")
            cached_aws_node_daemonset = None
    else:
        print("Using cached aws-node DaemonSet.")
    return cached_aws_node_daemonset


def get_subnet_usage_info(ec2_client, subnet_id):
    print(f"Fetching subnet usage info for subnet {subnet_id}...")
    try:
        subnet_info = ec2_client.describe_subnets(SubnetIds=[subnet_id])['Subnets'][0]
        availability_zone = subnet_info['AvailabilityZone']
        cidr_block = subnet_info['CidrBlock']
        total_ips = 2 ** (32 - int(subnet_info['CidrBlock'].split('/')[1])) - 5
        available_ips = subnet_info['AvailableIpAddressCount']
        used_ips = total_ips - available_ips
        percentage_used = (used_ips / total_ips) * 100
        percentage_free = 100 - percentage_used

        return [
            availability_zone,
            cidr_block,
            total_ips,
            used_ips,
            available_ips,
            create_usage_bar(used_ips, total_ips)
        ]
    except Exception as e:
        print(f"Error fetching subnet usage info for subnet {subnet_id}: {str(e)}")
        return ["N/A"] * 6

def get_cluster_subnet_data(eks_client, ec2_client, cluster_name):
    print(f"Fetching subnet data for cluster {cluster_name}...")
    try:
        cluster_info = eks_client.describe_cluster(name=cluster_name)
        cluster_subnet_ids = cluster_info['cluster']['resourcesVpcConfig']['subnetIds']

        cluster_subnet_info = defaultdict(list)
        for subnet_id in cluster_subnet_ids:
            cluster_subnet_info[subnet_id] = get_subnet_usage_info(ec2_client, subnet_id)

        return cluster_subnet_info
    except Exception as e:
        print(f"Error fetching cluster subnet data for cluster {cluster_name}: {str(e)}")
        return defaultdict(list)


def get_cluster_worker_node_ips(v1, ec2_client):
    print("Fetching EC2 IPs for the EKS cluster...")
    worker_node_ips = set()
    subnet_ids = set()
    worker_subnet_info = defaultdict(list)

    try:
        # Pagination loop to fetch all nodes
        continue_token = None
        while True:
            if continue_token:
                nodes = v1.list_node(watch=False, _continue=continue_token)
            else:
                nodes = v1.list_node(watch=False)

            # Iterate through nodes and get their private IP addresses, instance id, subnet id
            for node in nodes.items:
                for address in node.status.addresses:
                    if address.type == 'InternalIP':
                        worker_node_ips.add(address.address)
                        try:
                            subnet_id = get_worker_node_subnets(ec2_client, address.address)
                            if subnet_id:
                                subnet_ids.add(subnet_id)
                        except Exception as e:
                            print(f"Error getting subnet for worker node {address.address}: {str(e)}")

            # Check if there is a continue token, meaning more results to fetch
            continue_token = nodes.metadata._continue
            if not continue_token:
                break

        # Fetch subnet usage info for all unique subnets
        for subnet_id in subnet_ids:
            try:
                worker_subnet_info[subnet_id] = get_subnet_usage_info(ec2_client, subnet_id)
            except Exception as e:
                print(f"Error getting subnet usage info for subnet {subnet_id}: {str(e)}")
                worker_subnet_info[subnet_id] = ["N/A"] * 6

    except Exception as e:
        print(f"Error fetching cluster worker node IPs: {str(e)}")

    return worker_node_ips, worker_subnet_info


def get_cluster_pod_ips(v1):
    print("Fetching Pod IPs...")
    pod_ips = set()

    try:
        # Pagination loop to fetch all pods
        continue_token = None
        while True:
            if continue_token:
                pods = v1.list_pod_for_all_namespaces(watch=False, _continue=continue_token)
            else:
                pods = v1.list_pod_for_all_namespaces(watch=False)

            # Collect Pod IPs
            for pod in pods.items:
                if pod.status.pod_ip:
                    pod_ips.add(pod.status.pod_ip)
                else:
                    print(f"Warning: Pod {pod.metadata.name} in namespace {pod.metadata.namespace} has no IP address")

            # Check if there is a continue token, meaning more results to fetch
            continue_token = pods.metadata._continue
            if not continue_token:
                break

    except Exception as e:
        print(f"Error fetching cluster pod IPs: {str(e)}")

    return pod_ips


# Check CNI variable using cached aws-node DaemonSet
def check_cni_var(api_instance, mode):
    print(f"Checking if {mode} is enabled...")
    daemonset = fetch_aws_node_daemonset(api_instance)
    if daemonset:
        env_vars = {var.name: var.value for var in daemonset.spec.template.spec.containers[0].env if var.value is not None}
        check_variable = env_vars.get(mode, "").lower() == "true"
        if mode not in env_vars:
            print(f"WARNING: {mode} environment variable is not set")
        return check_variable
    else:
        return False


def get_eniconfig_subnet_ids(custom_objects):
    print("Fetching ENIConfig subnet IDs...")
    try:
        eniconfigs = custom_objects.list_cluster_custom_object(
            group="crd.k8s.amazonaws.com",
            version="v1alpha1",
            plural="eniconfigs"
        )
        return [item['spec']['subnet'] for item in eniconfigs['items'] if 'spec' in item and 'subnet' in item['spec']]
    except client.ApiException as e:
        print(f"Exception when calling CustomObjectsApi->list_cluster_custom_object: {e}")
        return []


# Fetch WARM target values using cached aws-node DaemonSet
def get_warm_target_values(api_instance):
    daemonset = fetch_aws_node_daemonset(api_instance)
    print("Fetching WARM_ENI_TARGET, WARM_PREFIX_TARGET, WARM_IP_TARGET and MINIMUM_IP_TARGET values...")
    if daemonset:
        env_vars = {var.name: var.value for var in daemonset.spec.template.spec.containers[0].env if var.value is not None}
        warm_ip_target = env_vars.get("WARM_IP_TARGET")
        warm_prefix_target = env_vars.get("WARM_PREFIX_TARGET")
        warm_eni_target = env_vars.get("WARM_ENI_TARGET")
        minimum_ip_target = env_vars.get("MINIMUM_IP_TARGET")

        if "WARM_IP_TARGET" not in env_vars:
            print("WARNING: WARM_IP_TARGET environment variable is not set")
        if "WARM_PREFIX_TARGET" not in env_vars:
            print("WARNING: WARM_PREFIX_TARGET environment variable is not set")
        if "WARM_ENI_TARGET" not in env_vars:
            print("WARNING: WARM_ENI_TARGET environment variable is not set")
        if "MINIMUM_IP_TARGET" not in env_vars:
            print("WARNING: MINIMUM_IP_TARGET environment variable is not set")
        
        return warm_ip_target, warm_prefix_target, warm_eni_target, minimum_ip_target
    else:
        print("Could not retrieve IP envs from VPC CNI")
        return None, None, None


def get_worker_node_subnets(ec2_client, internal_ip):
    print(f"Fetching subnet for worker node with IP: {internal_ip}")
    try:
        response = ec2_client.describe_network_interfaces(
            Filters=[
                {
                    'Name': 'addresses.private-ip-address',
                    'Values': [internal_ip]
                }
            ]
        )

        if response['NetworkInterfaces']:
            network_interface = response['NetworkInterfaces'][0]
            subnet_id = network_interface['SubnetId']
            print(f"Found subnet {subnet_id} for worker node {internal_ip}")
            return subnet_id
        else:
            print(f"No network interface found for worker node {internal_ip}")
            return None

    except Exception as e:
        print(f"Error fetching subnet for worker node {internal_ip}: {str(e)}")
        return None


def generate_log_file(cluster_name, subnet_ips, worker_node_ips, pod_ips, worker_subnets, 
                      warm_ip_target, warm_prefix_target, warm_eni_target, minimum_ip_target, custom_networking_enabled,
                      prefix_delegation_enabled, eniconfig_subnets, ec2_client):
    now = datetime.now()
    timestamp = now.strftime("%Y-%m-%d_%H-%M-%S")
    filename = f"cluster_network_analysis_{timestamp}.txt"
    with open(filename, 'w') as log_file:
        log_file.write(f"=== EKS Cluster IP Analysis ===\n")
        log_file.write(f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
        log_file.write(f"Cluster Name: {cluster_name}\n\n")

        log_file.write("=== Cluster IP Usage Summary ===\n\n")
        log_file.write(f"EC2 Instance IPs: {len(worker_node_ips)}\n")
        log_file.write(f"Pod IPs: {len(pod_ips) - 2}\n\n")

        headers = ["Subnet ID", "AZ", "CIDR", "Total IPs", "Used IPs", "Free IPs", "Usage Bar"]

        cluster_table_data = []
        for subnet_id, data in subnet_ips.items():
            cluster_table_data.append([subnet_id] + data)

        log_file.write("Control Plane Subnets:\n")
        log_file.write(tabulate(cluster_table_data, headers=headers, tablefmt="grid"))
        log_file.write("\n\n")

        worker_table_data = []
        for subnet_id, data in worker_subnets.items():
            worker_table_data.append([subnet_id] + data)

        log_file.write("Worker Node Subnets:\n")
        log_file.write(tabulate(worker_table_data, headers=headers, tablefmt="grid"))
        log_file.write("\n\n")

        prefix_delegation_message = f"Prefix Delegation is {'enabled' if prefix_delegation_enabled else 'disabled'}."
        log_file.write("=" * len(prefix_delegation_message) + "\n")
        log_file.write(prefix_delegation_message + "\n")
        log_file.write("=" * len(prefix_delegation_message) + "\n\n")

        warm_target_data = [
            ["WARM_ENI_TARGET", warm_eni_target or "Not set", "1"],
            ["WARM_IP_TARGET", warm_ip_target or "Not set", "--"],
            ["MINIMUM_IP_TARGET", minimum_ip_target or "Not set", "--"],
            ["WARM_PREFIX_TARGET", warm_prefix_target or "Not set", "--"]
        ]
        warm_target_headers = ["Variable", "Value", "Default"]
        log_file.write("WARM Target Values:\n")
        log_file.write(tabulate(warm_target_data, headers=warm_target_headers, tablefmt="grid"))
        log_file.write("\n\nFor details see: https://github.com/aws/amazon-vpc-cni-k8s/blob/master/docs/eni-and-ip-target.md\n\n")

        custom_networking_message = f"Custom Networking is {'enabled' if custom_networking_enabled else 'disabled'}."
        log_file.write("=" * len(custom_networking_message) + "\n")
        log_file.write(custom_networking_message + "\n")
        log_file.write("=" * len(custom_networking_message) + "\n\n")

        if custom_networking_enabled and eniconfig_subnets:
            eniconfig_table_data = []
            for subnet_id in eniconfig_subnets:
                subnet_info = get_subnet_usage_info(ec2_client, subnet_id)
                eniconfig_table_data.append([subnet_id] + subnet_info)
            
            log_file.write("ENIConfig Subnets:\n")
            log_file.write(tabulate(eniconfig_table_data, headers=headers, tablefmt="grid"))
            log_file.write("\n\n")
        elif custom_networking_enabled:
            log_file.write("No ENIConfig subnets found.\n\n")

        log_file.write("=== End of Analysis ===\n")
        print(f"\n\nResults have been written to {filename}")

def main():
    print("\n=== Initializing EKS Cluster IP Analysis ===\n")

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

    print("\nFetching current Kubernetes context...")
    contexts, active_context = config.list_kube_config_contexts()
    if not contexts:
        print("Error: No Kubernetes contexts found. Please check your kubeconfig.")
        return
    
    cluster_name = active_context['context']['cluster'].split("/")[-1]
    print(f"Current context: {cluster_name}")

    print("\n=== Gathering Cluster Data ===\n")

    print("Fetching cluster subnet data...")
    subnet_ips = get_cluster_subnet_data(eks_client, ec2_client, cluster_name)
    print("Cluster subnet data fetched successfully.")

    print("\nFetching worker node and pod IPs...")
    worker_node_ips, worker_subnets = get_cluster_worker_node_ips(v1, ec2_client)
    pod_ips = get_cluster_pod_ips(v1)
    print("Worker node and pod IPs fetched successfully.")

    print("Fetching WARM_IP_TARGET and WARM_ENI_TARGET values...")
    warm_ip_target, warm_prefix_target, warm_eni_target, minimum_ip_target = get_warm_target_values(api_instance)

    print("\nChecking Prefix Delegation status...")
    prefix_delegation_enabled = check_cni_var(api_instance, "ENABLE_PREFIX_DELEGATION")

    print("\nChecking Custom Networking status...")
    custom_networking_enabled = check_cni_var(api_instance, "AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG")

    eniconfig_subnets = None
    if custom_networking_enabled:
        print("\nFetching ENIConfig subnet details...")
        eniconfig_subnets = get_eniconfig_subnet_ids(custom_objects)

    print("\nGenerating log file...")
    generate_log_file(cluster_name, subnet_ips, worker_node_ips, pod_ips, worker_subnets, 
                      warm_ip_target, warm_prefix_target, warm_eni_target, minimum_ip_target, custom_networking_enabled, 
                      prefix_delegation_enabled, eniconfig_subnets, ec2_client)

    print("\n=== Analysis Complete ===\n")

if __name__ == "__main__":
    main()