#!/bin/bash

#########This Bash code adds node definitions for compute nodes, scaling more than 10,000 nodes.############
# Prompt for inputs
read -p "Enter The Subnet Prefix of Network (Valid range: 18-24): " subnet_prefix
if [[ $subnet_prefix -ge 18 && $subnet_prefix -le 24 ]]; then
    echo "Subnet prefix is valid. Proceeding with the script..."
else
    echo "Invalid subnet prefix. Please enter a value between 18 and 24."
    exit 1
fi

read -p "Enter Private Network Address (Starting Pvt_IP Address) Of The Subnet: " pv_net_address
read -p "Enter BMC Network Address (Starting BMC_IP Address) Of The Subnet: " bmc_net_address
read -p "Enter IB Network Address (Starting IB_IP Address) Of The Subnet: " ib_net_address
read -p "Enter The Prefix Value For Compute Node (For ex: rbcn or rpcn or cn): " prefix
read -p "Enter The Start Compute Node No: " start_node_no
read -p "Enter The Last Compute Node No: " last_node_no

# Check if mac.txt file exists
if [ ! -f "compute_mac.txt" ]; then
    echo "Error: compute_mac.txt file not found!"
    exit 1
fi

# Determine the base prefix based on the last node number
if [ $last_node_no -ge 1 ] && [ $last_node_no -lt 10 ]; then
    base_cn_prefix="${prefix}"
elif [ $last_node_no -ge 10 ] && [ $last_node_no -lt 100 ]; then
    base_cn_prefix="${prefix}0"
elif [ $last_node_no -ge 100 ] && [ $last_node_no -lt 1000 ]; then
    base_cn_prefix="${prefix}00"
elif [ $last_node_no -ge 1000 ] && [ $last_node_no -lt 10000 ]; then
    base_cn_prefix="${prefix}000"
elif [ $last_node_no -ge 10000 ]; then
    base_cn_prefix="${prefix}0000"
else
    echo "Last node number is greater than 100000"
    exit 1
fi

define_prefix() {
    j=$1
    if [ -z "$mac" ]; then
        echo "Error: MAC address not found for node $j in compute_mac.txt"
        exit 1
    fi
    # Nested conditions to set the prefix
    if [ $j -lt 10 ]; then
        cn_prefix="${base_cn_prefix}"
        if [ $j == 9 ]; then
            base_cn_prefix=${base_cn_prefix%?}  # Remove one trailing character
        fi
    elif [ $j == 10 ] || [ $j -gt 10 ] && [ $j -lt 100 ]; then
        cn_prefix="${base_cn_prefix}"
        if [ $j == 99 ]; then
            base_cn_prefix=${base_cn_prefix%?}
        fi
    elif [ $j == 100 ] || [ $j -gt 100 ] && [ $j -lt 1000 ]; then
        cn_prefix="${base_cn_prefix}"
        if [ $j == 999 ]; then
            base_cn_prefix=${base_cn_prefix%?}
        fi
    elif [ $j == 1000 ] || [ $j -gt 1000 ] && [ $j -lt 10000 ]; then
        cn_prefix="${base_cn_prefix}"
        if [ $j == 9999 ]; then
            base_cn_prefix=${base_cn_prefix%?}
        fi
    elif [ $j == 10000 ] || [ $j -gt 10000 ]; then
        cn_prefix="${base_cn_prefix}"
    else
        echo "None of the conditions met for node $j"
        exit 1
    fi
}

# Calculate the number of full subnet blocks and the remainder
num_full_blocks=$(($last_node_no / 254))
remaining_nodes=$(($last_node_no % 254))

# Main loop to define nodes
current_node=$start_node_no
for ((block = 0; block <= num_full_blocks; block++)); do
    if [ $block -eq $num_full_blocks ] && [ $remaining_nodes -gt 0 ]; then
        max_nodes_in_block=$remaining_nodes
    else
        max_nodes_in_block=254
    fi
    for ((i = 1; i <= max_nodes_in_block; i++)); do

        node_number=$(($current_node + $block * 254 + $i - 1))

        # Read MAC address from compute_mac.txt
        mac=$(sed -n "${node_number}p" compute_mac.txt)
        if [ -z "$mac" ]; then
            echo "Error: MAC address not found for node $node_number in compute_mac.txt"
            exit 1
        fi

        # Construct the IP network variables
        pvt_ip_network_var=$(echo $pv_net_address | awk -F '.' '{print $1"."$2}')
        bmc_ip_network_var=$(echo $bmc_net_address | awk -F '.' '{print $1"."$2}')
        ib_ip_network_var=$(echo $ib_net_address | awk -F '.' '{print $1"."$2}')
        R=$(($block + $(echo $pv_net_address | awk -F '.' '{print $3}')))
        S=$(($block + $(echo $bmc_net_address | awk -F '.' '{print $3}')))
        T=$(($block + $(echo $ib_net_address | awk -F '.' '{print $3}')))
        pvt_ip_network="${pvt_ip_network_var}.$R.$i"
        bmc_ip_network="${bmc_ip_network_var}.$S.$i"
        ib_ip_network="${ib_ip_network_var}.$T.$i"

        define_prefix $node_number

        mkdef -t node "${cn_prefix}${node_number}" groups=compute,all bmc="${bmc_ip_network}" \
            bmcpassword=0penBmc bmcusername=root nicips.ib0="${ib_ip_network}" \
            nicnetworks.ib0=ib0 nictypes.ib0=Infiniband mgt=ipmi ip="${pvt_ip_network}" \
            installnic=mac primarynic=mac mac="$mac" netboot=xnba \
            postscripts="confignetwork -s,lustre.sh,ringbuf.sh"
    done
done
