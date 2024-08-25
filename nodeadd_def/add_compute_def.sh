#!/bin/bash
read -p "Enter The Subnet Prefix of Network:" subnet_prefix
# Check if the subnet prefix is within the valid range
if [[ $subnet_prefix -ge 18 && $subnet_prefix -le 24 ]]; then
    echo "Subnet prefix is valid. Proceeding with the script..."
    # Add the rest of your script commands here
else
    echo "Invalid subnet prefix. Please enter a value between 18 and 24."
    exit 1
fi

read -p "Enter Private Network Address (Starting Pvt_IP Address) Of The Subnet:" pv_net_address
read -p "Enter BMC Network Address (Starting BMC_IP Address) Of The Subnet:" bmc_net_address
read -p "Enter IB Network Address (Starting IB_IP Address) Of The Subnet:" ib_net_address
echo "Now You Are Adding The Node Definition !!!"
read -p "Enter The Prefix Value For Compute Node(For ex: rbcn or rpcn or cn):" prefix
read -p "Enter The Start Compute Node No: " start_node_no
read -p "Enter The Last Compute Node No: " last_node_no
#########This Bash code adds node definitions for compute nodes, scaling up to 16,382 nodes.############
##Define the network range##
ip_network_var=$(echo $pv_net_address | awk -F '.' '{print $1"."$2}')
bmc_ip_network_var=$(echo $bmc_net_address | awk -F '.' '{print $1"."$2}')
ib_ip_network_var=$(echo $ib_net_address | awk -F '.' '{print $1"."$2}')
#If the subnet prefix is 24
#If the subnet prefix is 23
#If the subnet prefix is 22
#If the subnet prefix is 21
#If the subnet prefix is 20
#If the subnet prefix is 19
#If the subnet prefix is 18


# Check if mac.txt file exists
if [ ! -f "compute_mac.txt" ]; then
  echo "Error: compute_mac.txt file not found!"
  exit 1
fi
# Determine the base prefix based on the last node number
if [ $last_node_no -lt 10 ]; then
    base_cn_prefix="${prefix}0"
elif [ $last_node_no -lt 100 ]; then
    base_cn_prefix="${prefix}00"
elif [ $last_node_no -lt 1000 ]; then
    base_cn_prefix="${prefix}000"
elif [ $last_node_no -lt 10000 ]; then
    base_cn_prefix="${prefix}0000"
elif [ $last_node_no -lt 100000 ]; then
    base_cn_prefix="${prefix}00000"
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

  a=10
  b=100
  c=1000
  d=10000
  e=100000
  # Nested conditions to set the prefix
    if [ $i -lt 10 ]; then
        cn_prefix="${base_cn_prefix}"
        base_cn_prefix=${base_cn_prefix%?}  # Remove one trailing character
    elif [ $i -lt 100 ]; then
        cn_prefix="${base_cn_prefix}"
        base_cn_prefix=${base_cn_prefix%?}
    elif [ $i -lt 1000 ]; then
        cn_prefix="${base_cn_prefix}"
        base_cn_prefix=${base_cn_prefix%?}
    elif [ $i -lt 10000 ]; then
        cn_prefix="${base_cn_prefix}"
        base_cn_prefix=${base_cn_prefix%?}
    elif [ $i -lt 100000 ]; then
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
elif [ $i -gt 254 ]; then
  # Construct the IP network variable
  pvt_ip_network_var=$(echo $pv_net_address | awk -F '.' '{print $1"."$2}')
  bmc_ip_network_var=$(echo $bmc_net_address | awk -F '.' '{print $1"."$2}')
  ib_ip_network_var=$(echo $ib_net_address | awk -F '.' '{print $1"."$2}')
  m=$($last_node_no/254)
  n=$($last_node_no/254)
  for ((y = 1; y <= m; y++)); do
    R=$(($y+$(echo $pv_net_address | awk -F '.' '{print $3}')))
    S=$(($y+$(echo $bmc_net_address | awk -F '.' '{print $3}')))
    T=$(($y+$(echo $ib_net_address | awk -F '.' '{print $3}')))
    for ((x = 1; x <=254; x++)); do
      pvt_ip_network=$($pvt_ip_network_var.$R.$x)
      bmc_ip_network=$($bmc_ip_network_var.$S.$x)
      ib_ip_network=$($ib_ip_network_var.$T.$x)
      
      if [ $i -lt $c ]; then
        cn_prefix="rbcn00"
      elif [ $i -eq $a ] || { [ $i -gt $a ] && [ $i -lt $b ]; }; then
        cn_prefix="rbcn0"
      elif [ $i -eq $b ] || [ $i -gt $b ]; then
        cn_prefix="rbcn"
      else
        echo "None of the conditions met"
        exit 1
      fi
      # Add node definition
      mkdef -t node "${cn_prefix}${i}" groups=compute,all bmc="${bmc_ip_network}" bmcpassword=0penBmc bmcusername=root nicips.ib0="${ib_ip_network}" nicnetworks.ib0=ib0 nictypes.ib0=Infiniband mgt=ipmi ip="${pvt_ip_network}" installnic=mac primarynic=mac mac="$mac" netboot=xnba postscripts="confignetwork -s,lustre.sh,ringbuf.sh"    
  
  
  


  # Add node definition
  mkdef -t node "${cn_prefix}${a}" groups=compute,all bmc="${bmc_ip_network}${a}" bmcpassword=0penBmc bmcusername=root nicips.ib0="${ib_ip_network}${a}" nicnetworks.ib0=ib0 nictypes.ib0=Infiniband mgt=ipmi ip="${ip_network}${a}" installnic=mac primarynic=mac mac="$mac" netboot=xnba postscripts="confignetwork -s,lustre.sh,ringbuf.sh"
done
