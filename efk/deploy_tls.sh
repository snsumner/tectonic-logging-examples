#!/bin/bash

CLUSTER_NAME=$1

read -r -d '' USAGE << EOM
Deploy TLS assets for EFK stack
./deploy_tls.sh [--help] <cluster_name>
EOM

if [ "$#" -ne 1 ]; then
    echo "Error: No cluster name provided"
    echo "$USAGE"
    exit 1
elif [ ${CLUSTER_NAME} = "--help" ]; then
    echo "$USAGE"
    exit 0
fi

mkdir tls

./generate_ca.sh
./generate_ca_chain.sh
./generate_admin_assets.sh ${CLUSTER_NAME}

echo "TLS assets deployed. Now start your ES cluster."

