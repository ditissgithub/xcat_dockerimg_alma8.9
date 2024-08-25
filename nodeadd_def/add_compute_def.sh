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

for ((i = start_node_no; i <= last_node_no; i++)); do
  # Read MAC address from compute_mac.txt
  mac=$(sed -n "${i}p" compute_mac.txt)

  if [ -z "$mac" ]; then
    echo "Error: MAC address not found for node $i in compute_mac.txt"
    exit 1
  fi
  if [ $i -le 254 ]; then
  ip_network_var=$(echo $pv_net_address | awk -F '.' '{print $1"."$2.$3}')
  else [ $i -gt 254 ]; then
  m=$($last_node_no/254)
  ip_network_var=$(echo $pv_net_address | awk -F '.' '{print $1"."$2')
  ip_network=$($ip_network_var.$x.$y)
  
  ip_network_var=$(echo $pv_net_address | awk -F '.' '{print $1"."$2.$3}')
  
  a=$((i))
  b=10
  c=100
  j=$((a+150))

  if [ $a -lt $b ]; then
    cn_prefix="rbcn00"
  elif [ $a == $b ] || [ $a -gt $b ] && [ $a -lt $c ]; then
    cn_prefix="rbcn0"
  elif [ $a == $c ] || [ $a -gt $c ]; then
    cn_prefix="rbcn"
  else
    echo "None of the conditions met"
    exit 1
  fi

  # Add node definition
  mkdef -t node "${cn_prefix}${a}" groups=compute,all bmc="${bmc_ip_network}${a}" bmcpassword=0penBmc bmcusername=root nicips.ib0="${ib_ip_network}${a}" nicnetworks.ib0=ib0 nictypes.ib0=Infiniband mgt=ipmi ip="${ip_network}${a}" installnic=mac primarynic=mac mac="$mac" netb                                                                                  oot=xnba postscripts="confignetwork -s,lustre.sh,ringbuf.sh"
done
