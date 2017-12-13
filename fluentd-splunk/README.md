# Logging with Fluentd to Splunk

This provides several items to use to set up a Fluentd DaemonSet in Kubernetes
that talks to Splunk. There are two directories here:

###Docker-Image

This directory contains what you need to create a container for the DaemonSet
to use.

```
$ cd docker-image
$ docker login quay.io # login to quay
$ docker build -t quay.io/namespace/containername:tag . #build the container
$ docker push quay.io/namespace/containername:tag # push image to quay
```

The container image uses the following Fluentd plugins:

* [fluent-plugin-record-reformer][0]
* [fluent-plugin-kubernetes_metadata_filter][1]
* [fluent-plugin-splunk-http-eventcollector][2]
* [fluent-plugin-systemd][3]

###Kubernetes-Config

This directory contains files required to deploy this to Kubernetes, based
on our official documentation [here][4]. Includes:

* Fluentd Auth file containing:
  * Fluentd service account
  * Fluentd cluster role
  * Fluentd cluster role binding
* A ConfigMap that contains your Fluentd/Splunk configuration.
* The DaemonSet to deploy Fluentd pods.

The DaemonSet example will need to be updated with:

* Your image built using the docker steps above.
* Your image pull secret in the `logging` namespace.

The ConfigMap example will need to be updated with your Splunk server information.

[0]: https://github.com/sonots/fluent-plugin-record-reformer
[1]: https://github.com/fabric8io/fluent-plugin-kubernetes_metadata_filter
[2]: https://github.com/brycied00d/fluent-plugin-splunk-http-eventcollector
[3]: https://github.com/reevoo/fluent-plugin-systemd
[4]: https://coreos.com/tectonic/docs/latest/admin/logging-customization.html