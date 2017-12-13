#!/bin/bash

NS=$1

read -r -d '' USAGE << EOM
Generate manifests for namespace logging
./add_ns.sh [--help] <namespace>
EOM

if [ "$#" -ne 1 ]; then
    echo "Error: No namespace provided"
    echo "$USAGE"
    exit 1
elif [ ${NS} = "--help" ]; then
    echo "$USAGE"
    exit 0
fi

mkdir -p ${NS}/config ${NS}/elasticsearch ${NS}/kibana ${NS}/psp ${NS}/auth

cat > ${NS}/config/cluster-config.yaml <<EOL
apiVersion: v1
kind: ConfigMap
metadata:
  name: es-logging-${NS}
  namespace: ${NS}
data:
  cluster.name: "es-logging-${NS}"
  cluster.master_count: "2"
  data_nodes.java_opts: -Xms512m -Xmx512m
  data_nodes.ingest: "false"
  data_nodes.store_data: "true"
  data_nodes.http_enable: "false"
  client_nodes.java_opts: -Xms1024m -Xmx1024m
  client_nodes.ingest: "true"
  client_nodes.store_data: "false"
  client_nodes.http_enable: "true"
  master_nodes.java_opts: -Xms256m -Xmx256m
  master_nodes.ingest: "false"
  master_nodes.store_data: "false"
  master_nodes.http_enable: "false"
EOL

cat > ${NS}/config/namespace.yaml <<EOL
apiVersion: v1
kind: Namespace
metadata:
  name: ${NS}
  labels:
    name: ${NS}
EOL

cat > ${NS}/elasticsearch/es-cluster-client.yaml <<EOL
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: es-client
  namespace: ${NS}
  labels:
    component: elasticsearch
    role: client
spec:
  replicas: 2
  template:
    metadata:
      labels:
        component: elasticsearch
        role: client
    spec:
      initContainers:
      - name: init-sysctl
        image: busybox
        imagePullPolicy: IfNotPresent
        command: ["sysctl", "-w", "vm.max_map_count=262144"]
        securityContext:
          privileged: true
      containers:
      - name: es-client
        securityContext:
          privileged: false
          capabilities:
            add:
              - IPC_LOCK
              - SYS_RESOURCE
        image: quay.io/pires/docker-elasticsearch-kubernetes:5.5.2
        imagePullPolicy: Always
        resources:
          requests:
            memory: "2Gi"
            cpu: "500m"
        env:
        - name: NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: CLUSTER_NAME
          valueFrom:
            configMapKeyRef:
              name: es-logging-${NS}
              key: cluster.name
        - name: NODE_MASTER
          value: "true"
        - name: NODE_INGEST
          valueFrom:
            configMapKeyRef:
              name: es-logging-${NS}
              key: client_nodes.ingest
        - name: NODE_DATA
          valueFrom:
            configMapKeyRef:
              name: es-logging-${NS}
              key: client_nodes.store_data
        - name: HTTP_ENABLE
          valueFrom:
            configMapKeyRef:
              name: es-logging-${NS}
              key: client_nodes.http_enable
        - name: ES_JAVA_OPTS
          valueFrom:
            configMapKeyRef:
              name: es-logging-${NS}
              key: client_nodes.java_opts
        ports:
        - containerPort: 9200
          name: http
          protocol: TCP
        - containerPort: 9300
          name: transport
          protocol: TCP
        volumeMounts:
        - name: storage
          mountPath: /data
      volumes:
          - emptyDir:
              medium: ""
            name: "storage"
EOL

cat > ${NS}/elasticsearch/es-cluster-discovery-svc.yaml <<EOL
apiVersion: v1
kind: Service
metadata:
  name: elasticsearch-discovery
  namespace: ${NS}
  labels:
    component: elasticsearch
    role: master
spec:
  selector:
    component: elasticsearch
    role: master
  ports:
  - name: transport
    port: 9300
    protocol: TCP
EOL

cat > ${NS}/elasticsearch/es-cluster-master.yaml <<EOL
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: es-master
  namespace: ${NS}
  labels:
    component: elasticsearch
    role: master
