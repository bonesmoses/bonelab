#!/bin/bash

#VERSION=v1.27.11+k0s.0 
VERSION=
DEBUG=false

CONTROL=(10.0.5.1 10.0.5.2 10.0.5.3)
WORKER=(10.0.5.4 10.0.5.5 10.0.5.6)

VM_USER=bones

CONTROL_LB=10.0.5.10
LB_RANGE=10.0.5.100-10.0.5.120

################################################################################
#                        No edits below this block                             #
################################################################################

echo
echo "-= BoneLab Kubernetes Installation Tool =-"
echo

LEADER=${CONTROL[0]}

echo "Checking for important software!"
echo

# Begin by installing K0sctl if it's not found. This utility is what does the
# bulk of the work during cluster installation.

echo -n "  - Checking for k0sctl utility ... "

if ! command -v k0sctl; then
  echo -n "Installing ... "
  go install github.com/k0sproject/k0sctl@latest &>> install.log
  echo "Done."
fi

# Next, install kubectl if it's not found. Again, life will be much harder
# without this utility.

echo -n "  - Checking for kubectl utility ... "

if ! command -v kubectl ; then
  echo -n "Installing ... "
  export KCTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
  {
    curl -LO "https://dl.k8s.io/release/$KCTL_VERSION/bin/linux/amd64/kubectl"
    mkdir -p ~/.local/bin
    chmod 0700 kubectl
    mv kubectl ~/.local/bin
  } &>> install.log
  echo "Done."
fi

# Next, install Helm if it's not found. At least a couple subsequent steps use
# helm to install the packaged application, so we need this to proceed.

echo -n "  - Checking for helm utility ... "

if ! command -v helm ; then
  echo -n "Installing ... "
  {
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm get_helm.sh
  } &>> install.log
  echo "Done."
fi

echo
echo "Deploying K0s to Kubernetes VMs!"
echo

# Now we need to generate a k0sctl.yaml template. We can loop through the 
# control plane and worker node lists to produce all of the necessary sections.
# In addition, we'll want to add our load-balancer IP so the cluster starts up
# properly. ONLY DO THIS IF THE CONFIG IS MISSING!

echo -n "  - Checking for k0sctl.yaml configuration file ... "

if [ ! -f k0sctl.yaml ]; then
  echo -n " Generating ... "
  {
    echo "apiVersion: k0sctl.k0sproject.io/v1beta1"
    echo "kind: Cluster"
    echo "metadata:"
    echo "  name: k0s-cluster"
    echo "spec:"
    echo "  hosts:"
  } > k0sctl.yaml

  # Now loop through control nodes and add an SSH entry for each one:

  for node in ${CONTROL[@]}; do
    {
      echo "  - ssh:"
      echo "      address: ${node}"
      echo "      user: ${VM_USER}"
      echo "    role: controller"
    } >> k0sctl.yaml
  done

  # Do the same with the worker nodes so all nodes are accounted for:

  for node in ${WORKER[@]}; do
    {
      echo "  - ssh:"
      echo "      address: ${node}"
      echo "      user: ${VM_USER}"
      echo "    role: worker"
    } >> k0sctl.yaml
  done

  # End the config file with our Load Balancer address definition. Again, the
  # cluster will not operate properly without this!

  {
    echo "  k0s:"
    [[ "${VERSION}" != "" ]] && echo "    version: ${VERSION}"
    echo "    versionChannel: stable"
    echo "    config:"
    echo "      spec:"
    echo "        api:"
    echo "          externalAddress: ${CONTROL_LB}"
    echo "          sans:"
    echo "          - ${CONTROL_LB}"
  } >> k0sctl.yaml
fi

echo "Done."

echo -n "  - Applying configuration file to cluster ... "

k0sctl apply &>> install.log

echo "Done."

echo -n "  - Copying cluster information to kubectl configuration ... "

k0sctl kubeconfig 2> install.log > ~/.kube/config
chmod 600 ~/.kube/config

echo "Done."

echo
echo "Now installing useful Helm repos"
echo

echo -n "  - Checking for MetalLB ... "
repo=$(helm repo list | grep metallb | awk '{print $2}')

if [ -n "${repo}" ]; then
  echo ${repo}
else
  echo -n "Installing ... "
  {
    helm repo add metallb https://metallb.github.io/metallb
    helm repo update
    helm install metallb metallb/metallb --namespace metallb-system --create-namespace
  } &>> install.log
  echo "Done."
fi

echo -n "  - Checking for OpenEBS ... "
repo=$(helm repo list | grep openebs | awk '{print $2}' | grep charts)

if [ -n "${repo}" ]; then
  echo ${repo}
else
  echo -n "  - Installing ... "
  {
    helm repo add openebs https://openebs.github.io/charts
    helm repo update
    helm install openebs openebs/openebs --namespace openebs --create-namespace
  } &>> install.log
  echo "Done."
fi

echo
echo "Now configuring openebs-hostpath storage class"
echo

is_default=$(kubectl get storageclass openebs-hostpath 2>>install.log | grep default)

if [ -n "${is_default}" ]; then
  echo "  - openebs-hostpath is set as the default storage class."
else
  echo -n "  - Setting openebs-hostpath as default storage class ... "
  kubectl patch storageclass openebs-hostpath \
    -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' \
    &>> install.log
  echo "Done."
fi

echo
echo "Now configuring MetalLB"
echo

pool=$(kubectl -n metallb-system get ipaddresspool first-pool 2>>install.log)

if [ -n "${pool}" ]; then
  echo "  - MetalLB is already set to use an IP address pool."
else
  echo -n "  - Setting MetalLB to manage ${LB_RANGE} ... "
  {
    echo "apiVersion: metallb.io/v1beta1"
    echo "kind: IPAddressPool"
    echo "metadata:"
    echo "  name: first-pool"
    echo "  namespace: metallb-system"
    echo "spec:"
    echo "  addresses:"
    echo "  - ${LB_RANGE}"
  } > address-pool.yaml

  kubectl apply -f address-pool.yaml &>>install.log
  echo "Done."
fi

advert=$(kubectl -n metallb-system get L2Advertisement metallb-l2-advert 2>>install.log)

if [ -n "${advert}" ]; then
  echo "  - MetalLB is already set as an L2 Load balancer."
else
  echo -n "  - Setting MetalLB as an L2 Load Balancer ... "
  {
    echo "apiVersion: metallb.io/v1beta1"
    echo "kind: L2Advertisement"
    echo "metadata:"
    echo "  name: metallb-l2-advert"
    echo "  namespace: metallb-system"
    echo "spec:"
    echo "  ipAddressPools:"
    echo "  - first-pool"
  } > l2-advert.yaml

  kubectl apply -f l2-advert.yaml &>>install.log
  echo "Done."
fi

echo
echo "K0s installation and setup complete!"
echo
