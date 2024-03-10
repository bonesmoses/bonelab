# Installing Necessary Kubernetes Resources

The current cluster has no ability to store data, and no method of ingress. This means we can't access any services or other software running in the cluster once we install it. There are plenty of choices for storage or ingress resources, but we've chosen two simple ones that work immediately upon installation.

Feel free to replace these or add further options once you're more familiar with your cluster.

## Install MetalLB

MetalLB is an easy way to expose services and automatically assign IP addresses. It is a load balancer rather than a reverse proxy, but it can work _with_ something like ingress-nginx, Traefik, and so on. That will come in handy later when we want to start adding authentication layers or SSL certificate management.

We installed Helm specifically so we could do this:

```
helm repo add metallb https://metallb.github.io/metallb
helm repo update
helm install metallb metallb/metallb --namespace metallb-system --create-namespace
```

Then the load balancer needs a definition for the IP pool, so create a file named `address-pool.yaml` with these contents:

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - 10.0.5.100-10.0.5.120
```

And install it into the cluster with `kubectl`:

```bash
kubectl apply -f address-pool.yaml
```

Then we need an advertisement that it's an available load balancer for layer 2 networks, so create a file named `l2-advert.yaml` with these contents:

```yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: example
  namespace: metallb-system
spec:
  ipAddressPools:
  - first-pool
```

Assuming everything went well, we should be able to assign IP addresses from 10.0.5.100 to 10.0.5.120 for services operating in our K0s cluster once we've installed a few.

## Install OpenEBS

The last thing we need is a storage layer. K0s itself ships with no storage controller, but used OpenEBS in the past. OpenEBS has great support for local storage, and has a recommended system called Mayastore for more advanced replicating block storage. We only need local storage for now, but keep the advanced features in mind for later.

Start by installing OpenEBS:

```
helm repo add openebs https://openebs.github.io/charts
helm repo update
helm install openebs openebs/openebs --namespace openebs --create-namespace
```

Now if we list available storage classes, we should see `openebs-device` and `openebs-hostpath`:

```
kubectl get storageclass -A
```

To avoid having to always reference these by name, we can mark the `openbs-hostpath` storage as the default for this cluster:

```
kubectl patch storageclass openebs-hostpath \
    -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

From now on, if we don't specify any specific storage type, our cluster will use `openebs-hostpath`.

