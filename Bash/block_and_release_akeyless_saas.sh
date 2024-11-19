#!/bin/bash

# This script will block or release connectivity to Akeyless SaaS services
# The script is for testing purposes and works best with one GW pod
# Usage: ./script_name.sh [block|release]

set -e

BLOCKED_IP_FILE="/tmp/blocked_ips.txt"

# Function to get the pod and namespace details
get_pod_info() {
    local pod_info
    pod_info=$(kubectl get pods --all-namespaces -l app.kubernetes.io/name=akeyless-api-gateway \
        -o jsonpath="{.items[0].metadata.name} {.items[0].metadata.namespace}" 2>/dev/null)
    if [[ -z "$pod_info" ]]; then
        echo "Error: No running Akeyless API Gateway pod found."
        exit 1
    fi

    echo "$pod_info"
}

# Function to install lsof in the pod
install_lsof() {
    local pod_name=$1
    local namespace=$2
    echo "Installing lsof on pod: $pod_name in namespace: $namespace" >&2
    kubectl exec -n "$namespace" "$pod_name" -- apt-get update
    kubectl exec -n "$namespace" "$pod_name" -- apt-get install -y lsof
}

# Function to resolve domains to IPs
resolve_domains_to_ips() {
    local pod_name=$1
    local namespace=$2
    local ips=()

    echo "Fetching domains accessed on port 443 by pod: $pod_name" >&2
    local domains
    domains=$(kubectl exec -n "$namespace" "$pod_name" -- lsof -i:443 2>/dev/null | \
        awk -F '->' '{print $2}' | awk -F ':' '{print $1}' | sort -u)

    for domain in $domains; do
        echo "Resolving domain: $domain" >&2
        local resolved_ips
        resolved_ips=$(dig +short "$domain")
        if [[ -n "$resolved_ips" ]]; then
            ips+=($resolved_ips)
            echo "Resolved IPs for $domain: $resolved_ips" >&2
        fi
    done

    echo "${ips[@]}"
}

# Function to block IPs
block_ips() {
    local ips=("$@")
    echo "Blocking IPs: ${ips[*]}" >&2
    for ip in "${ips[@]}"; do
        echo "Blocking IP $ip by routing it to 127.0.0.1" >&2
        sudo ip route add "$ip/32" via 127.0.0.1 || echo "Route for $ip already exists." >&2
    done
}

# Function to release IPs
release_ips() {
    local ips=("$@")
    echo "Releasing IPs: ${ips[*]}" >&2
    for ip in "${ips[@]}"; do
        echo "Releasing IP $ip by removing the route" >&2
        sudo ip route del "$ip/32" via 127.0.0.1 || echo "No existing route for $ip." >&2
    done
}

# Main logic
main() {
    local action=$1
    if [[ -z "$action" ]]; then
        echo "Usage: $0 [block|release]"
        exit 1
    fi

    local pod_info
    pod_info=$(get_pod_info)
    local pod_name namespace
    pod_name=$(echo "$pod_info" | awk '{print $1}')
    namespace=$(echo "$pod_info" | awk '{print $2}')

    case "$action" in
        block)
            install_lsof "$pod_name" "$namespace"

            local resolved_ips
            resolved_ips=($(resolve_domains_to_ips "$pod_name" "$namespace"))

            if [[ ${#resolved_ips[@]} -eq 0 ]]; then
                echo "No IPs resolved to block."
                exit 1
            fi

            echo "${resolved_ips[@]}" > "$BLOCKED_IP_FILE"
            block_ips "${resolved_ips[@]}"
            ;;
        release)
            if [[ ! -f "$BLOCKED_IP_FILE" ]]; then
                echo "No blocked IPs file found. Nothing to release."
                exit 1
            fi

            local blocked_ips
            read -r -a blocked_ips < "$BLOCKED_IP_FILE"
            release_ips "${blocked_ips[@]}"
            rm -f "$BLOCKED_IP_FILE"
            ;;
        *)
            echo "Invalid action. Please use 'block' or 'release'."
            exit 1
            ;;
    esac

    echo "Current routes:"
    sudo ip route show
}

main "$@"

