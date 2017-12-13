#/bin/bash

CLUSTER_NAME=$1
CLIENT_NAME=$2

read -r -d '' USAGE << EOM
Generate TLS assets for ES client
./generate_client_assets.sh [--help] <cluster_name> <client_name>
EOM

if [ "$#" -eq 0 ]; then
    echo "Error: Incorrect number of arguments"
    echo "$USAGE"
    exit 1
elif [ ${CLUSTER_NAME} = "--help" ]; then
    echo "$USAGE"
    exit 0
elif [ "$#" -ne 2 ]; then
    echo "Error: Incorrect number of arguments"
    echo "$USAGE"
    exit 1
fi

touch tls/${CLIENT_NAME}index
echo $((100000 + RANDOM % 999999)) > tls/${CLIENT_NAME}serial

cat > tls/${CLIENT_NAME}.cnf <<EOS
[ca]
default_ca=intermediate_ca

[intermediate_ca]
new_certs_dir=tls
certificate=tls/ca-chain.pem
private_key=tls/ca-chain-key.pem
database=tls/${CLIENT_NAME}index
default_md=sha1
policy=intermediate_policy
serial=tls/${CLIENT_NAME}serial
default_days=365

[intermediate_policy]
commonName=supplied
stateOrProvinceName=optional
countryName=optional
emailAddress=optional
organizationName=optional
organizationalUnitName=optional

[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name

[req_distinguished_name]
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
EOS

openssl genrsa \
    -out tls/${CLIENT_NAME}-rsa.pem \
    2048

openssl pkcs8 \
    -topk8 \
    -inform PEM \
    -outform PEM \
    -in tls/${CLIENT_NAME}-rsa.pem \
    -out tls/${CLIENT_NAME}-key.pem \
    -nocrypt

openssl req \
    -new \
    -key tls/${CLIENT_NAME}-key.pem \
    -out tls/${CLIENT_NAME}.csr \
    -subj /CN=${CLUSTER_NAME}-${CLIENT_NAME}

openssl ca \
    -batch \
    -notext \
    -extensions v3_req \
    -config tls/${CLIENT_NAME}.cnf \
    -in tls/${CLIENT_NAME}.csr \
    -out tls/${CLIENT_NAME}.pem

cat tls/ca-chain.pem >> tls/${CLIENT_NAME}.pem

openssl x509 \
    -text \
    -in tls/${CLIENT_NAME}.pem \
    -noout \
    > tls/${CLIENT_NAME}.txt

kubectl create secret tls es-tls-${CLIENT_NAME}-secret \
    -n logging \
    --cert tls/${CLIENT_NAME}.pem \
    --key tls/${CLIENT_NAME}-key.pem

