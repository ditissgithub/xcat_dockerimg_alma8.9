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
if [ $last_node_no -gt 1 ] && [ $last_node_no -lt 10 ]; then
    base_cn_prefix="${prefix}"
elif [ $last_node_no -gt 10 ] && [ $last_node_no -lt 100 ]; then
    base_cn_prefix="${prefix}0"
elif [ $last_node_no -gt 100 ] && [ $last_node_no -lt 1000 ]; then
    base_cn_prefix="${prefix}00"
elif [ $last_node_no -gt 1000 ] && [ $last_node_no -lt 10000 ]; then
    base_cn_prefix="${prefix}000"
elif [ $last_node_no -gt 10000 ]; then
    base_cn_prefix="${prefix}0000"
else
    echo "\$last_node_no is greater than 100000"
    exit 1
fi

for ((i = start_node_no; i <= last_node_no; i++)); do
  # Read MAC address from compute_mac.txt
  mac=$(sed -n "${i}p" compute_mac.txt)

  if [ -z "$mac" ]; then
    echo "Error: MAC address not found for node $i in compute_mac.txt"
    exit 1
  fi

   # Nested conditions to set the prefix
    if [ $i -lt 10 ]; then
        cn_prefix="${base_cn_prefix}"
        if [ $i == 9 ]; then
        base_cn_prefix=${base_cn_prefix%?}  # Remove one trailing character
        fi
    elif [ $i == 10 ] || [ $i -gt 10 ] && [ $i -lt 100 ]; then
        cn_prefix="${base_cn_prefix}"
        if [ $i == 99 ]; then
        base_cn_prefix=${base_cn_prefix%?}
        fi
    elif [ $i == 100 ] || [ $i -gt 100 ] && [ $i -lt 1000 ]; then
        cn_prefix="${base_cn_prefix}"
        if [ $i == 999 ]; then
        base_cn_prefix=${base_cn_prefix%?}
        fi
    elif [ $i == 1000 ] || [ $i -gt 1000 ] && [ $i -lt 10000 ]; then
        cn_prefix="${base_cn_prefix}"
        if [ $i == 9999 ]; then
        base_cn_prefix=${base_cn_prefix%?}
        fi
    elif [ $i == 10000 ] || [ $i -gt 10000 ]; then
        cn_prefix="${base_cn_prefix}"
    else
        echo "None of the conditions met for node $i"
        exit 1
    fi

  if [ $i -le 254 ]; then
  # Construct the IP network variable
  pvt_ip_network_var=$(echo $pv_net_address | awk -F '.' '{print $1"."$2"."$3}')
  bmc_ip_network_var=$(echo $bmc_net_address | awk -F '.' '{print $1"."$2"."$3}')
  ib_ip_network_var=$(echo $ib_net_address | awk -F '.' '{print $1"."$2"."$3}')
  # Construct the full IP address
  pvt_ip_network="${pvt_ip_network_var}.${i}"
  bmc_ip_network="${bmc_ip_network_var}.${i}"
  ib_ip_network="${ib_ip_network_var}.${i}"

  # Add node definition
  mkdef -t node "${cn_prefix}${i}" groups=compute,all bmc="${bmc_ip_network}" bmcpassword=0penBmc bmcusername=root nicips.ib0="${ib_ip_network}" nicnetworks.ib0=ib0 nictypes.ib0=Infiniband mgt=ipmi ip="${pvt_ip_network}" installnic=mac primarynic=mac mac="$mac" netboot=xnba postscripts="confignetwork -s,lustre.sh,ringbuf.sh"

  else
  # Construct the IP network variable
  pvt_ip_network_var=$(echo $pv_net_address | awk -F '.' '{print $1"."$2}')
  bmc_ip_network_var=$(echo $bmc_net_address | awk -F '.' '{print $1"."$2}')
  ib_ip_network_var=$(echo $ib_net_address | awk -F '.' '{print $1"."$2}')
  m=$($last_node_no/254)
  n=$($last_node_no/254)
    for ((y = 1; y <= m; y++)); do
      o=$($last_node_no-254)
      o=$($o-254)
      if [ $o -lt $n ]; then
        R=$((1+$(echo $pv_net_address | awk -F '.' '{print $3}')))
        S=$((1+$(echo $bmc_net_address | awk -F '.' '{print $3}')))
        T=$((1+$(echo $ib_net_address | awk -F '.' '{print $3}')))
        for ((x = 1; x <=$n; x++)); do
          pvt_ip_network=$($pvt_ip_network_var.$R.$x)
          bmc_ip_network=$($bmc_ip_network_var.$S.$x)
          ib_ip_network=$($ib_ip_network_var.$T.$x)
          mkdef -t node "${cn_prefix}${i}" groups=compute,all bmc="${bmc_ip_network}" bmcpassword=0penBmc bmcusername=root nicips.ib0="${ib_ip_network}" nicnetworks.ib0=ib0 nictypes.ib0=Infiniband mgt=ipmi ip="${pvt_ip_network}" installnic=mac primarynic=mac mac="$mac" netboot=xnba postscripts="confignetwork -s,lustre.sh,ringbuf.sh"
        done
      else
        R=$(($y+$(echo $pv_net_address | awk -F '.' '{print $3}')))
        S=$(($y+$(echo $bmc_net_address | awk -F '.' '{print $3}')))
        T=$(($y+$(echo $ib_net_address | awk -F '.' '{print $3}')))
        for ((x = 1; x <=254; x++)); do
          pvt_ip_network=$($pvt_ip_network_var.$R.$x)
          bmc_ip_network=$($bmc_ip_network_var.$S.$x)
          ib_ip_network=$($ib_ip_network_var.$T.$x)
          mkdef -t node "${cn_prefix}${i}" groups=compute,all bmc="${bmc_ip_network}" bmcpassword=0penBmc bmcusername=root nicips.ib0="${ib_ip_network}" nicnetworks.ib0=ib0 nictypes.ib0=Infiniband mgt=ipmi ip="${pvt_ip_network}" installnic=mac primarynic=mac mac="$mac" netboot=xnba postscripts="confignetwork -s,lustre.sh,ringbuf.sh"
        done
      fi
    done
  fi
done
