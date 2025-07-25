import subprocess
import sys
import re
import readline  # Import the readline module for enhanced input

# Function to run shell commands
def run_command(command):
    try:
        result = subprocess.run(command, shell=True, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return result.stdout.decode().strip()
    except subprocess.CalledProcessError as e:
        print(f"Command failed: {e}")
        sys.exit(1)

# Function to define node prefix based on the node number and max digit count
def define_prefix(node_number, prefix, max_digit_count):
    formatted_node_number = str(node_number).zfill(max_digit_count)
    return f"{prefix}{formatted_node_number}"

# Function to get the maximum number of digits needed for node numbering
def get_max_digit_count(start_node_no, last_node_no):
    max_digit_count = len(str(last_node_no))  # Get the length of the last node number
    # Ensure at least 3 digits for node numbers like rbcn001, rbcn011
    return max(max_digit_count, 3)

# Function to get input with backspace support using readline
def get_user_input(prompt):
    try:
        return input(prompt)
    except EOFError:
        print("Error: End of input encountered!")
        sys.exit(1)


# Prompt for inputs
subnet_prefix = int(input("Enter The Subnet Prefix of Network (Valid range: 18-24): "))
if subnet_prefix < 18 or subnet_prefix > 24:
    print("Invalid subnet prefix. Please enter a value between 18 and 24.")
    sys.exit(1)

node_type = get_user_input("Enter The Node Type To Add In Groups (For ex: compute, hm, gpu): ")
pv_net_address = get_user_input(f"Enter Private Network Address (Starting Pvt_IP Address of {node_type} node): ")
bmc_net_address = get_user_input(f"Enter BMC Network Address (Starting BMC_IP Address of {node_type} node): ")
ib_net_address = get_user_input(f"Enter IB Network Address (Starting IB_IP Address of {node_type} node): ")
prefix = get_user_input(f"Enter The Prefix Value For {node_type} node (For ex: rbcn, rpcn, cn, rbhm, rbgpu): ")
start_node_no = int(get_user_input(f"Enter The Start {node_type} node no: "))
last_node_no = int(get_user_input(f"Enter The Last {node_type} node no: "))
mac_file = get_user_input(f"Enter The MAC file to add {node_type} node definition (For ex: compute_mac.txt, gpu_mac.txt, hm_mac.txt): ")

# Check if the MAC file exists
try:
    with open(mac_file, 'r') as file:
        mac_addresses = file.readlines()
except FileNotFoundError:
    print(f"Error: {mac_file} file not found!")
    sys.exit(1)

# Fetch existing nodes and find the maximum number of digits
existing_nodes_output = run_command(f"lsdef -t node | grep '{prefix}' || true")  # Append '|| true' to prevent failure
existing_nodes = existing_nodes_output.splitlines()

# Get the maximum digit count based on the last node number (minimum 3 digits)
max_digit_count = get_max_digit_count(start_node_no, last_node_no)

# Calculate network variables
pvt_ip_network_var = ".".join(pv_net_address.split('.')[:2])
bmc_ip_network_var = ".".join(bmc_net_address.split('.')[:2])
ib_ip_network_var = ".".join(ib_net_address.split('.')[:2])

pvt_ip_third_octet = int(pv_net_address.split('.')[2])
bmc_ip_third_octet = int(bmc_net_address.split('.')[2])
ib_ip_third_octet = int(ib_net_address.split('.')[2])

pvt_ip_fourth_octet = int(pv_net_address.split('.')[3])
bmc_ip_fourth_octet = int(bmc_net_address.split('.')[3])
ib_ip_fourth_octet = int(ib_net_address.split('.')[3])

# Main loop to define nodes
for node_number in range(start_node_no, last_node_no + 1):
    if node_number > len(mac_addresses):
        print(f"Error: MAC address not found for node {node_number} in {mac_file}")
        sys.exit(1)

    mac = mac_addresses[node_number - 1].strip()
    if not mac:
        print(f"Error: MAC address not found for node {node_number}")
        sys.exit(1)

    # Define prefix based on node number and max digit count
    cn_prefix = define_prefix(node_number, prefix, max_digit_count)

    # Calculate network addresses
    R = pvt_ip_third_octet + (node_number // 254)
    S = bmc_ip_third_octet + (node_number // 254)
    T = ib_ip_third_octet + (node_number // 254)
    A = pvt_ip_fourth_octet + (node_number % 254) - 1
    B = bmc_ip_fourth_octet + (node_number % 254) - 1
    C = ib_ip_fourth_octet + (node_number % 254) - 1

    pvt_ip_network = f"{pvt_ip_network_var}.{R}.{A}"
    bmc_ip_network = f"{bmc_ip_network_var}.{S}.{B}"
    ib_ip_network = f"{ib_ip_network_var}.{T}.{C}"

    # Create node definitions in xCAT
    node_name = f"{cn_prefix}"
    cmd = f"""mkdef -f -t node "{node_name}" groups="{node_type},all" bmc="{bmc_ip_network}" bmcpassword=0penBmc \
              bmcusername=root nicips.ib0="{ib_ip_network}" nicnetworks.ib0=ib0 nictypes.ib0=Infiniband \
              mgt=ipmi ip="{pvt_ip_network}" installnic=mac primarynic=mac mac="{mac}" \
              netboot=xnba postscripts="confignetwork -s,lustre.sh,ringbuf.sh\""""
    run_command(cmd)
    print(f"Node {node_name} added successfully.")
