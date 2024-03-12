# Creating a Playground Kubernetes Cluster

These instructions will explain how to set up a [K0s Kubernetes Cluster](https://k0sproject.io/) in on a Proxmox host. These steps will create a VM template which is then cloned numerous times and set as targets for subsequent steps. Once the initial cluster is online, we include a few more to make the cluster actually _usable_, as K0s deployments are incredibly bare-bones.

We've split the guide into multiple parts, as the procedure is somewhat involved, and we've spent a lot of time describing what is happening during each step.

1. [Prepare VM Environment](vm-prep.md)
2. [Install Kubernetes Platform](install-k0s.md)
3. [Required Kubernetes Resources](install-apps.md)

All three parts must be complete before the Kubernetes cluster is nominally operational. Additionally, there are supplementary steps we recommend which install useful software:

* [Install a CloudNativePG Cluster](setup-cnpg.md) - Create a CloudNativePG Postgres cluster in our Kubernetes cloud

## Useful Kuburnetes Tools

The cluster isn't the only thing that requires a bit of TLC. The machine where we plan to administer the cluster should also have a couple of useful utilities installed. So before we start going nuts installing K0s, let's download and install two essential tools.

The first of these is [Kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/) for sending various CLI commands to our cluster once it's up and running.

```bash
export KCTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/$KCTL_VERSION/bin/linux/amd64/kubectl"
install -m 0755 kubectl ~/.local/bin/kubectl
```

Next we'll want to install [Helm](https://helm.sh/docs/intro/install/), which is widely accepted as the "Kubernetes package manager", making it much easier to install various software into our cluster.

```bash
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
```

These tools are both invaluable for managing the cluster itself. Don't forget them!

## Helper Scripts

Given this is a testbed of sorts, there are many operations which must be repeated frequently, and as such, should be scripted. There are currently two categories of scripts.

### VM Management

All of the scripts in this category should be placed on the Proxmox hypervisor where the VMs are hosted. It is also strongly recommended to use a utility such as [direnv](https://direnv.net/) to set one or more of these environment variables used by the scripts unless you just happen to be OK with the defaults:

* `GATEWAY` - The address of the router / gateway for this network. Default `10.0.0.1`.
* `IP_START` - Where to start IP addresses. This is a rudimentary system, so avoid using high values where the VM count can cause the maximum to exceed 255. Default `10.0.5.1`.
* `LB_NODE` - The node number for the Kubernetes load balancer VM. Default 510.
* `LB_IP` - The IP address for the load balancer VM itself.
* `NET_MASK` - The net mask to use for each VM IP address, in integer format. So `255.255.0.0` would be a mask of 16. Default 16.
* `TEMPLATE` - The VM template to use for creating the cloned VMs. Default 5000.
* `VM_COUNT` - The total number of VMs to create. Default 6.
* `VM_START` - Where to start numbering VMs. We recommend using a numbering system so the VMs line up nicely with the IP numbering. Default 501.

Then create a subdirectory for the scripts and place a `.envrc` file there so `dotenv` can set them automatically upon endering the directory. The three scripts are as follows:

1. [`create-k8s-vms.sh`](scripts/create-k8s-vms.sh) - Create all Kubernetes VMs using the environment variables listed above. Each VM will also be started once the template cloning step and configuration are complete. Assuming the template was defined according to the steps in this guide, these VMs will also have the same SSH host keys as the hypervisor, making it easy to connect to them for administrative purposes.
2. [`create-lb-vm.sh`](scripts/create-lb-vm.sh) - Create the load balancer VM necessary for K0s to work properly. Note that this only creates the VM using the same variables above for the sake of convenience and to follow a similar naming scheme. HAProxy still needs to be installed and configured, but this only has to be done once, no matter how many times the other nodes are created and destroyed.
3. [`destroy-k8s-vms.sh`](scripts/destroy-k8s-vms.sh) - Destroy the Kubernetes VMs using the environment variables listed above. VMs will be stopped prior to being removed, and will not prompt, so be _extra_ sure the `VM_START` and `VM_COUNT` variables are set properly, or it may destroy other VMs unintentionally.

### Kubernetes Installation

Given the amount of steps necessary to install Kubernetes properly, even K0s, there is also a script that automates the entire process described in the 3-step series. This script should be executed from a "home" machine which already has a SSH host key used by the Kubernetes VMs. If you used the creation scripts above, this should already be done. 

What the script will do:

1. Install any missing kubectl, Helm, and k0sctl tools for managing the cluster.
2. Install any missing Helm repositories for MetalLB and OpenEBS.
3. Install OpenEBS into the cluster and set the `openebs-hostpath` storage class as the default.
4. Install MetalLB into the cluster, register it with an address pool, and set it to advertise as an l2 load balancer within the cluster.

Simply edit this script to change the variables in the header before execution, and it should do the rest.

* [`install-k0s.sh`](scripts/install-k0s.sh)

All output produced by commands launched by the script is redirected to an `install.log` file. Check this file for errors if the process has problems. Otherwise, the script will chronicle each step of the installation for the sake of visibility.

