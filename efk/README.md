# Logging, Built Ford Tough

## Architecture

In order to separate logging concerns and access by the various app dev teams, each team get it's own namespace with a dedicated Elasticsearch cluster and Kibana dashboard. Additionally, all logs from kube-system, tectonic-system, and any other logs not for a specific app dev team are collected in the es-cluster in logging namespace.  A single Fluentd daemonset ships logs to the various es-clusters in the different namespaces.

Advantages:
* Each team "pays" for their own logging in a billing and chargeback sense
* There is no single point of failure for _all_ logging
* Each team can scale their ES cluster to handle their own logging volume if they configure logs to be extremely verbose without it affecting any other team.
* Requires no intelligence in Kibana to select only specific logs and block others

Disadvantages:
* Overhead of multiple Elasticsearch clusters

Access to Kibana dashboards is routed through tectonic-ingress-controller and tectonic-identity is leveraged for auth.  In this diagram there is just one app dev team using the appteam namespace.  This would be repeated for other teams.

```
           ------------------------------------------------------------------------------------------
           | tectonic-system namespace                  | logging namespace     | appteam namespace |
           |                                            |                       |                   |
user       |     --------------                         |                       |                   |
request -------->| tectonic   |                         |  ------------------   |                   |
           |     | ingress    |                         |  | fluentd        |   |                   |
           |     | controller |                         |  | daemonset      |-------                |
           |     |            |-------\                 |  |                |   |   \               |
           |     --------------       |                 |  ------------------   |   |               |
           |        |                 |                 |      |                |   |               |
           |        |                 |                 |      |                |   |               |
           |  ------------------   ---------------      |      |kube-system     |   |appteam        |
           |  | logging-system |   | appteam     |      |      |tectonic-system |   |log stream     |
           |  | auth-proxy     |   | auth-proxy  |      |      |systemd         |   |               |
           |  |                |   |             |      |      |log stream      |   |               |
           |  ------------------   ---------------      |      |                |   |               |
           |       |         |      |       |           |      |                |   |               |
           |       |         |      |       |           |      |                |    \              |
           |       |      -------------     |           |      |                |     \             |
           |       |      | tectonic  |     |           |      |                |      |            |
           |       |      | identity  |     |           |      |                |      |            |
           |       |      |           |     |           |      |                |      |            |
           |       |      -------------     |           |      |                |      |            |
           |       |                        |           |      |                |      |            |
           |       |                    ------------    |      |                |      |            |
           |       |                    | appteam  |    |      |                |   --------------  |
           |       |                    | kibana   |------------------------------->| appteam    |  |
           |       |                    |          |    |      |                |   | es-cluster |  |
           |       |                    ------------    |      |                |   |            |  |
           |    -------------------                     |      |                |   --------------  |
           |    | logging-system  |                     |   ------------------  |                   |
           |    | kibana          |------------------------>| logging-system |  |                   |
           |    |                 |                     |   | es-cluster     |  |                   |
           |    -------------------                     |   |                |  |                   |
           |                                            |   ------------------  |                   |
           ------------------------------------------------------------------------------------------

```

## Installation

### Prerequisites
* Storage class:  This implementation assumes the SC name is "standard".  Edit `elasticsearch/es-data-stateful.yaml` to reflect a different SC name if needed.

### Env vars

Set the following env vars when adding namespace logging *and* when installing system logging.

* `K8S_CLUSTER_DOMAIN`: Domain name - including subdomains - used for cluster, e.g. tectonic.dev.k8s.ford.com

### Namespace

All components of this logging system are contained within their own namespace. This provides isolation to ensure that other services running on the cluster have no interaction with the Elasticsearch services.

```
$ kubectl apply -f config/namespace.yaml
```

### TLS Assets

Generate the TLS assets to be used by your EFK stack.  Pass the name of the ES cluster to the shell script.  For system logging, use `es-logging` for the cluster name.  It will create a `tls` directory and deposit assets there.  It will also create the necessary secrets in the logging namespace.

```
$ ./deploy_tls.sh es-logging
```

### ES Client Passwords

Add password secrets for ES Clients.

```
$ ./set_client_pwd.sh admin [admin password] logging
$ ./set_client_pwd.sh fluentd [fluentd password] logging
$ ./set_client_pwd.sh kibana [kibana password] logging && ./set_client_pwd.sh kibana [kibana password] tectonic-system
```

### Dynamic Manifests

Generate manifests with environment-dependent content.

```
$ ./build_logging_manifests.sh
```

### Pod Security Policy

Create pod security policies and related RBAC if using PSPs by default in the cluster.

```
$ kubectl apply -f psp/
```