spec:
  replicas: 3
  template:
    metadata:
      labels:
        component: elasticsearch
        role: master
    spec:
      initContainers:
      - name: init-sysctl
        image: busybox
        imagePullPolicy: IfNotPresent
        command: ["sysctl", "-w", "vm.max_map_count=262144"]
        securityContext:
          privileged: true
      containers:
      - name: es-master
        securityContext:
          privileged: false
          capabilities:
            add:
              - IPC_LOCK
              - SYS_RESOURCE
        image: quay.io/pires/docker-elasticsearch-kubernetes:5.5.2
        imagePullPolicy: Always
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
        env:
        - name: NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: CLUSTER_NAME
          valueFrom:
            configMapKeyRef:
              name: es-logging-${NS}
              key: cluster.name
        - name: NUMBER_OF_MASTERS
          valueFrom:
            configMapKeyRef:
              name: es-logging-${NS}
              key: cluster.master_count
        - name: NODE_MASTER
          value: "true"
        - name: NODE_INGEST
          valueFrom:
            configMapKeyRef:
              name: es-logging-${NS}
              key: master_nodes.ingest
        - name: NODE_DATA
          valueFrom:
            configMapKeyRef:
              name: es-logging-${NS}
              key: master_nodes.store_data
        - name: HTTP_ENABLE
          valueFrom:
            configMapKeyRef:
              name: es-logging-${NS}
              key: master_nodes.http_enable
        - name: ES_JAVA_OPTS
          valueFrom:
            configMapKeyRef:
              name: es-logging-${NS}
              key: master_nodes.java_opts
        ports:
        - containerPort: 9300
          name: transport
          protocol: TCP
        volumeMounts:
        - name: storage
          mountPath: /data
      volumes:
          - emptyDir:
              medium: ""
            name: "storage"
EOL

cat > ${NS}/elasticsearch/es-cluster-svc.yaml <<EOL
apiVersion: v1
kind: Service
metadata:
  name: elasticsearch
  namespace: ${NS}
  labels:
    component: elasticsearch
    role: client
spec:
  selector:
    component: elasticsearch
    role: client
  ports:
  - name: http
    port: 9200
    protocol: TCP
EOL

cat > ${NS}/elasticsearch/es-data-stateful.yaml <<EOL
apiVersion: apps/v1beta1
kind: StatefulSet
metadata:
  name: es-data
  namespace: ${NS}
  labels:
    component: elasticsearch
    role: data
spec:
  serviceName: elasticsearch-data
  replicas: 3
  template:
    metadata:
      labels:
        component: elasticsearch
        role: data
    spec:
      initContainers:
      - name: init-sysctl
        image: busybox
        imagePullPolicy: IfNotPresent
        command: ["sysctl", "-w", "vm.max_map_count=262144"]
        securityContext:
          privileged: true
      containers:
      - name: es-data
        securityContext:
          privileged: true
          capabilities:
            add:
              - IPC_LOCK
        image: quay.io/pires/docker-elasticsearch-kubernetes:5.5.2
        imagePullPolicy: Always
        resources:
          requests:
            memory: "1Gi"
            cpu: "250m"
        env:
        - name: NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: "CLUSTER_NAME"
          valueFrom:
            configMapKeyRef:
              name: es-logging-${NS}
              key: cluster.name
        - name: NODE_MASTER
          value: "false"
        - name: NODE_INGEST
          valueFrom:
            configMapKeyRef:
              name: es-logging-${NS}
              key: data_nodes.ingest
        - name: NODE_DATA
          valueFrom:
            configMapKeyRef:
              name: es-logging-${NS}
              key: data_nodes.store_data
        - name: HTTP_ENABLE
          valueFrom:
            configMapKeyRef:
              name: es-logging-${NS}
              key: data_nodes.http_enable
        - name: NODE_MASTER
          value: "false"
        - name: ES_JAVA_OPTS
          valueFrom:
            configMapKeyRef:
              name: es-logging-${NS}
              key: data_nodes.java_opts
        ports:
        - containerPort: 9300
          name: transport
          protocol: TCP
        volumeMounts:
        - name: storage
          mountPath: /data
  volumeClaimTemplates:
  - metadata:
      name: storage
      annotations:
        volume.beta.kubernetes.io/storage-class: standard
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 12Gi
EOL

