# Prepare VM Environment

Before we can deploy Kubernetes to VMs on our Proxmox system, we need to set up the environment. This means creating a VM template and several target VMs to host various Kubernetes resources.

Let's get going!

## Create a Proxmox Cloud-init VM Template

One of the best features of Proxmox is the [cloud-init](https://pve.proxmox.com/wiki/Cloud-Init_Support) system. This makes it possible to download a standardized cloud image and provide parameters to quickly provision VMs from a template. To do that, we need to build the template itself.

Cloud images are usually provided in either `.img` or `.qcow2` format. Find the one for your favorite operating system and download it to the Proxmox server. Common options may include:

* [Debian Official Cloud Images](https://cloud.debian.org/images/cloud/)
* [Ubuntu Cloud Images](https://cloud-images.ubuntu.com/)
* [Rocky Linux Cloud Images](https://rockylinux.org/cloud-images/)

This example will use the latest Debian stable image:

```bash
mkdir ~/images
cd ~/images
wget https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2
mv debian-12-genericcloud-amd64.qcow2 debian-12-genericcloud-amd64.img
```

We renamed the `.qcow2` file to `.img` for subsequent steps which expect certain extensions. Next, we need to actually build the template.

```bash
cd ~/images

qm create 5000 --name debian-bookworm-cloud \
               --memory 4096 --balloon 0 --numa 1 \
               --cpu host --sockets 2 --cores 2  \
               --net0 virtio,bridge=vmbr0 \
               --scsihw virtio-scsi-pci

qm importdisk 5000 debian-12-genericcloud-amd64.img tank-pool

qm set 5000 --scsihw virtio-scsi-pci --scsi0 tank-pool:vm-5000-disk-0,ssd=1
qm set 5000 --ide2 tank-pool:cloudinit
qm set 5000 --boot order=scsi0
qm set 5000 --serial0 socket --vga serial0
qm set 5000 --template 1
```

The first command actually creates a VM with several desirable attributes. The Proxmox `qm` command is extremely handy for automating VM management, allowing us to avoid the GUI and get this going quickly. Two important notes here, are that we disable memory ballooning to get a stable RAM allocation, and enable NUMA so the VM is aware of memory locality for better CPU thread assignment.

The next command creates a storage allocation in the `tank-pool` storage pool we created during the bootstrap process. We don't set a size here, as the initial size will be determined by the cloud image itself. The image we chose ends up being 2GB when fully expanded.

Next we set some options on that root storage, such as enabling SSD mode so TRIM commands are properly propagated to underlying storage. We also add an `ide2` device which we name `cloudinit`. This is how our cloud-init parameters are actually passed into the VM during the boot process when the operating system initializes. We also attach a serial device so Proxmox can attch to the VM display with VNC. The final thing we do is set the VM as a template, preventing any booting. From now on, the VM can only be used to create _other_ VMs through cloning.

Once we've created the template VM, we need to define a few essential cloud-init parameters through further `qm` commands:

```bash
qm set 5000 --ciuser bones --sshkeys ~/.ssh/authorized_keys --ipconfig0 ip=dhcp
```

This line performs three key actions:

1. Sets the user to something _other_ than the default for the cloud image. This is often arbitrary and inconvenient. Set it to something simple based on the machine that will be interacting with it most.
2. Imports all of the public keys currently registered with the Proxmox hypervisor. This will allow us immediate SSH access once the cloud images are initialized, from any system that can already access Proxmox itself.
3. Sets the default IP address to DHCP. We will be overriding this for cloned VMs, but should we forget that step, the VM will still be assigned a unique IP address upon boot.

Now our template is ready to use. All VMs based on it will automatically upgrade on boot, and set our SSH keys for remote access. Easy!

## Create Kubernetes VMs

Now we need to create the Kubernetes VMs themselves. The easiest way to do this is with a simple script which employs a loop for the number of machines we actually want. Something like this:

```bash
#!/bin/bash

TEMPLATE=5000

for x in {1..6}; do
  let node=$[500 + $x]
  let ip=$x
  qm clone ${TEMPLATE} ${node} --name kubernetes-${x} --full 1
  qm resize ${node} scsi0 +18G
  qm set ${node} --ipconfig0 ip=10.0.5.${ip}/16,gw=10.0.0.1
  qm start ${node}
done
```

This script does a few cool things for us:

1. Creates six full clone nodes from VM ID 501 to 506, named `kubernetes-1` through `kubernetes-6`
2. Adds 18GB of storage to the root filesystem of each node. The 2GB default inherited through the cloud image is probably not enough, so now is our chance to increase VM size.
3. Sets the IP address of each node as `10.0.5.1` to `10.0.5.6` for easy reference.
4. Immediately starts each node

Why six nodes? We'll need at least three for a proper Kubernetes control plane, and having multiple worker nodes is extremely convenient for load distribution and High Availability. If we implement replicating block storage, these often duplicate blocks across at least three worker nodes. So in total, we want a minimum of three of each node type as a starting point.

## Create HAProxy VM

This step is required primarily for K0s-based Kubernetes clusters. Unlike K3s or K8s, K0s does _not_ facilitate worker-node-hosted VIP capabilities for accessing the control plane. As a result, the workers _themselves_ will encounter problems trying to access the control plane. The K0s documentation has a page on [Control Plane High Availablity](https://docs.k0sproject.io/head/high-availability/) where they provide instructions for configuring HAProxy to fill this role.

Since we have functional IP addresses for all of our nodes, we just need to create one more VM to host the HAProxy service. We can even use a similar script to the one that built the Kubernetes VMs:

```bash
#!/bin/bash

TEMPLATE=5000

let node=510
let ip=10
qm clone ${TEMPLATE} ${node} --name kubernetes-lb --full 1
qm resize ${node} scsi0 +8G
qm set ${node} --ipconfig0 ip=10.0.5.${ip}/16,gw=10.0.0.1
qm start ${node}
```

In this case, we created the proxy node with the IP address of `10.0.5.10`, which is easy to remember for later. We also named the VM `kubernetes-lb` so we know it's the Kubernetes load balancer for our control plane.

## Next Steps

Continue with [Install Kubernetes Platform](install-k0s.md) to create the cluster.
