#!/bin/bash

cat > auth/logging-auth-deploy.yaml << EOS
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  labels:
    k8s-app: logging-system-auth
  name: logging-system-auth
  namespace: tectonic-system
spec:
  replicas: 1
  selector:
    matchLabels:
      k8s-app: logging-system-auth
  strategy:
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
    type: RollingUpdate
  template:
    metadata:
      labels:
        k8s-app: logging-system-auth
    spec:
      containers:
      - args:
        - -provider=oidc
        - -client-id=\$(CLIENT_ID)
        - -client-secret=\$(CLIENT_SECRET)
        - -cookie-secret=\$(COOKIE_SECRET)
        - -external-url=\$(BASE_URL)/logging-system
        - -proxy-prefix=/auth
        - -pass-host-header=true
        - -pass-user-headers=true
        - -pass-basic-auth=false
        - -cookie-name=_tectonic_monitoring_auth
        - -cookie-domain=${K8S_CLUSTER_DOMAIN}
        - -cookie-expire=8h0m0s
        - -email-domain=*
        - -redirect-url=\$(BASE_URL)/logging-system/auth/callback
        - -oidc-issuer-url=\$(OIDC_ISSUER_URL)
        - -http-address=http://0.0.0.0:4180
        - -upstream=http://kibana-system.tectonic-system.svc.cluster.local:5601
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
EOS
