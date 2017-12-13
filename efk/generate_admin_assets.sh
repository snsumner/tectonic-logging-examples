#/bin/bash

CLUSTER_NAME=$1

read -r -d '' USAGE << EOM
Generate TLS assets for ES cluster admin
./generate_admin_assets.sh [--help] <cluster_name>
EOM

if [ "$#" -ne 1 ]; then
    echo "Error: No cluster name provided"
    echo "$USAGE"
    exit 1
elif [ ${CLUSTER_NAME} = "--help" ]; then
    echo "$USAGE"
    exit 0
fi

touch tls/adminindex
echo $((100000 + RANDOM % 999999)) > tls/adminserial

cat > tls/admin.cnf <<EOS
[ca]
default_ca=intermediate_ca

[intermediate_ca]
new_certs_dir=tls
certificate=tls/ca-chain.pem
private_key=tls/ca-chain-key.pem
database=tls/adminindex
default_md=sha1
policy=intermediate_policy
serial=tls/adminserial
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
    -out tls/admin-rsa.pem \
    2048

openssl pkcs8 \
    -topk8 \
    -inform PEM \
    -outform PEM \
    -in tls/admin-rsa.pem \
    -out tls/admin-key.pem \
    -nocrypt

openssl req \
    -new \
    -key tls/admin-key.pem \
    -out tls/admin.csr \
    -subj /CN=${CLUSTER_NAME}-admin

openssl ca \
    -batch \
    -notext \
    -extensions v3_req \
    -config tls/admin.cnf \
    -in tls/admin.csr \
    -out tls/admin.pem

cat tls/ca-chain.pem >> tls/admin.pem

openssl x509 \
    -text \
    -in tls/admin.pem \
    -noout \
    > tls/admin.txt

kubectl create secret tls es-tls-admin-secret \
    -n logging \
    --cert tls/admin.pem \
    --key tls/admin-key.pem