cat > ${NS}/elasticsearch/es-data-svc.yaml <<EOL
apiVersion: v1
kind: Service
metadata:
  namespace: ${NS}
  name: elasticsearch-data
  labels:
    component: elasticsearch
    role: data
spec:
  ports:
  - port: 9300
    name: transport
  clusterIP: None
  selector:
    component: elasticsearch
    role: data
EOL

cat > ${NS}/kibana/kibana-svc.yaml <<EOL
apiVersion: v1
kind: Service
metadata:
  name: kibana-${NS}
  namespace: tectonic-system
  labels:
    component: kibana-${NS}
spec:
  selector:
    component: kibana-${NS}
  ports:
  - name: http
    port: 5601
    targetPort: kibana
    protocol: TCP
EOL

cat > ${NS}/kibana/kibana.yaml <<EOL
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: kibana-${NS}
  namespace: tectonic-system
  labels:
    component: kibana-${NS}
spec:
  replicas: 1
  selector:
    matchLabels:
     component: kibana-${NS}
  template:
    metadata:
      labels:
        component: kibana-${NS}
    spec:
      containers:
      - name: kibana
        image: cfontes/kibana-xpack-less:5.5.0
        env:
        - name: CLUSTER_NAME
          value: es-logging-${NS}
        - name: ELASTICSEARCH_URL
          value: http://elasticsearch.${NS}.svc.cluster.local:9200
        - name: SERVER_BASEPATH
          value: /logging-${NS}
        - name: XPACK_SECURITY_ENABLED
          value: 'false'
        - name: XPACK_GRAPH_ENABLED
          value: 'false'
        - name: XPACK_ML_ENABLED
          value: 'false'
        - name: XPACK_REPORTING_ENABLED
          value: 'false'
        resources:
          limits:
            cpu: 1000m
          requests:
            cpu: 100m
        ports:
        - containerPort: 5601
          name: kibana
          protocol: TCP
EOL

cat > ${NS}/psp/logging-psp-rb.yaml <<EOL
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: logging-psp
  namespace: ${NS}
subjects:
- kind: ServiceAccount
  name: replicaset-controller
  namespace: kube-system
- kind: ServiceAccount
  name: daemon-set-controller
  namespace: kube-system
- kind: ServiceAccount
  name: statefulset-controller
  namespace: kube-system
roleRef:
  kind: Role
  name: logging-psp
  apiGroup: rbac.authorization.k8s.io
EOL

cat > ${NS}/psp/logging-psp-role.yaml <<EOL
kind: Role
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: logging-psp
  namespace: ${NS}
rules:
  - apiGroups: ["extensions"]
    resources: ["podsecuritypolicies"]
    resourceNames: ["logging-privileged"]
    verbs: ["use"]
EOL

cat > ${NS}/auth/logging-auth-deploy.yaml <<EOL
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  labels:
    k8s-app: logging-${NS}-auth
  name: logging-${NS}-auth
  namespace: tectonic-system
