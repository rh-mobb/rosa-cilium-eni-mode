#!/bin/bash

# Script to list OIDC configs and optionally delete unused ones
# Usage: ./list-oidc-status.sh [--delete]

DELETE_MODE=false
if [ "$1" = "--delete" ]; then
    DELETE_MODE=true
    echo "=== DELETE MODE ENABLED ==="
    echo "This will delete unused OIDC configs as it finds them."
    echo "Press Ctrl+C to cancel, or wait 5 seconds to continue..."
    sleep 5
fi

# Create a temporary file to track used configs
> /tmp/used_oidc_configs.txt

echo "=== OIDC Configs in Use by Clusters ==="
rosa list clusters --output json | jq -r '.[] | .id' | while read -r cluster_id; do
    oidc_id=$(rosa describe cluster --cluster "$cluster_id" --output json | jq -r '.aws.sts.oidc_config.id')
    if [ "$oidc_id" != "null" ] && [ -n "$oidc_id" ]; then
        echo "Cluster $cluster_id uses OIDC config: $oidc_id"
        echo "$oidc_id" >> /tmp/used_oidc_configs.txt
    fi
done

echo ""
if [ "$DELETE_MODE" = "true" ]; then
    echo "=== Deleting Unused OIDC Configs ==="
    deleted_count=0
    failed_count=0
else
    echo "=== Unused OIDC Configs (Safe to Delete) ==="
fi

rosa list oidc-config --output json | jq -r '.[] | select(.reusable == true) | .id' | while read -r config_id; do
    if [ -n "$config_id" ]; then
        # Check if this config is in use
        if ! grep -q "^$config_id$" /tmp/used_oidc_configs.txt 2>/dev/null; then
            issuer_url=$(rosa list oidc-config --output json | jq -r ".[] | select(.id == \"$config_id\") | .issuer_url")

            if [ "$DELETE_MODE" = "true" ]; then
                echo "Deleting unused OIDC config: $config_id - $issuer_url"
                delete_output=$(rosa delete oidc-config --oidc-config-id "$config_id" --mode auto --yes 2>&1)
                delete_exit_code=$?

                if [ "$delete_exit_code" -eq 0 ]; then
                    echo "  ✅ Successfully deleted: $config_id"
                    # Check if it was already gone
                    if echo "$delete_output" | grep -q "not found"; then
                        echo "  ℹ️  (OIDC config was already deleted or provider not found)"
                    fi
                    deleted_count=$((deleted_count + 1))
                else
                    echo "  ❌ Failed to delete: $config_id"
                    echo "  Error: $delete_output"
                    failed_count=$((failed_count + 1))
                fi
            else
                echo "  $config_id - $issuer_url"
            fi
        fi
    fi
done

echo ""
echo "=== Summary ==="
total_configs=$(rosa list oidc-config --output json | jq '. | length')
used_count=$(wc -l < /tmp/used_oidc_configs.txt 2>/dev/null || echo "0")
unused_count=$((total_configs - used_count))

echo "Total OIDC configs: $total_configs"
echo "Total clusters: $(rosa list clusters --output json | jq '. | length')"
echo "Configs in use: $used_count"
echo "Configs safe to delete: $unused_count"

if [ "$DELETE_MODE" = "true" ]; then
    echo "Deleted configs: $deleted_count"
    echo "Failed deletions: $failed_count"
fi

# Cleanup
rm -f /tmp/used_oidc_configs.txt
