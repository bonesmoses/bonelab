# Install K0s Kubernetes Platform

By far the easiest way to install K0s is using the associated `k0sctl` utility. The [k0sctl](https://docs.k0sproject.io/head/k0sctl-install/) documentation is a good starting point. 

This is simple to install if you're already using `go`:

```bash
go install github.com/k0sproject/k0sctl@latest
```

## Install HAProxy

Before deploying our K0s cluster, we need to finish setting up our HAProxy VM. Once we can access the HAProxy VM, installation and configuration should be easy.

First install the `haproxy` system package:

```bash
sudo apt-get install haproxy
```

Then we add this to the existing `haproxy.cfg` configuration file in `/etc/haproxy`:

```ini
listen kubernetes
    bind :6443
    bind :8132
    bind :9443

    mode tcp

    option tcplog
    option tcp-check
    tcp-check connect port 6443

    server k0s-controller1 10.0.5.1 check check-ssl verify none
    server k0s-controller2 10.0.5.2 check check-ssl verify none
    server k0s-controller3 10.0.5.3 check check-ssl verify none
```

The example provided by the K0s documentation is overly complicated for no reason.  We just need to listen on the three main ports used by the K0s control plane, and forward connections to online control plane nodes.

Next, enable and restart HAProxy with `systemctl`:

```bash
sudo systemctl enable haproxy
sudo systemctl restart haproxy
```

## Install K0s into Cluster

We already know what our cluster should resemble, so create a file named `k0sctl.yaml` with these contents, which rely heavily on many cluster defaults:

```yaml
apiVersion: k0sctl.k0sproject.io/v1beta1
kind: Cluster
metadata:
  name: k0s-cluster
spec:
  hosts:
  - ssh:
      address: 10.0.5.1
      user: bones
    role: controller
  - ssh:
      address: 10.0.5.2
      user: bones
    role: controller
  - ssh:
      address: 10.0.5.3
      user: bones
    role: controller
  - ssh:
      address: 10.0.5.4
      user: bones
    role: worker
  - ssh:
      address: 10.0.5.5
      user: bones
    role: worker
  - ssh:
      address: 10.0.5.6
      user: bones
    role: worker
  k0s:
    versionChannel: stable
    config:
      spec:
        api:
          externalAddress: 10.0.5.10
          sans:
          - 10.0.5.10
```

This will deploy our actual cluster, and note the part at the end where we denote the `externalAddress` and specify a `sans` section. The external IP address should be our HAProxy load balancer, and the `sans` specify any IP address serving cluster certificates. Since HAProxy represents all nodes in the control plane, we only need to list that address.

Then to install the cluster itself:

```bash
k0sctl apply
```

Once the installation process completes, it will give further instructions for obtaining the cluster configuration. We can take advantage of that to configure `kubectl`:

```bash
mkdir -m 0700 ~/.kube
k0sctl kubeconfig > ~/.kube/config
chmod 600 ~/.kube/config
```

We can check our cluster to verify it with `kubectl` once the config is installed:

```bash
kubectl get nodes

NAME           STATUS   ROLES    AGE     VERSION
kubernetes-4   Ready    <none>   9m48s   v1.29.2+k0s
kubernetes-5   Ready    <none>   9m48s   v1.29.2+k0s
kubernetes-6   Ready    <none>   9m48s   v1.29.2+k0s
```

Perfect!

## Next Steps

Continue with [Required Kubernetes Resources](install-apps.md) to complete the cluster.
