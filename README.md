# WordPress on Kubernetes

A Helm chart that runs WordPress with its own MySQL database on Kubernetes. It is a reference setup: small, readable and easy to change.

It replaces an older set of plain manifests that used WordPress 4.8, MySQL 5.6 and Kubernetes API versions that no longer exist. The chart uses current versions and adds the parts those manifests lacked: a dedicated database user, health probes, an optional Ingress, a NetworkPolicy and a pipeline.

## What the chart creates

| Object | Purpose |
| --- | --- |
| Deployment `wordpress` | One WordPress pod (Apache and PHP), strategy `Recreate`, with a volume for the WordPress files |
| Service `wordpress` | ClusterIP Service on port 80 in front of the WordPress pod |
| PersistentVolumeClaim `wordpress-data` | Volume for the WordPress files (`/var/www/html`), kept when the release is removed |
| StatefulSet `wordpress-mysql` | One MySQL 8.4 pod with its own volume claim |
| Service `wordpress-mysql` | Headless Service with the stable DNS name of the database |
| NetworkPolicy `wordpress-mysql` | Only the WordPress pods can reach the database on port 3306 |
| Ingress | Optional, off by default |
| Helm test pod | Requests the WordPress login page, which needs the database to answer |

The object names above are the ones for a release called `wordpress`. Other release names give other prefixes.

## Prerequisites

- A Kubernetes cluster with a default StorageClass
- `kubectl` and Helm 3 or later
- For the local cluster workflow in the Makefile: `kind` and `openssl`

## Install

The chart never creates the database passwords. Create a Secret with two keys first. This keeps the passwords out of the chart values and out of the Helm release history.

```bash
kubectl create namespace wordpress

kubectl --namespace wordpress create secret generic wordpress-db \
  --from-literal=mysql-root-password='<root-password>' \
  --from-literal=mysql-password='<wordpress-user-password>'
```

Then install the chart and run its test:

```bash
helm install wordpress charts/wordpress --namespace wordpress --wait --timeout 10m
helm test wordpress --namespace wordpress
```

Open the site with a port forward, then follow the WordPress setup page:

```bash
kubectl --namespace wordpress port-forward svc/wordpress 8080:80
```

The site is now on http://localhost:8080.

### On a local kind cluster

The Makefile runs the same steps on a kind cluster called `wordpress` and creates the Secret with random passwords. Every command is pinned to the context `kind-wordpress`, so another current kubectl context never receives the install.

```bash
make install        # create the cluster, the Secret and the release
make test           # run the Helm test
make port-forward   # open http://localhost:8080
make down           # delete the cluster
```

`make help` lists all targets.

### From the registry

When a version tag such as `v0.1.0` is pushed, the pipeline publishes the chart to GitHub Container Registry as an OCI artifact:

```bash
helm install wordpress oci://ghcr.io/ahmedbadawy4/charts/wordpress --version 0.1.0 --namespace wordpress
```

## Configuration

The full list with comments is in [charts/wordpress/values.yaml](charts/wordpress/values.yaml). The values most often changed:

| Value | Default | Description |
| --- | --- | --- |
| `auth.existingSecret` | `wordpress-db` | Secret with the database passwords |
| `auth.rootPasswordKey` | `mysql-root-password` | Key in the Secret for the MySQL root password |
| `auth.passwordKey` | `mysql-password` | Key in the Secret for the WordPress database user |
| `database.name` | `wordpress` | Database that MySQL creates |
| `database.user` | `wordpress` | User that WordPress connects as |
| `wordpress.image.tag` | `7.1.5-php8.4-apache` | WordPress image tag |
| `wordpress.replicaCount` | `1` | Needs a ReadWriteMany volume when above 1 |
| `wordpress.persistence.size` | `10Gi` | Size of the WordPress files volume |
| `wordpress.persistence.existingClaim` | `""` | Use a claim that already exists |
| `wordpress.persistence.keepOnUninstall` | `true` | Keep the claim when the release is removed |
| `wordpress.extraEnv` | `[]` | Extra environment variables, for example `WORDPRESS_CONFIG_EXTRA` |
| `mysql.image.tag` | `8.4.13` | MySQL image tag |
| `mysql.persistence.size` | `10Gi` | Size of the database volume |
| `service.type` | `ClusterIP` | Service type for WordPress |
| `ingress.enabled` | `false` | Create an Ingress |
| `networkPolicy.enabled` | `true` | Create the NetworkPolicy for the database |

Both persistence settings can be turned off with `enabled=false`. The pods then use an `emptyDir` volume and lose their data when they restart.

### Ingress with TLS

[examples/values-ingress.yaml](examples/values-ingress.yaml) publishes the site on a host name with TLS. It expects ingress-nginx and a cert-manager ClusterIssuer called `letsencrypt`. Change the class name, annotations and host to match the cluster.

```bash
helm upgrade --install wordpress charts/wordpress \
  --namespace wordpress -f examples/values-ingress.yaml
```

## Upgrade and uninstall

Change the image tags or other values and run `helm upgrade` with the same release name and namespace. The `Recreate` strategy stops the old WordPress pod before the new one starts, because the volume can be attached to one node at a time.

`helm uninstall wordpress --namespace wordpress` removes the release but keeps both volume claims, so the site and the database survive a reinstall. To delete the data as well:

```bash
kubectl --namespace wordpress delete pvc --selector app.kubernetes.io/instance=wordpress
```

## Pipeline

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) has three jobs:

1. **chart** runs `helm lint`, renders the chart with three sets of values (default, the Ingress example, persistence off) and validates the output with kubeconform against the Kubernetes 1.33 schemas.
2. **install** creates a kind cluster, creates the Secret with random passwords, installs the chart and runs `helm test`. If a step fails, it prints the pods, volume claims, events and logs.
3. **publish** runs only for `v*` tags. It checks that the tag matches `version` in `Chart.yaml`, then packages the chart and pushes it to `oci://ghcr.io/<owner>/charts`.

To release, change `version` in `charts/wordpress/Chart.yaml`, commit, and push a tag with the same number:

```bash
git tag v0.1.0
git push origin v0.1.0
```

A new GHCR package is private at first. Change its visibility in the package settings on GitHub to let others pull the chart.

`.pre-commit-config.yaml` runs basic file checks before each commit, including a scan for private keys.

## Repository layout

```text
charts/wordpress/
  Chart.yaml
  values.yaml
  templates/
    wordpress-deployment.yaml
    wordpress-service.yaml
    wordpress-pvc.yaml
    mysql-statefulset.yaml
    mysql-service.yaml
    ingress.yaml
    networkpolicy.yaml
    tests/test-connection.yaml
    NOTES.txt
    _helpers.tpl
examples/values-ingress.yaml
.github/workflows/ci.yml
Makefile
```

## Design limits

- **One WordPress replica.** The WordPress files live on a ReadWriteOnce volume. More replicas need ReadWriteMany storage and a higher `wordpress.replicaCount`.
- **One MySQL instance.** There is no replication and no automatic failover.
- **No backups.** The chart does not schedule backups of the database or the uploads.
- **Database passwords are read once.** MySQL creates the database user on its first start with an empty volume. Changing the Secret later does not change the password inside an existing database.
- **No TLS inside the cluster.** Traffic between the Ingress, WordPress and MySQL is plain. TLS ends at the Ingress.
- **NetworkPolicy needs support from the cluster.** The policy has an effect only when the network plugin enforces NetworkPolicy objects.

## License

Apache License 2.0, see [LICENSE](LICENSE).
