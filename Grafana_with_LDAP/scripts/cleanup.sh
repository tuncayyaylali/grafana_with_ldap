#!/usr/bin/env bash
set -euo pipefail

echo "==> Uninstalling Grafana Helm release..."
helm uninstall grafana -n monitoring 2>/dev/null || true

echo "==> Deleting Kubernetes manifests..."
kubectl delete -f manifests/05-phpldapadmin.yaml --ignore-not-found=true
kubectl delete -f manifests/04-openldap-networkpolicy.yaml --ignore-not-found=true
kubectl delete -f manifests/02-grafana-ldap-secret.yaml --ignore-not-found=true
kubectl delete -f manifests/01-openldap.yaml --ignore-not-found=true

echo "==> Deleting namespaces..."
kubectl delete -f manifests/00-namespaces.yaml --ignore-not-found=true

echo "==> Teardown and cleanup completed successfully."