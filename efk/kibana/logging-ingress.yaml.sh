#!/bin/bash

cat > kibana/logging-ingress.yaml << EOS
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  annotations:
    ingress.kubernetes.io/rewrite-target: /
    ingress.kubernetes.io/ssl-redirect: "true"
    ingress.kubernetes.io/use-port-in-redirects: "true"
    kubernetes.io/ingress.class: tectonic
  name: logging-ingress
  namespace: tectonic-system
spec:
  rules:
  - host: ${K8S_CLUSTER_DOMAIN}
    http:
      paths:
      - backend:
          serviceName: logging-system-auth
          servicePort: 4180
        path: /logging-system
  tls:
  - hosts:
    - ${K8S_CLUSTER_DOMAIN}
    secretName: tectonic-ingress-tls-secret
EOS

