#/bin/bash

read -r -d '' USAGE << EOM
Generate self-signed root CA for ES cluster
./generate_ca.sh [--help]
EOM

if [ "$1" = "--help" ]; then
    echo "$USAGE"
    exit 0
elif [ "$#" -ne 0 ]; then
    echo "Error: Only accepted (optional) argument is '--help'"
    echo "$USAGE"
    exit 1
fi

touch tls/certindex
echo $((100000 + RANDOM % 999999)) > tls/certserial

cat > tls/ca.cnf <<EOS
[ca]
default_ca=selfsigned

[selfsigned]
new_certs_dir=tls
certificate=tls/ca.pem
private_key=tls/ca-key.pem
database=tls/certindex
serial=tls/certserial
default_md=sha1
policy=ca_policy
default_days=365

[ca_policy]
commonName=supplied
stateOrProvinceName=optional
countryName=optional
emailAddress=optional
organizationName=optional
organizationalUnitName=optional

[req]
req_extensions=v3_req
distinguished_name=req_distinguished_name

[req_distinguished_name]
[ v3_req ]
keyUsage=critical,keyCertSign,cRLSign
basicConstraints=critical,CA:TRUE
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer

EOS

openssl genrsa \
    -out tls/ca-key.pem \
    2048

openssl req \
    -x509 \
    -new \
    -nodes \
    -key tls/ca-key.pem \
    -days 10000 \
    -out tls/ca.pem \
    -subj /CN=es-logging-ca \
    -extensions v3_req \
    -config tls/ca.cnf

openssl x509 \
    -text \
    -in tls/ca.pem \
    -noout \
    > tls/ca.txt