### Elasticsearch Configuration

This config has worked in relatively low-volume traffic environments.  If you see OOM errors due to JVM heap sizes, adjust the `java_opts` on the appropriate nodes and adjust the resource reqests on the deployment/stateful set manifest.

As a rule of thumb, set the heap size to half of the memory request on the pod specs.
https://www.elastic.co/guide/en/elasticsearch/reference/master/heap-size.html

```
$ kubectl apply -f config/cluster-config.yaml
```

### Search Guard Configuration

If you need to customize Search Guard config, including additional users, roles, etc., edit the files in `config/searchguard/` before creating the configmap.

```
$ kubectl create configmap searchguard-config -n logging --from-file config/searchguard/
```

### Cluster Access Control

By default, pods within a namespace can not see or operate on any resources in other namespaces (including default) so a `ClusterRoleBinding` is provided to allow Fluentd to access the logs output by all pods. The following specs create a `ServiceAccount` for Fluentd and grant the appropriate read permissions on all pods in the cluster.

```
$ kubectl apply -f rbac/
```

### Elasticsearch Docker Images

The elasticsearch nodes are using images built using popular open-source images with Search Guard added.

Image build contexts:

* https://github.com/lander2k2/docker-elasticsearch-pires/tree/v5.5.0
* https://github.com/lander2k2/docker-elasticsearch-kubernetes/tree/v5.5.0

The former serves as a base image for the latter.

Elasticsearch version 5.5.0 is being used.  The following versions were unworkable because:

* 6.0.1 - has no corresponding Search Guard version
* 6.0.0 - Search Guard is in beta, OSS Kibana fails with auth errors
* 5.6.4 - No x-pack-less Kibana image available

I concluded that it was of little value to build an x-pack-less Kibana image for 5.6.4.  As of version 6.0.0, Elastic is releasing OSS Kibana images without x-pack.  When Search Guard releases a 6.0.1 version, it will make sense to upgrade.

### Elasticsearch Data Nodes

Data nodes only handle persistence, search and aggregation of documents. These provision a 12Gi `PersistentVolume` but that can be configured at the bottom of the following manifest.

```
$ kubectl apply -f elasticsearch/es-data-stateful.yaml
```

The Elasticsearch data `Service` exposes a mechanism for all of the data nodes to be referenced by other cluster members. Communication between ES nodes is on port 9300/tcp and only exposed to other pods in the logging namespace.

```
$ kubectl apply -f elasticsearch/es-data-svc.yaml
```

### Elasticsearch Master Nodes

Master nodes are responsible for index creation, tracking cluster members and coordinating shard distribution across data nodes.

```
$ kubectl apply -f elasticsearch/es-cluster-master.yaml
```

The cluster discovery service is for cluster internal communication only; it enables client and data nodes to discover the cluster by exposing port 9300/tcp to other pods in the logging namespace.

```
$ kubectl apply -f elasticsearch/es-cluster-discovery-svc.yaml
```

### Elasticsearch Clients

Elasticsearch client nodes in this deployment are responsible for ingestion of documents and coordinating searches across data nodes. 

```
$ kubectl apply -f elasticsearch/es-cluster-client.yaml
```

The client service enables access to the data in Elasticsearch over its HTTP interface on port 9200/tcp. This interface is used for both ingestion of log messages from Fluentd and retrieval through Kibana.

```
$ kubectl apply -f elasticsearch/es-cluster-svc.yaml
```

### Initialize Search Guard

Search Guard stores client roles and credentials in Elasticsearch.  This will populate the necessary configuration.  Note: this initialization can only be run on data nodes.  The admin creds and SG config are not mounted on the other nodes.

```
$ kubectl exec -n logging es-data-0 -- /bin/bash /elasticsearch/config/searchguard/initialize_sg.sh
```

Test admin access to the ES cluster.  Ensure you see `"status" : "green"` in the response from Elasticsearch.

```
$ kubectl create -f https://raw.githubusercontent.com/lander2k2/crashcart/master/crashcard-po.yaml
$ kubectl exec crashcart -- curl -k 'https://admin:[admin password]@elasticsearch.logging.svc.cluster.local:9200/_cluster/health?pretty'
$ kubectl delete po crashcart
```

### Fluentd

Fluentd is used to collect logs from each host and forward them onto a storage medium. In the default deployment, Elasticsearch is used and each host submits its documents directly to the Elasticsearch cluster. 

Fluentd needs to be able to list pods and namespaces in order to identify pods and properly correlate the log messages written to disk. The following manifests create a ServiceAccount, Role and RoleBinding to be used by the FluentD DaemonSet below.

