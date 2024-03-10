# Install a CloudNativePG Cluster

[CloudNativePG ](https://cloudnative-pg.io/) is one of the more advanced Postgres Kubernetes operators available. Unlike all of the others, it does _not_ rely on Patroni for managing failover, quorum, and other cluster operations. Instead, it leverages Kubernetes functionality, allowing it to also include features like filesystem snapshots.

Here is a quick series of steps to install a CloudNativePG cluster in our new Kubernetes environment.

## Install CloudNative PG

Begin by installing the operator itself. Again, we'll leverage Helm rather than using the "official" documentation suggestion of `kubectl apply`.

```bash
helm repo add cloudnative-pg https://cloudnative-pg.github.io/charts
helm repo update
helm upgrade --install cnpg cloudnative-pg/cloudnative-pg \
  --namespace cnpg-system --create-namespace
```

## Create a Test Cluster

Next we just need to define a simple test cluster. Use a configuration like this, named `test-cnpg-cluster.yaml`:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: test-cnpg-cluster
  namespace: cloudnative-pg
spec:
  instances: 3

  bootstrap:
    initdb:
      database: bones
      owner: bones

  postgresql:
    parameters:
      random_page_cost: "1.1"
      log_statement: "ddl"
      log_checkpoints: "on"

  storage:
    size: 10Gi
```

Then we can deploy it with:

```bash
kubectl create namespace cloudnative-pg
kubectl apply -f test-cnpg-cluster.yaml
```

Watch the deployment process with:

```bash
kubectl -n cloudnative-pg get pods -w
```

Once the initialization, join, and other steps complete, it should be safe to use the cluster.

## Expose Postgres Cluster

Once the cluster is running, we can already use it with [other kubernetes applications](https://cloudnative-pg.io/documentation/1.22/applications/). But for at least development purposes, having direct access might be easier. So let's use our load balancer to associate it with an IP address:

```
kubectl expose svc test-cnpg-cluster-rw --name=test-cnpg-bones-rw \
  --port=5432 --type=LoadBalancer -n cloudnative-pg
```

This will bind the `test-cnpg-cluster-rw` service which always points to the Primary pod with an IP address. In the event of a failover, this endpoint should always point to the active Primary once the failover is complete.

To see the assigned IP address, we just need to view the associated service kubernetes created:

```bash
kubectl get svc -n cloudnative-pg test-cnpg-bones-rw

NAME                   TYPE           CLUSTER-IP       EXTERNAL-IP   PORT(S)          AGE
test-cnpg-bones-rw     LoadBalancer   10.106.236.202   10.0.5.100    5432:30494/TCP   55m
```

## Retrieve Cluster User Auth

When a cluster is created, CloudNativePG generates a password for any user that owns databases we define. Using the above configuration, we should be able to retrieve and decode the password with the following command:

```bash
export PGPASSWORD=$(
  kubectl get secret -n cloudnative-pg test-cnpg-cluster-app \
    -o jsonpath="{.data.password}" | base64 -d
)
```

This will set the `PGPASSWORD` environment variable read by `libpq`, which is used by nearly all Postgres-compatible client software. We can then test this using the standard `psql` tool:

```bash
psql -h 10.0.5.100

psql (16.2 (Ubuntu 16.2-1.pgdg22.04+1))
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, compression: off)
Type "help" for help.

bones=> 
```
