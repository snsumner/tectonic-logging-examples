#/bin/bash

read -r -d '' USAGE << EOM
Generate intermediate TLS assets for signing ES cluster certs
Requires root CA
./generate_ca_chain.sh [--help]
EOM

if [ $1 = "--help" ]; then
    echo "$USAGE"
    exit 0
elif [ "$#" -ne 0 ]; then
    echo "Error: Only accepted (optional) argument is '--help'"
    echo "$USAGE"
    exit 1
fi

openssl genrsa \
    -out tls/ca-chain-rsa.pem \
    2048

openssl pkcs8 \
    -topk8 \
    -inform PEM \
    -outform PEM \
    -in tls/ca-chain-rsa.pem \
    -out tls/ca-chain-key.pem \
    -nocrypt

openssl req \
    -new \
    -subj /CN=es-logging-chain \
    -key tls/ca-chain-key.pem \
    -out tls/ca-chain.csr

openssl ca \
    -batch \
    -notext \
    -extensions v3_req \
    -config tls/ca.cnf \
    -in tls/ca-chain.csr \
    -out tls/ca-chain.pem

openssl x509 \
    -text \
    -in tls/ca-chain.pem \
    -noout \
    > tls/ca-chain.txt

kubectl create secret tls es-tls-ca-chain-secret \
    -n logging \
    --cert tls/ca-chain.pem \
    --key tls/ca-chain-key.pem

