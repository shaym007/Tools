#!/bin/sh

###################
# The scripts runs API request to k8s auth via Akeyless GW (API, port 8080)
####################

echo -e "Please provide the folllwing:\nAccess-ID:"
read ACCESS_ID

echo -e "\nGW URL with port and path (e.g http://<gw-url>:8080/v2/auth)"
read GW_URL

echo -e "\nAuth config name:"
read AUTH_CONFIG_NAME

# Get the token from the GW with
# kubectl exec -it <gw-pod-name> -- /bin/bash -c "cat /var/run/secrets/kubernetes.io/serviceaccount/token | base64 -w 0; echo "

echo -e "\nk8s service account token (cat cat /var/run/secrets/kubernetes.io/serviceaccount/token | base64 -w0):"
read TOKEN


generate_post_data () {

cat << EOF
{
  "access-type": "k8s",
  "json": false,
  "debug": true,
  "access-id": "$ACCESS_ID",
  "k8s-auth-config-name": "$AUTH_CONFIG_NAME",
  "k8s-service-account-token": "$TOKEN"
}
EOF
}

curl --request POST \
     --url $GW_URL \
     --header 'accept: application/json' \
     --header 'content-type: application/json' \
     --data "$(generate_post_data)"
