#!/usr/bin/env bash
set -euo pipefail

PORT=3000
NAMESPACE="monitoring"
SERVICE="svc/grafana"

echo "==> Starting port-forward to Grafana service (Port $PORT)..."
kubectl port-forward -n "$NAMESPACE" "$SERVICE" "$PORT:80" > /dev/null 2>&1 &
PF_PID=$!

cleanup() {
    echo "==> Cleaning up port-forward process (PID: $PF_PID)..."
    kill "$PF_PID" 2>/dev/null || true
}
trap cleanup EXIT

echo "==> Waiting for Grafana to be ready..."
for i in $(seq 1 30); do
    if curl -s -o /dev/null "http://localhost:${PORT}/api/health"; then
        echo "==> Grafana is reachable and healthy."
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "ERROR: Grafana port-forward timed out!"
        exit 1
    fi
    sleep 1
done

test_user() {
    local username="$1"
    local password="$2"
    local expected_role="$3"

    echo -n "Testing: '$username' (Expected Role: $expected_role) -> "

    response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -u "${username}:${password}" "http://localhost:${PORT}/api/user/orgs")
    http_code=$(echo "$response" | grep "HTTP_STATUS" | cut -d':' -f2)
    body=$(echo "$response" | grep -v "HTTP_STATUS")

    if [ "$http_code" != "200" ]; then
        echo "FAILED! (HTTP Status: $http_code)"
        echo "Response: $body"
        exit 1
    fi

    if echo "$body" | grep -q "\"role\":\"$expected_role\""; then
        echo "SUCCESS! (HTTP 200, Role: $expected_role)"
    else
        echo "FAILED! (Role mismatch, expected: $expected_role)"
        echo "Response: $body"
        exit 1
    fi
}

test_invalid_auth() {
    local username="$1"
    local password="$2"

    echo -n "Testing: Invalid password authentication for '$username' -> "
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -u "${username}:${password}" "http://localhost:${PORT}/api/user/orgs")

    if [ "$http_code" = "401" ]; then
        echo "SUCCESS! (HTTP 401 Unauthorized)"
    else
        echo "FAILED! (Expected HTTP 401, Got: $http_code)"
        exit 1
    fi
}

echo ""
echo "=== LDAP Authentication & Role Mapping Tests ==="
test_user "jdoe" "password123" "Admin"
test_user "asmith" "password123" "Editor"
test_user "bjones" "password123" "Viewer"
test_invalid_auth "jdoe" "wrongpassword"

echo ""
echo "All verification tests passed successfully!"