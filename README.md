# xcat_dockerimg_alma8.9

Note: Update the argument values in the dev.env file according to your requirements.

---

## 📄 xCAT Docker Environment Configuration (`dev.env`)

This `.env` file provides all necessary environment variables for deploying and configuring an xCAT-based cluster environment using Docker Compose. It enables modular, repeatable configuration for HA setups, MySQL, networking, and DNS components.
Source: https://xcat-docs.readthedocs.io/en/stable/guides/admin-guides/basic_concepts/global_cfg/index.html

### 🔁 High Availability (HA) Settings

* **`XCAT_VIP`**: The Virtual IP (VIP) address for xCAT management when configured in HA mode using **PCS**. All compute nodes and clients will interact with this VIP instead of individual nodes.

### 🛢️ MySQL Database Configuration

These variables configure the xCAT database backend to use MySQL instead of SQLite.

* **`MYSQL_PORT`**: Custom port for MySQL (avoid default `3306` if used by the host).
* **`MYSQL_ADMIN_PW`**: Password for the MySQL admin user (alphanumeric only).
* **`MYSQL_ROOT_PW`**: Root password for MySQL (alphanumeric only).

### 🕑 Time Synchronization

* **`TIMEZONE`**: Linux timezone setting to be applied across the cluster (e.g., `Asia/Kolkata`).

### 🌐 Network Interface for DHCP

Defines which network interfaces the xCAT DHCP server should listen on.

* **`DHCPINTERFACE`**: Comma-separated NIC list (e.g., `eth2,eth2:0`), or per-node/group format.

  * Example for all: `hpc-master01 | eth2,eth2:0;all`
  * Example for group: `xcatmn|eth1,eth2;service|bond0`

### 🌍 DNS Configuration

Set DNS domain details and upstream forwarders.

* **`DOMAIN`**: The DNS domain name for your cluster (e.g., `server.ac.in`).
* **`FORWARDERS`**: External DNS servers for resolving names outside the cluster.

  * Preferred: `172.25.0.3` (VIP)
  * Alternate: `172.25.0.1,172.25.0.2`
* **`MASTER`**: The xCAT master IP, typically set to the VIP in HA setups.
* **`NAMESERVERS`**: Nameservers used by cluster nodes.

  * Use `<xcatmaster>` for dynamic resolution based on node hierarchy
  * Or use a specific IP (e.g., `172.25.0.3`)

### 🔌 Infiniband (IB) Network Configuration

For HPC environments using IB networks.

* **`IB_NET`**: Base IB network (e.g., `172.26.0.0`)
* **`IB_MASK`**: IB subnet mask (e.g., `255.255.254.0`)
* **`XCAT_MASTER`**: DNS gateway for IB nodes (usually `<xcatmaster>`)

### 🧠 Network Table Configuration

Controls how xCAT assigns and manages node networks.

* **`OBJECT_NAME`**: Identifier format based on network/mask (e.g., `172_25_0_0-255_255_254_0`)
* **`DHCP_SERVER`**: IP address of the DHCP provider, usually the xCAT VIP.
* **`GATEWAY`**: Gateway for compute nodes to reach xCAT.
* **`IP_MASK`**: Subnet mask for xCAT's management network.
* **`IP_NET`**: Base IP network for the management layer.
* **`MGT_IF_NAME`**: Interface name on the nodes (e.g., `eth2:0`).
* **`TFTP_SERVER`**: Server IP for PXE/TFTP boot services (often same as DHCP server).

### 📝 Notes

* The dev.env file must be copied to .env so that Docker Compose can use it.
* All passwords must be alphanumeric; special characters are not supported when inputting for the xCAT MySQL database.
* Ensure consistency between the `.env` file and any static network or node configuration managed by xCAT.
* Always reload Docker Compose after changing `.env` variables.

---


