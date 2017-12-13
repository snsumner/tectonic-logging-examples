#!/bin/bash

CLIENT_NAME=$1
CLIENT_PWD=$2
NS=$3

read -r -d '' USAGE << EOM
Set passwords for ES clients
./set_client_pwd.sh [--help] <client_name> <client_pwd> <namespace>
EOM

if [ "$#" -eq 0 ]; then
    echo "Error: Incorrect number of arguments"
    echo "$USAGE"
    exit 1
elif [ ${CLIENT_NAME} = "--help" ]; then
    echo "$USAGE"
    exit 0
elif [ "$#" -ne 3 ]; then
    echo "Error: Incorrect number of arguments"
    echo "$USAGE"
    exit 1
fi

kubectl create secret generic es-pwd-${CLIENT_NAME}-secret \
    -n ${NS} \
    --from-literal password=${CLIENT_PWD}