This implementation does not use a flutend aggregator, but the manfifests exist here.  Just uncomment the env var in the fluentd daemonset manifest and deploy the aggregator deployment and service.

```
$ kubectl apply -f fluentd/fluentd-role-binding.yaml
$ kubectl apply -f fluentd/fluentd-role.yaml
$ kubectl apply -f fluentd/fluentd-service-account.yaml
```

The configmap manifest configures Fluentd to tail all logs from `/var/log` and `/var/lib/docker/containers`. It also has filters to handle common Kubernetes log formats. The existing contents of all logs in these directories will be sent when Fluentd initially starts; this may cause a large quantity of logs to be indexed leading to a temporary state of high load on the Elasticsearch node.

```
$ kubectl apply -f fluentd/fluentd-configmap.yaml
```

In Kubernetes, DaemonSets are used to schedule a pod on a set of hosts. This manifest does not contain a `nodeSelector` in its spec so the pod is scheduled on each node in the cluster. To include more log directories from the hosts, add to the `volume` and `volumeMounts` in the manifest.

```
$ kubectl apply -f fluentd/fluentd-ds.yaml
```

The Fluentd Service exposes metrics endpoints for consumption by Prometheus.

```
$ kubectl apply -f fluentd/fluentd-svc.yaml
```

### Kibana

Add `'https://$K8S_CLUSTER_DOMAIN/logging-system/auth/callback'` to the redirectURIs in the tectonic-identity configmap.  You can do this in the Tectonic console.  Then restart the tectonic-identity pods.

```
$ kubectl apply -f auth/
$ kubectl apply -f kibana/
```

Browse to $K8S_CLUSTER_DOMAIN/logging-system/ and log into tectonic if necessary.  When you hit Kibana, if your browser prompts you for a username and password, use username: kibana and the password you used when adding client passwords to Elasticsearch earlier.

### Prometheus

Prometheus is included to collect and store metrics about the state of the Elasticsearch cluster and Fluentd instances. 

Prometheus requires access to the objects created by this architecture in order to automatically collect metrics from Fluentd and Elasticsearch. The following manifest creates a ServiceAccount, ClusterRole and ClusterRoleBinding to allow the pods to list, watch and get Pods, Services and Endpoints in the `logging` namespace.

```
$ kubectl apply -f prometheus/prometheus-rbac.yaml
```


Using the operator included in Tectonic a Prometheus instance can easily be provisioned to collect and store metrics. This manifest creates an instance that watches for `es-exporter` ServiceMonitors in the `logging` namespace.

```
$ kubectl apply -f prometheus/prometheus-instance.yaml
```

`es-exporter` is a simple Prometheus exporter to make Elasticsearch metrics available to Prometheus collectors. This manifest deploys one replica of the service which is able to collect cluster-level metrics using the previously created elasticsearch Service.

```
$ kubectl apply -f prometheus/prometheus-es-exporter.yaml
```

This ServiceMonitor enables Prometheus to automatically discover Elasticsearch pods and collect metrics from them.

```
$ kubectl apply -f prometheus/prometheus-servicemon.yaml
```

### Data Management and Pruning

Depending on the retention requirements of your organization and the capacity of your cluster you may need to prune Elasticsearch indexes. Elastic has a project called [Curator](https://www.elastic.co/guide/en/elasticsearch/client/curator/current/index.html) which can remove old indexes based on a defined set of criteria, the most common is by date. The provided curator manifest will run once a day to remove anything older than three days.

```
$ kubectl apply -f curator/es-curator-config.yaml
```

```
$ kubectl apply -f curator/es-curator.yaml
```

This feature relies on the CronJob object which is an alpha feature in Kubernetes 1.7. It has been promoted to beta in Kubernetes 1.8 but can be enabled in 1.7 if desired.

## Namespace Logging

Each namespace gets it's own logging mechanisms to separate resource concerns and segregate access. The fluentd daemonset is the only shared component and it's configmap must be updated when new namespaces are deployed.  However, each namespace gets it's own elasticsearch cluster and dashboard.

### Deploy logging system.

```
$ ./add_ns.sh [namespace]
$ kubectl apply -f [namespace]/config/
$ kubectl apply -f [namespace]/psp/
$ kubectl apply -f [namespace]/elasticsearch/
$ kubectl apply -f [namespace]/auth/
$ kubectl apply -f [namespace]/kibana/
```
### Update tectonic-identity configmap

Follow instructions provided by `add_ns.sh` output by editing the existing configmap for tectonic-identity in your cluster.

### Update fluentd

The `add_ns.sh` script will output a fluentd config to add to `logging/fluentd-config`.  Be sure to add new configurations to the *beginning* of the `output.conf` file.

