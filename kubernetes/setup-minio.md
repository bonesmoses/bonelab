# Install and Setup MinIO Storage

The [MinIO](https://github.com/minio/minio) storage layer is a distributed object-store that makes it possible to host S3 volumes on a Kubernetes cluster. This makes it a perfect candidate for several projects which utilize S3 in some manner. 

Use the following instructions to install the service and related drivers.

## Install MinIO

Use the following `helm` commands to install the MinIO operator. There will be no corresponding storage at this stage.

```bash
helm repo add minio-operator https://operator.min.io
helm repo update
helm install --namespace minio-operator --create-namespace \
  operator minio-operator/operator
```

## Add MinIO Storage

If you followed the Kubernetes installation guide, the `krew` plugin manager should also be installed. It will be used for many of the following steps to configure and manage MinIO.

Start by installing the `minio` plugin for Kubectl:

```bash
kubectl krew update
kubectl krew install minio
```

Next, we'll need to add the [DirectPV](https://github.com/minio/directpv) driver so MinIO can manage attached volumes. Any volumes used this way will be fully managed by MinIO, and should not be formatted or used by any other process on the Kubernetes host. If you followed the guide and have a fully operational K0s cluster, you should also add a separate SCSI device to each Kubernetes worker VM for MinIO's exclusive use.

When the drives are attached and ready, hand them over to MinIO:

```bash
export KUBELET_DIR_PATH=/var/lib/k0s/kubelet

kubectl krew install directpv
kubectl directpv install --node-selector directpv=yes
kubectl directpv init drives.yaml --dangerous
```

> [!NOTE]
> The `KUBELET_DIR_PATH` export is necessary because K0s uses a non-standard kubelet path. Normally this is `/var/lib/kubelet`. Failure to export this variable will result in DirectPV failing to operate normally. This should only be necessary during DirectPV installation.

Once the devices are installed, examine them for posterity. Ours looked like this:

```bash
kubectl directpv list drives

┌──────────────┬──────┬─────────────────────────────┬──────────┬──────────┬─────────┬────────┐
│ NODE         │ NAME │ MAKE                        │ SIZE     │ FREE     │ VOLUMES │ STATUS │
├──────────────┼──────┼─────────────────────────────┼──────────┼──────────┼─────────┼────────┤
│ kubernetes-4 │ sdb1 │ QEMU QEMU_HARDDISK (Part 1) │ 1024 GiB │ 1024 GiB │ 0       │ Ready  │
│ kubernetes-5 │ sdb1 │ QEMU QEMU_HARDDISK (Part 1) │ 1024 GiB │ 1024 GiB │ 0       │ Ready  │
│ kubernetes-6 │ sdb1 │ QEMU QEMU_HARDDISK (Part 1) │ 1024 GiB │ 1024 GiB │ 0       │ Ready  │
└──────────────┴──────┴─────────────────────────────┴──────────┴──────────┴─────────┴────────┘
```

## Using MinIO Volumes

In order to use MinIO volumes, it's necessary to know the name of the underlying storage class. This _should_ be `directpv-min-io`, but should be verified:

```bash
kubectl get storageclass --server-print=false

NAME               AGE
directpv-min-io    6d16h
openebs-device     13d
openebs-hostpath   13d
```

Any physical volume (PV) or volume claim (PVC) definition should use `directpv-min-io` as the `storageClass` to allocate MinIO storage volumes.

## Access the MinIO Admin Console

In order to allocate S3 credentials and volume names to the storage, it may be necessary to access the administration console. The easiest way to do this is to expose the MinIO console service using a LoadBalancer, and then viewing the secret token necessary to log into the interface.

Use this command to expose the service with a dedicated IP on port 80:

```bash
kubectl expose svc console --name=minio-console-ip --port=80 \
  --target-port=9090 --type=LoadBalancer -n minio-operator
```

Then use this to obtain the secret token:

```bash
kubectl get secret/console-sa-secret -n minio-operator \
  -o jsonpath="{.data.token}" | base64 -d
```

Direct a browser to the IP address associated with the `minio-console-ip` service and paste the entire token into the text box where it says "Enter JWT".

Subsequent steps for managing tenants, S3 volumes, credentials, and other details should be derived from the [MinIO tenant documentation](https://min.io/docs/minio/kubernetes/upstream/operations/deploy-manage-tenants.html).
