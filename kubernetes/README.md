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
