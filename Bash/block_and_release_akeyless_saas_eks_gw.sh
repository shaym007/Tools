#!/bin/bash -e

# This script will block or release connectivity to Akeyless SaaS services.
# Blocking will be made by routing the upstream SaaS trafic to a blockhole 
# The script is for testing purposes only and works best with one GW pod
#
# NOTE: the containerSecurityContext in the Deployment part should be added to allow routing modifications:
#
# containerSecurityContext:
#    allowPrivilegeEscalation: true
#    capabilities:
#        add: ["NET_ADMIN"]
#
#
# Usage: ./script_name.sh [block|release]


BLOCKED_IP_FILE="/tmp/blocked_ips.txt"

# Function to get the pod name and namespace of the running Akeyless API Gateway
get_pod_info() {
    local pod_info
    pod_info=$(kubectl get pods -l app.kubernetes.io/name=akeyless-api-gateway \
        --field-selector=status.phase=Running \
        -o jsonpath="{.items[0].metadata.name} {.items[0].metadata.namespace}" 2>/dev/null)

    if [[ -z "$pod_info" ]]; then
        echo "Error: No running Akeyless API Gateway pod found."
        exit 1
    fi

    local pod_name
    local namespace
    pod_name=$(echo "$pod_info" | awk '{print $1}')
    namespace=$(echo "$pod_info" | awk '{print $2}')

    echo "$pod_name" "$namespace"
}

# Function to install necessary tools on the pod
install_tools_on_pod() {
    local pod=$1
    local namespace=$2
    echo "Installing tools (lsof, iproute2) on pod: $pod in namespace: $namespace" >&2
    kubectl exec -n "$namespace" "$pod" -- apt-get update
    kubectl exec -n "$namespace" "$pod" -- apt-get install -y lsof iproute2
}

# Function to resolve domains to IPs
resolve_domains_to_ips() {
    local pod=$1
    local namespace=$2
    local ips=()

    echo "Fetching domains accessed on port 443 by pod: $pod in namespace: $namespace" >&2
    local domains
    domains=$(kubectl exec -n "$namespace" "$pod" -- lsof -i:443 2>/dev/null | \
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
block_ips_on_pod() {
    local pod=$1
    local namespace=$2
    shift 2
    local ips=("$@")

    echo "Blocking IPs on pod: $pod in namespace: $namespace" >&2
    for ip in "${ips[@]}"; do
        echo "Blocking IP $ip by routing it to 127.0.0.1" >&2
        kubectl exec -n "$namespace" "$pod" -- ip route add "$ip/32" via 127.0.0.1 || echo "Route for $ip already exists."
    done
}

# Function to release IPs
release_ips_on_pod() {
    local pod=$1
    local namespace=$2
    shift 2
    local ips=("$@")

    echo "Releasing IPs on pod: $pod in namespace: $namespace" >&2
    for ip in "${ips[@]}"; do
        echo "Releasing IP $ip by removing the route" >&2
        kubectl exec -n "$namespace" "$pod" -- ip route del "$ip/32" via 127.0.0.1 || echo "No existing route for $ip." >&2
    done
}

# Function to show current routes on the pod
show_routes_on_pod() {
    local pod=$1
    local namespace=$2
    echo "Listing existing routes on pod: $pod in namespace: $namespace" >&2
    kubectl exec -n "$namespace" "$pod" -- ip route show
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
    local pod_name
    local namespace
    pod_name=$(echo "$pod_info" | awk '{print $1}')
    namespace=$(echo "$pod_info" | awk '{print $2}')

    case "$action" in
        block)
            install_tools_on_pod "$pod_name" "$namespace"

            show_routes_on_pod "$pod_name" "$namespace"

            local resolved_ips
            resolved_ips=($(resolve_domains_to_ips "$pod_name" "$namespace"))

            if [[ ${#resolved_ips[@]} -eq 0 ]]; then
                echo "No IPs resolved to block." >&2
                exit 1
            fi

            echo "${resolved_ips[@]}" > "$BLOCKED_IP_FILE"
            block_ips_on_pod "$pod_name" "$namespace" "${resolved_ips[@]}"
            ;;
        release)
            if [[ ! -f "$BLOCKED_IP_FILE" ]]; then
                echo "No blocked IPs file found. Nothing to release." >&2
                exit 1
            fi

            local blocked_ips
            read -r -a blocked_ips < "$BLOCKED_IP_FILE"
            release_ips_on_pod "$pod_name" "$namespace" "${blocked_ips[@]}"
            rm -f "$BLOCKED_IP_FILE"
            ;;
        *)
            echo "Invalid action. Please use 'block' or 'release'." >&2
            exit 1
            ;;
    esac

    show_routes_on_pod "$pod_name" "$namespace"
}

main "$@"

