################ SET RUN TYPE DEUBGING ################
# RUN_TYPE="installation" #debugging                  #
# RUN_TYPE="nightly" #debugging                       #
#######################################################

pull_secret_exists=$(oc get secret  pull-secret -n sigstore-monitoring --ignore-not-found=true)

if [[ -z $pull_secret_exists ]]; then
    echo "Error, Secret \`pull-secret\` does not exist in nampesace \`sigstore-monitoring\`.
    Please download the pull-secret from \`https://console.redhat.com/application-services/trusted-content/artifact-signer\`
    and create a secret from it: \`oc create secret generic pull-secret -n sigstore-monitoring --from-file=\$HOME/Downloads/pull-secret.json\`. "
    exit 0
fi

secret_data=$(oc get secret pull-secret -n sigstore-monitoring -o "jsonpath={.data.pull-secret\.json}")
registry_auth=$(echo $secret_data | base64 -d | jq .auths."\"registry.redhat.io\"".auth | cut -d "\"" -f 2 | base64 -d)

declare org_id_index
declare user_id_index
base64_indexes=()

for ((i=0; i<${#registry_auth}; i++)); do
  char="${registry_auth:$i:1}"
  if [[ $char == "|" ]]; then
    org_id_index=$i
  elif [[ $char == ":" ]]; then
    user_id_index=$i
  elif [[ $char == "." ]]; then
    base64_indexes+=("$i")
  fi
done

org_id=${registry_auth:0:$org_id_index}
user_id=${registry_auth:$org_id_index+1:$user_id_index-($org_id_index+1)}
alg_id=$(echo ${registry_auth:$user_id_index+1:(${base64_indexes[0]}-($user_id_index+1))} | base64 -d | jq .alg | cut -d "\"" -f 2 )
sub_id=$(echo ${registry_auth:(${base64_indexes[0]}+1):(${base64_indexes[1]}-${base64_indexes[0]}-1)} | base64 -d | jq .sub |  cut -d "\"" -f 2)

PROM_TOKEN_SECRET_NAME=$(oc get secret -n openshift-user-workload-monitoring | grep  prometheus-user-workload-token | head -n 1 | awk '{print $1 }')
PROM_TOKEN_DATA=$(echo $(oc get secret $PROM_TOKEN_SECRET_NAME -n openshift-user-workload-monitoring -o json | jq -r '.data.token') | base64 -d)
THANOS_QUERIER_HOST=$(oc get route thanos-querier -n openshift-monitoring -o json | jq -r '.spec.host')

echo "org_id: $org_id" > /opt/app-root/src/tmp
echo "user_id: $user_id" >> /opt/app-root/src/tmp
echo "alg_id: $alg_id" >> /opt/app-root/src/tmp
echo "sub_id: $sub_id" >> /opt/app-root/src/tmp

if [[ $RUN_TYPE == "nightly" ]]; then
  fulcio_new_certs=$(curl -X GET -kG "https://$THANOS_QUERIER_HOST/api/v1/query?" --data-urlencode "query=fulcio_new_certs" -H "Authorization: Bearer $PROM_TOKEN_DATA" | jq '.data.result[] | .value[1]')

  rekor_new_entries_query_data=$(curl -X GET -kG "https://$THANOS_QUERIER_HOST/api/v1/query?" --data-urlencode "query=rekor_new_entries" -H "Authorization: Bearer $PROM_TOKEN_DATA" | jq '.data.result[]' )
  declare rekor_new_entries
  if [[ -z $rekor_new_entries_query_data ]]; then
    rekor_new_entries="0"
  else 
    rekor_new_entries=$(curl -X GET -kG "https://$THANOS_QUERIER_HOST/api/v1/query?" --data-urlencode "query=rekor_new_entries" -H "Authorization: Bearer $PROM_TOKEN_DATA" | jq '.data.result[] | .value[1]')
  fi

  declare rekor_qps_by_api
  rekor_qps_by_api_query_data=$(curl -X GET -kG "https://$THANOS_QUERIER_HOST/api/v1/query?" --data-urlencode "query=rekor_qps_by_api" -H "Authorization: Bearer $PROM_TOKEN_DATA" | jq '.data.result[]' )
  if [[ -z $rekor_qps_by_api_query_data ]]; then
    rekor_qps_by_api=""
  else 
    rekor_qps_by_api=$(curl -X GET -kG "https://$THANOS_QUERIER_HOST/api/v1/query?" --data-urlencode "query=rekor_qps_by_api" -H "Authorization: Bearer $PROM_TOKEN_DATA" | \
    jq -r '.data.result[] | "method:" + .metric.method + ",status_code:" + .metric.code + ",path:" + .metric.path + ",value:" + .value[1] + "|"')
  fi
  
  echo "fulcio_new_certs: $fulcio_new_certs" >> /opt/app-root/src/tmp
  echo "rekor_new_entries: $rekor_new_entries" >> /opt/app-root/src/tmp
  echo "rekor_qps_by_api: " $rekor_qps_by_api >> /opt/app-root/src/tmp
fi

if [[ $RUN_TYPE == "nightly" ]]; then
  python3 /opt/app-root/src/main-nightly.py
elif [[ $RUN_TYPE == "installation" ]]; then
  python3 /opt/app-root/src/main-installation.py
else 
  echo "error \$RUN_TYPE not set.
    options: \"nightly\", \"installation\""
  exit 1
fi