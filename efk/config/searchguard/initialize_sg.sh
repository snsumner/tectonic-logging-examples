#!/bin/bash

chmod +x /elasticsearch/plugins/search-guard-5/tools/sgadmin.sh
chmod +x /elasticsearch/plugins/search-guard-5/tools/hash.sh

hash=$(/elasticsearch/plugins/search-guard-5/tools/hash.sh -p $ADMIN_PWD)
sed -ri "s|hash:[^\r\n#]*#admin|hash: \'$hash\' #admin|" /elasticsearch/config/searchguard/sg_internal_users.yml

hash=$(/elasticsearch/plugins/search-guard-5/tools/hash.sh -p $KIBANA_PWD)
sed -ri "s|hash:[^\r\n#]*#kibana|hash: '$hash' #kibana|" /elasticsearch/config/searchguard/sg_internal_users.yml

hash=$(/elasticsearch/plugins/search-guard-5/tools/hash.sh -p $LOGSTASH_PWD)
sed -ri "s|hash:[^\r\n#]*#logstash|hash: '$hash' #logstash|" /elasticsearch/config/searchguard/sg_internal_users.yml

exec su-exec elasticsearch /elasticsearch/plugins/search-guard-5/tools/sgadmin.sh \
    -h ${NODE_NAME} \
    -cd /elasticsearch/config/searchguard \
    -cn ${CLUSTER_NAME} \
    -cacert /elasticsearch/config/tls/ca_chain/tls.crt \
    -cert /elasticsearch/config/tls/admin/tls.crt \
    -key /elasticsearch/config/tls/admin/tls.key