spec:
  replicas: 1
  selector:
    matchLabels:
      k8s-app: logging-${NS}-auth
  strategy:
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
    type: RollingUpdate
  template:
    metadata:
      labels:
        k8s-app: logging-${NS}-auth
    spec:
      containers:
      - args:
        - -provider=oidc
        - -client-id=\$(CLIENT_ID)
        - -client-secret=\$(CLIENT_SECRET)
        - -cookie-secret=\$(COOKIE_SECRET)
        - -external-url=\$(BASE_URL)/logging-${NS}
        - -proxy-prefix=/auth
        - -pass-host-header=true
        - -pass-user-headers=true
        - -pass-basic-auth=false
        - -cookie-name=_tectonic_monitoring_auth
        - -cookie-domain=${K8S_CLUSTER_DOMAIN}
        - -cookie-expire=8h0m0s
        - -email-domain=*
        - -redirect-url=\$(BASE_URL)/logging-${NS}/auth/callback
        - -oidc-issuer-url=\$(OIDC_ISSUER_URL)
        - -http-address=http://0.0.0.0:4180
        - -upstream=http://kibana-${NS}.tectonic-system.svc.cluster.local:5601
        - -ssl-insecure-skip-verify
        env:
        - name: BASE_URL
          valueFrom:
            configMapKeyRef:
              key: consoleBaseAddress
              name: tectonic-config
        - name: CLIENT_ID
          valueFrom:
            configMapKeyRef:
              key: consoleClientID
              name: tectonic-identity
        - name: CLIENT_SECRET
          valueFrom:
            configMapKeyRef:
              key: consoleSecret
              name: tectonic-identity
        - name: OIDC_ISSUER_URL
          valueFrom:
            configMapKeyRef:
              key: issuer
              name: tectonic-identity
        - name: COOKIE_SECRET
          valueFrom:
            secretKeyRef:
              key: cookie_secret
              name: tectonic-monitoring-auth
        image: quay.io/coreos/tectonic-monitoring-auth:v0.0.1
        imagePullPolicy: IfNotPresent
        livenessProbe:
          failureThreshold: 3
          httpGet:
            path: /ping
            port: 4180
            scheme: HTTP
          initialDelaySeconds: 5
          periodSeconds: 5
          successThreshold: 1
          timeoutSeconds: 1
        name: auth-proxy
        ports:
        - containerPort: 4180
          name: http
          protocol: TCP
        readinessProbe:
          failureThreshold: 3
          httpGet:
            path: /ping
            port: 4180
            scheme: HTTP
          initialDelaySeconds: 5
          periodSeconds: 5
          successThreshold: 1
          timeoutSeconds: 1
        resources:
          limits:
            cpu: 10m
            memory: 20Mi
          requests:
            cpu: 5m
            memory: 10Mi
      dnsPolicy: ClusterFirst
      restartPolicy: Always
EOL

cat > ${NS}/auth/logging-auth-svc.yaml <<EOL
apiVersion: v1
kind: Service
metadata:
  labels:
    k8s-app: logging-${NS}-auth
  name: logging-${NS}-auth
  namespace: tectonic-system
spec:
  ports:
  - name: http
    port: 4180
    protocol: TCP
    targetPort: http
  selector:
    k8s-app: logging-${NS}-auth
  sessionAffinity: None
  type: ClusterIP
EOL

cat > ${NS}/kibana/logging-ingress.yaml <<EOL
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  annotations:
    ingress.kubernetes.io/rewrite-target: /
    ingress.kubernetes.io/ssl-redirect: "true"
    ingress.kubernetes.io/use-port-in-redirects: "true"
    kubernetes.io/ingress.class: tectonic
  name: logging-${NS}-ingress
  namespace: tectonic-system
spec:
  rules:
  - host: ${K8S_CLUSTER_DOMAIN}
    http:
      paths:
      - backend:
          serviceName: logging-${NS}-auth
          servicePort: 4180
        path: /logging-${NS}
  tls:
  - hosts:
    - ${K8S_CLUSTER_DOMAIN}
    secretName: tectonic-ingress-tls-secret
EOL

read -r -d '' FLUENTD_CONFIG << EOM
################################################################################
    <match kube.${NS}.**>
      type elasticsearch
      log_level info
      include_tag_key true
      # Replace with the host/port to your Elasticsearch cluster.
      # This assumes a service 'elasticsearch' exists in the default namespace
      host elasticsearch.${NS}.svc.cluster.local
      port 9200
      scheme http
      ssl_verify false

      logstash_format true
      template_file /fluentd/etc/elasticsearch-template-es5x.json
      template_name elasticsearch-template-es5x.json

      buffer_chunk_limit 2M
      buffer_queue_limit 32
      flush_interval 10s
      max_retry_wait 30
      disable_retry_limit
      num_threads 8
    </match>
################################################################################
EOM

echo "Deploy the resources defined in manifests that were written to '${NS}' directory"
echo "Add the following to the list of rediredURIs in tectonic-identity's config map"
echo "'https://${K8S_CLUSTER_DOMAIN}/logging-${NS}/auth/callback'"
echo "Add the following to the *beginning* of 'output.conf' in 'fluentd/fluentd-configmap.yaml':"
echo "${FLUENTD_CONFIG}"
echo "Finally, update the fluentd configmap"

