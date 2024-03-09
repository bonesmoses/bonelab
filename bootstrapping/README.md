# Bootstrapping a New Cluster

The Bones homelab currently consists of one or more [Proxmox](https://proxmox.com/en/) nodes. Follow these steps to get a node up to a minimal usable state.

## Hardware Settings

No matter what kind of system this is, make sure it is set to boot into UEFI mode. Most, if not all of the Proxmox instructions assume this is the boot system. Additionally, this may be the only mode which is compatible with 3rd-party boot devices such as PCIe adapters.

Set any and all RAID controller cards to HBA mode if possible so we can treat all attached drive as JBOD. We're going to be using ZFS, and it makes several assumptions which won't work as safely or efficiently with an intermediate controller card. It's better to have a "true" HBA card, but many newer full RAID devices can operate with device passthrough. If you can't do either of these, set up a 1-drive RAID for each drive so ZFS at least gets the full inventory of drives.

## Install Phase

[Download the latest ISO of Proxmox](https://proxmox.com/en/downloads/proxmox-virtual-environment/iso)

Once downloaded, use the Linux `dd` utility to copy the image to a flash device, as recommended by the [proxmox documentation](https://pve.proxmox.com/wiki/Prepare_Installation_Media):

```bash
dd if=proxmox-ve_8.1-2.iso of=/path/to/usb bs=1M conv=fdatasync
```

Install the USB media into the target server and reboot so the Proxmox installer is invoked.

It is _strongly_ recommended to use a ZFS drive mirror when installing Proxmox as a boot device. This will dramatically improve RTO in the event of a boot drive failure. Do not include _any other_ storage devices in any other menu; we will be handling that manually. The rest of the installation instructions should be self-explanatory.

> [!NOTE]
> Shortly following the installation of the second node in the cluster, the second boot device failed and required replacement. If this had been the only drive, a restore from backup or reinstallation of the node operating system would have been necessary.

## Shell and OS Setup

Use `ssh-copy-id` to transmit SSH key to newly installed system. This will _greatly_ simplify working with the server in the future.

Next we want to tweak several kernel setting. Simply execute the following commands on the server as `root`:

```
cat > /etc/sysctl.d/99-tweaks.conf << EOF
vm.swappiness=1
vm.overcommit_memory=2
vm.overcommit_kbytes=$(grep MemTotal /proc/meminfo | awk '{print $2}')
EOF

sysctl --system
```

Even though it's likely the server was set up without a SWAP device, we set the swapping preference to 1. It's a common trick on servers to strongly discourage swapping without making it outright impossible. Next, we prevent over-allocating memory to VMs. If memory pressure gets too high, the operating system may start arbitrarily killing processes, and that's decidedly less than ideal. Finally, we set the amount of available memory for allocation equal to the _exact_ amount of RAM.

The default setting for most systems is to set `overcommit_ratio=50` because they assume the _extremely_ outdated advice to allocate as much swap space as RAM. The 50% essentially ensures swap isn't interpreted as standard memory available to programs. But we much prefer using `overcommit_kbytes`, which isn't nearly as ambiguous.

## ZFS Filesystems

Aside from any boot drives, all other storage devices should be unallocated. Take some time to perform an inventory of the server to find all remaining drives. The easiest way to do this is by examining the `/dev/disk/by-id` folder. These IDs will often have manufacture designation, storage media type (ata, scsi, NVMe) and other relevant details.

Create a storage pool named "tank" with one or more vdevs and if possible, an SLOG device. This example is from the first system in the cluster:

```bash
zpool create -f -o ashift=12 tank \
  raidz1 ata-SAMSUNG_MZ7LM1T9HCJM-00003_S1YKNXAGB15742 \
         ata-SAMSUNG_MZ7LM1T9HCJM-00003_S1YKNXAGB17162 \
         ata-SAMSUNG_MZ7LM1T9HCJM-00003_S1YKNXAGB18219 \
         ata-SAMSUNG_MZ7LM1T9HCJM-00003_S1YKNXAH104813 \
  raidz1 ata-SAMSUNG_MZ7LM1T9HCJM-00003_S1YKNXAH200325 \
         ata-SAMSUNG_MZ7LM1T9HCJM-00003_S1YKNXAGB16928 \
         ata-SAMSUNG_MZ7LM1T9HCJM-00003_S1YKNXAH103505 \
         ata-SAMSUNG_MZ7LM1T9HCJM-00003_S1YKNXAGB19101 \
  log nvme-eui.5cd2e4abc3560100 nvme-eui.5cd2e440c3560100
```

When Linux systems boot, the `/dev/*` devices are often assigned arbitrary names such as `sda`, `sdb`, and so on. These names are _not consisent_ between reboots, and using them to define a ZFS cluster may result in odd behavior. Just use the drive IDs, as these are reliable labels that will persist between reboots, and even swapping between systems.

Then set some standard ZFS options on the base pool:

```bash
zfs set compression=lz4 tank
zfs set atime=off tank
```

This will set default compression for every 128k block to lz4, a very fast and storage efficient compression method. This will get the most out of available storage, and you'll probably find stored files greatly exceed the listed capacity of the storage pool. We also turn off `atime` because we don't want to write to the disk metadata every time a file is read; that's dumb.

Next, create the following ZFS volumes:

```bash
zfs create tank/pool
zfs create tank/db_pool
zfs set recordsize=8k tank/db_pool
```

These volumes will inherit any parameters we defined for the base pool, so they're mostly set properly. The only exception is the `db_pool` allocation. Postgres and other databases are likely to use 8kb blocks as the underlying block size, and will write 8kb blocks frequently. 

While a default recordsize of 128kb would get us better storage compression, each 8kb block will result in a 128kb write. This is called Write Amplification, and will dramatically reduce database write throughput. We recommend reserving this pool for database VMs.

## NGINX Dashboard Proxy

The Proxmox dashboard is usually only available via the server's IP address (or assigned DNS hostname) at port 8006. This is... very strange. As a hypervisor, Proxmox assigns IP addresses to any VMs or LXC containers it hosts, meaning the host IP should be able to use any available port.

Thankfully Proxmox provides instructions on [using NGINX as a dashboard proxy](https://pve.proxmox.com/wiki/Web_Interface_Via_Nginx_Proxy). 

Essential steps include installing NGINX itself:

```bash
apt-get -y install nginx
```

Remove the default configuration

```bash
rm /etc/nginx/sites-enabled/default
```

Then creating the Proxmox config:

```bash
cat > /etc/nginx/conf.d/proxmox.conf << EOF
upstream proxmox {
    server "keystone.bonelab.top";
}
 
server {
    listen 80 default_server;
    rewrite ^(.*) https://$host$1 permanent;
}
 
server {
    listen 443 ssl;
    server_name _;
    ssl_certificate /etc/pve/local/pve-ssl.pem;
    ssl_certificate_key /etc/pve/local/pve-ssl.key;
    proxy_redirect off;
    location / {
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade"; 
        proxy_pass https://localhost:8006;
	proxy_buffering off;
	client_max_body_size 0;
	proxy_connect_timeout  3600s;
        proxy_read_timeout  3600s;
        proxy_send_timeout  3600s;
        send_timeout  3600s;
    }
}
EOF
```

And finally, restart NGINX:

```bash
systemctl restart nginx
```

It's also a good idea to use `systemctl edit nginx` and paste the following:

```ini
[Unit]
Requires=pve-cluster.service
After=pve-cluster.service
```

This will ensure nginx starts _after_ the Proxmox server. Apparently the SSL certs are dynamic, and it could cause NGINX to fail to start as our proxy following a reboot.

## System Stats

While the `sysstat` package is installed on Proxmox systems, it is not configured to collect system data. The following steps should enable it:

```bash
systemctl enable sysstat
systemctl start sysstat
```

Next is optional, but recommended. The default sysstat timer only collects system statistics every ten minutes, which may not be enough granularity. So use the following command:

```bash
systemctl edit sysstat-collect.timer
```

And paste the following:

```ini
[Unit]
Description=Run system activity accounting tool every minute

[Timer]
OnCalendar=
OnCalendar=*:00/1:00
AccuracySec=1s
```

Now sysstat will collect various statistics every minute. It will then be possible to use sar to view CPU, RAM, DISK, and other important diagnostics at a 1-minute granularity.


# TODO

Many of these post-installation steps should be converted to an Ansible playbook or role for easier deployment.
