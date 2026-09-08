# Kubernetes OpenLDAP and Grafana RBAC Integration

This document provides a comprehensive, production-grade guide for deploying and configuring an OpenLDAP directory service integrated with Grafana on Kubernetes. It covers automated directory bootstrapping, official Helm-based Grafana deployment, LDAP authentication, Role-Based Access Control (RBAC), network security hardening with NetworkPolicy, directory administration via phpLDAPadmin, dashboard folder-level permissions, and end-to-end verification through both automated CLI scripts and the web user interfaces.

---

## Table of Contents

1. Architecture and Security Design
2. Repository Structure
3. Prerequisites
4. Step-by-Step Deployment Guide
   - Step 1: Namespace Creation
   - Step 2: OpenLDAP Deployment and Directory Bootstrapping
   - Step 3: Grafana LDAP Secret Packaging
   - Step 4: Grafana Helm Deployment
   - Step 5: Network Security Hardening (NetworkPolicy)
   - Step 6: phpLDAPadmin GUI Deployment
5. Automated CLI Verification
6. Grafana UI Verification and Role-Based Access Testing
7. Dashboard Management and Folder-Level Permissions
   - Importing General and Restricted Dashboards
   - Configuring Folder Access Control Lists (ACLs)
   - Verifying Dashboard Visibility Across Roles
8. Dynamic LDAP User Management
   - Adding Users via Command Line (LDIF)
   - Managing Directory Entries via phpLDAPadmin GUI
   - Verifying New Admin User in Grafana
9. Teardown and Cleanup
10. Complete Manifests, Configurations, and Source Code

---

## 1. Architecture and Security Design

- **Namespace Isolation:** Identity provider services reside in the `identity` namespace, while monitoring and visualization tools are deployed into the `monitoring` namespace.
- **Credential Protection:** OpenLDAP administrator credentials and Grafana bind passwords strictly reside in Kubernetes Secret resources (`openldap-admin-secret` and `grafana-ldap-secret`), preventing plaintext exposure in ConfigMaps or Helm values.
- **Cluster-Internal Routing:** Grafana communicates with OpenLDAP using the cluster-internal Fully Qualified Domain Name (`openldap.identity.svc.cluster.local:389`).
- **Zero-Trust Network Hardening:** A Kubernetes `NetworkPolicy` isolates OpenLDAP pod ingress traffic on TCP port 389 strictly to Grafana pods in the `monitoring` namespace and phpLDAPadmin in the `identity` namespace.
- **LDAP to Grafana RBAC Mapping:**
  - `cn=grafana-admins,ou=groups,dc=example,dc=org` maps to Grafana `Admin` (with Server Admin privileges).
  - `cn=grafana-editors,ou=groups,dc=example,dc=org` maps to Grafana `Editor`.
  - `cn=grafana-viewers,ou=groups,dc=example,dc=org` maps to Grafana `Viewer`.

---

## 2. Repository Structure

```text
.
├── README.md
├── .gitignore
├── manifests/
│   ├── 00-namespaces.yaml
│   ├── 01-openldap.yaml
│   ├── 02-grafana-ldap-secret.yaml
│   ├── 03-grafana-values.yaml
│   ├── 04-openldap-networkpolicy.yaml
│   ├── 05-phpldapadmin.yaml
│   └── new-user.ldif
├── dashboards/
│   ├── admin-dashboard.json
│   └── general-dashboard.json
└── scripts/
    ├── verify.sh
    └── cleanup.sh
```

---

## 3. Prerequisites

- Kubernetes Cluster (v1.28+) (Minikube, Kind, K3s, or Cloud Managed)
- `kubectl` CLI installed and configured
- `helm` v3 package manager
- `curl` and `bash` for running verification scripts

---

## 4. Step-by-Step Deployment Guide

### Step 1: Namespace Creation
Deploy the isolated namespaces for identity and monitoring:
```bash
kubectl apply -f manifests/00-namespaces.yaml
```

### Step 2: OpenLDAP Deployment and Directory Bootstrapping
Deploy OpenLDAP (`osixia/openldap:1.5.0`), mount admin secrets, initialize organizational units (`ou=users`, `ou=groups`), and seed the default test users (`jdoe`, `asmith`, `bjones`):
```bash
kubectl apply -f manifests/01-openldap.yaml
kubectl rollout status deployment/openldap -n identity --timeout=90s
```

### Step 3: Grafana LDAP Secret Packaging
Create the `grafana-ldap-secret` in the `monitoring` namespace, encoding the `ldap.toml` file with server connection and group-to-role mappings:
```bash
kubectl apply -f manifests/02-grafana-ldap-secret.yaml
```

### Step 4: Grafana Helm Deployment
Deploy Grafana using the official Helm chart with LDAP authentication enabled and the secret mounted into `/etc/grafana/ldap.toml`:
```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm upgrade --install grafana grafana/grafana -n monitoring -f manifests/03-grafana-values.yaml
kubectl rollout status deployment/grafana -n monitoring --timeout=120s
```

### Step 5: Network Security Hardening (NetworkPolicy)
Apply the zero-trust NetworkPolicy to restrict TCP port 389 access exclusively to Grafana and phpLDAPadmin:
```bash
kubectl apply -f manifests/04-openldap-networkpolicy.yaml
```

### Step 6: phpLDAPadmin GUI Deployment
Deploy the web management console to visually inspect and manage LDAP directory trees:
```bash
kubectl apply -f manifests/05-phpldapadmin.yaml
kubectl rollout status deployment/phpldapadmin -n identity --timeout=90s
```

---

## 5. Automated CLI Verification

The automated verification script (`scripts/verify.sh`) executes headless validation of the entire stack:
1. Spawns a background `kubectl port-forward` to Grafana.
2. Polls `/api/health` until the service is ready.
3. Authenticates each seed user against Grafana REST API (`/api/user/orgs`).
4. Asserts expected HTTP 200 responses and matching organization roles.
5. Asserts HTTP 401 Unauthorized upon invalid password submission.
6. Gracefully terminates the background port-forward process via exit trap.

Run the test script:
```bash
chmod +x scripts/verify.sh
bash scripts/verify.sh
```

Expected output:
```text
==> Starting port-forward to Grafana service (Port 3000)...
==> Waiting for Grafana to be ready...
==> Grafana is reachable and healthy.

=== LDAP Authentication & Role Mapping Tests ===
Testing: 'jdoe' (Expected Role: Admin) -> SUCCESS! (HTTP 200, Role: Admin)
Testing: 'asmith' (Expected Role: Editor) -> SUCCESS! (HTTP 200, Role: Editor)
Testing: 'bjones' (Expected Role: Viewer) -> SUCCESS! (HTTP 200, Role: Viewer)
Testing: Invalid password authentication for 'jdoe' -> SUCCESS! (HTTP 401 Unauthorized)

All verification tests passed successfully!
==> Cleaning up port-forward process (PID: 8587)...
```

---

## 6. Grafana UI Verification and Role-Based Access Testing

To test access via a web browser, start port-forwarding Grafana:
```bash
kubectl port-forward svc/grafana 3000:80 -n monitoring
```
Open `http://localhost:3000` in your web browser.

### Seed User Credentials and Permissions

| Username | Password | LDAP Group | Grafana Role | Create Dashboards | Edit Dashboards | Administration Menu |
|---|---|---|---|---|---|---|
| `jdoe` | `password123` | `grafana-admins` | Admin | Yes | Yes | Yes (Server Admin) |
| `asmith` | `password123` | `grafana-editors` | Editor | Yes | Yes | No |
| `bjones` | `password123` | `grafana-viewers` | Viewer | No | No | No |

### Interactive UI Validation Steps

1. **`jdoe` (Admin) Verification:**
   - Sign in as `jdoe`.
   - Inspect the top-right profile icon: confirm the assigned role is `Admin` with Server Admin capabilities.
   - Verify that the left sidebar displays the complete `Administration` section (Users, Orgs, Settings).
   - Verify that dashboard creation and panel editing are fully enabled.
   - Sign out.

2. **`asmith` (Editor) Verification:**
   - Sign in as `asmith`.
   - Inspect the profile icon: confirm the assigned role is `Editor`.
   - Verify that `Dashboards > New > New Dashboard` is accessible and panels can be created and modified.
   - Verify that `Administration` and server management menus are absent.
   - Sign out.

3. **`bjones` (Viewer) Verification:**
   - Sign in as `bjones`.
   - Inspect the profile icon: confirm the assigned role is `Viewer`.
   - Verify that the "New Dashboard" button is absent or disabled.
   - Verify that existing dashboards cannot be edited or saved (view-only mode).
   - Sign out.

---

## 7. Dashboard Management and Folder-Level Permissions

In Grafana, restricting specific dashboards to privileged roles is enforced using **Folder Permissions (ACLs)**.

### A. Folder Setup and Access Control Configuration

Sign in as `jdoe` (Admin):

1. **Create the Public Folder:**
   - Navigate to `Dashboards > New > New Folder`.
   - Folder Name: `General Dashboards`.
   - Leave default permissions intact (Admin, Editor, and Viewer can view).

2. **Create and Restrict the Admin-Only Folder:**
   - Navigate to `Dashboards > New > New Folder`.
   - Folder Name: `Admin Dashboards`.
   - Click the gear icon (**Folder settings**) in the top-right corner, then open the **Permissions** tab.
   - Delete the entries for `Editor` and `Viewer` using the trash icon.
   - Retain strictly the `Admin` role permission.

### B. Dashboard Import

1. **Import the General Overview Dashboard:**
   - Navigate to `Dashboards > New > Import`.
   - Upload `dashboards/general-dashboard.json`.
   - Under **Folder**, select `General Dashboards` and click **Import**.

2. **Import the Restricted Security Dashboard:**
   - Navigate to `Dashboards > New > Import`.
   - Upload `dashboards/admin-dashboard.json`.
   - Under **Folder**, select `Admin Dashboards` and click **Import**.

### C. Folder Access Verification Across Roles

- **Signed in as `jdoe` (Admin):** Both folders (`General Dashboards` and `Admin Dashboards`) and their respective dashboards are fully visible and editable.
- **Signed in as `asmith` (Editor):** The `Admin Dashboards` folder is completely hidden from dashboard listings and search. `General Dashboards` is visible and editable.
- **Signed in as `bjones` (Viewer):** Only `General Dashboards` is visible in read-only mode. The `Admin Dashboards` folder is hidden. Direct browser navigation to `/d/admin-security-overview` yields `Access Denied` / `Dashboard not found`.

---

## 8. Dynamic LDAP User Management

### Method 1: Adding Users via CLI (LDIF)

New users can be dynamically provisioned into the running OpenLDAP instance without pod restarts using `ldapadd`.

Example: Adding a new administrator account (`tyaylali`):

```bash
kubectl exec -i deployment/openldap -n identity -- ldapadd -x -D "cn=admin,dc=example,dc=org" -w "adminpassword" << 'EOF'
# User Account
dn: uid=tyaylali,ou=users,dc=example,dc=org
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
uid: tyaylali
cn: Tuncay Yaylali
cn: cn=grafana-admins,ou=groups,dc=example,dc=org
sn: Yaylali
givenName: Tuncay
mail: tyaylali@example.org
userPassword: password123

# Group Membership
dn: cn=grafana-admins,ou=groups,dc=example,dc=org
changetype: modify
add: member
member: uid=tyaylali,ou=users,dc=example,dc=org
EOF
```

### Method 2: Directory Management via phpLDAPadmin GUI

1. Start port-forwarding to phpLDAPadmin:
   ```bash
   kubectl port-forward svc/phpldapadmin 8080:80 -n identity
   ```
2. Navigate to `http://localhost:8080`.
3. Sign in:
   - **Login DN:** `cn=admin,dc=example,dc=org`
   - **Password:** `adminpassword`
4. Expand `dc=example,dc=org` to browse `ou=users` and `ou=groups`.
5. When creating users via GUI, avoid POSIX account templates (which demand numeric `gidNumber` values). Instead, select the **Default** template, choose the **`inetOrgPerson`** structural object class, and assign the Relative Distinguished Name (RDN) attribute to **`uid`**.
6. Associate the newly created user DN (`uid=...,ou=users,dc=example,dc=org`) as a `member` attribute under the target group in `ou=groups`.

### Verifying the New Admin User in Grafana

1. Navigate to `http://localhost:3000`.
2. Sign in with the new credentials:
   - **Username:** `tyaylali`
   - **Password:** `password123`
3. Confirm that Grafana grants the `Admin` role automatically, providing access to both `General Dashboards` and the restricted `Admin Dashboards` folder.

---

## 9. Teardown and Cleanup

To uninstall the Grafana Helm release and remove all Kubernetes manifests, secrets, network policies, and namespaces:

```bash
chmod +x scripts/cleanup.sh
bash scripts/cleanup.sh
```

---

## 10. Complete Manifests, Configurations, and Source Code

The following listings contain the full, unedited contents of every file in the repository.

### `manifests/00-namespaces.yaml`
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: identity
  labels:
    name: identity
---
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
  labels:
    name: monitoring
```

### `manifests/01-openldap.yaml`
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: openldap-admin-secret
  namespace: identity
type: Opaque
stringData:
  admin-password: "adminpassword"
  config-password: "configpassword"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: openldap-seed-ldif
  namespace: identity
data:
  seed.ldif: |
    # Organizational Units
    dn: ou=users,dc=example,dc=org
    objectClass: top
    objectClass: organizationalUnit
    ou: users

    dn: ou=groups,dc=example,dc=org
    objectClass: top
    objectClass: organizationalUnit
    ou: groups

    # Users
    dn: uid=jdoe,ou=users,dc=example,dc=org
    objectClass: top
    objectClass: person
    objectClass: organizationalPerson
    objectClass: inetOrgPerson
    uid: jdoe
    cn: John Doe
    cn: cn=grafana-admins,ou=groups,dc=example,dc=org
    sn: Doe
    givenName: John
    mail: jdoe@example.org
    userPassword: password123

    dn: uid=asmith,ou=users,dc=example,dc=org
    objectClass: top
    objectClass: person
    objectClass: organizationalPerson
    objectClass: inetOrgPerson
    uid: asmith
    cn: Alice Smith
    cn: cn=grafana-editors,ou=groups,dc=example,dc=org
    sn: Smith
    givenName: Alice
    mail: asmith@example.org
    userPassword: password123

    dn: uid=bjones,ou=users,dc=example,dc=org
    objectClass: top
    objectClass: person
    objectClass: organizationalPerson
    objectClass: inetOrgPerson
    uid: bjones
    cn: Bob Jones
    cn: cn=grafana-viewers,ou=groups,dc=example,dc=org
    sn: Jones
    givenName: Bob
    mail: bjones@example.org
    userPassword: password123

    # Groups
    dn: cn=grafana-admins,ou=groups,dc=example,dc=org
    objectClass: top
    objectClass: groupOfNames
    cn: grafana-admins
    member: uid=jdoe,ou=users,dc=example,dc=org

    dn: cn=grafana-editors,ou=groups,dc=example,dc=org
    objectClass: top
    objectClass: groupOfNames
    cn: grafana-editors
    member: uid=asmith,ou=users,dc=example,dc=org

    dn: cn=grafana-viewers,ou=groups,dc=example,dc=org
    objectClass: top
    objectClass: groupOfNames
    cn: grafana-viewers
    member: uid=bjones,ou=users,dc=example,dc=org
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: openldap
  namespace: identity
  labels:
    app: openldap
spec:
  replicas: 1
  selector:
    matchLabels:
      app: openldap
  template:
    metadata:
      labels:
        app: openldap
    spec:
      containers:
      - name: openldap
        image: osixia/openldap:1.5.0
        imagePullPolicy: IfNotPresent
        args: ["--copy-service"]
        env:
        - name: LDAP_ORGANISATION
          value: "Example Org"
        - name: LDAP_DOMAIN
          value: "example.org"
        - name: LDAP_ADMIN_PASSWORD
          valueFrom:
            secretKeyRef:
              name: openldap-admin-secret
              key: admin-password
        - name: LDAP_CONFIG_PASSWORD
          valueFrom:
            secretKeyRef:
              name: openldap-admin-secret
              key: config-password
        - name: LDAP_BASE_DN
          value: "dc=example,dc=org"
        - name: LDAP_TLS
          value: "false"
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
        ports:
        - containerPort: 389
          name: ldap
        volumeMounts:
        - name: seed-ldif-volume
          mountPath: /container/service/slapd/assets/config/bootstrap/ldif/custom/seed.ldif
          subPath: seed.ldif
      volumes:
      - name: seed-ldif-volume
        configMap:
          name: openldap-seed-ldif
---
apiVersion: v1
kind: Service
metadata:
  name: openldap
  namespace: identity
  labels:
    app: openldap
spec:
  type: ClusterIP
  ports:
  - port: 389
    targetPort: 389
    name: ldap
  selector:
    app: openldap
```

### `manifests/02-grafana-ldap-secret.yaml`
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: grafana-ldap-secret
  namespace: monitoring
type: Opaque
stringData:
  ldap-toml: |
    [[servers]]
    host = "openldap.identity.svc.cluster.local"
    port = 389
    use_ssl = false
    start_tls = false
    ssl_skip_verify = true
    bind_dn = "cn=admin,dc=example,dc=org"
    bind_password = "adminpassword"
    search_filter = "(&(objectClass=inetOrgPerson)(uid=%s))"
    search_base_dns = ["ou=users,dc=example,dc=org"]

    [servers.attributes]
    name = "givenName"
    surname = "sn"
    username = "uid"
    member_of = "cn"
    email = "mail"

    [[servers.group_mappings]]
    group_dn = "cn=grafana-admins,ou=groups,dc=example,dc=org"
    org_role = "Admin"
    grafana_admin = true

    [[servers.group_mappings]]
    group_dn = "cn=grafana-editors,ou=groups,dc=example,dc=org"
    org_role = "Editor"

    [[servers.group_mappings]]
    group_dn = "cn=grafana-viewers,ou=groups,dc=example,dc=org"
    org_role = "Viewer"
  ldap.toml: |
    [[servers]]
    host = "openldap.identity.svc.cluster.local"
    port = 389
    use_ssl = false
    start_tls = false
    ssl_skip_verify = true
    bind_dn = "cn=admin,dc=example,dc=org"
    bind_password = "adminpassword"
    search_filter = "(&(objectClass=inetOrgPerson)(uid=%s))"
    search_base_dns = ["ou=users,dc=example,dc=org"]

    [servers.attributes]
    name = "givenName"
    surname = "sn"
    username = "uid"
    member_of = "cn"
    email = "mail"

    [[servers.group_mappings]]
    group_dn = "cn=grafana-admins,ou=groups,dc=example,dc=org"
    org_role = "Admin"
    grafana_admin = true

    [[servers.group_mappings]]
    group_dn = "cn=grafana-editors,ou=groups,dc=example,dc=org"
    org_role = "Editor"

    [[servers.group_mappings]]
    group_dn = "cn=grafana-viewers,ou=groups,dc=example,dc=org"
    org_role = "Viewer"
```

### `manifests/03-grafana-values.yaml`
```yaml
adminPassword: "admin"

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 200m
    memory: 256Mi

persistence:
  enabled: false

ldap:
  enabled: true
  existingSecret: "grafana-ldap-secret"
  subPath: "ldap.toml"

grafana.ini:
  auth.ldap:
    enabled: true
    config_file: /etc/grafana/ldap.toml
    allow_sign_up: true
```

### `manifests/04-openldap-networkpolicy.yaml`
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-grafana-to-openldap
  namespace: identity
spec:
  podSelector:
    matchLabels:
      app: openldap
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring
      podSelector:
        matchLabels:
          app.kubernetes.io/name: grafana
    ports:
    - protocol: TCP
      port: 389
  - from:
    - podSelector:
        matchLabels:
          app: phpldapadmin
    ports:
    - protocol: TCP
      port: 389
```

### `manifests/05-phpldapadmin.yaml`
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: phpldapadmin
  namespace: identity
  labels:
    app: phpldapadmin
spec:
  replicas: 1
  selector:
    matchLabels:
      app: phpldapadmin
  template:
    metadata:
      labels:
        app: phpldapadmin
    spec:
      containers:
      - name: phpldapadmin
        image: osixia/phpldapadmin:0.9.0
        imagePullPolicy: IfNotPresent
        env:
        - name: PHPLDAPADMIN_LDAP_HOSTS
          value: "openldap.identity.svc.cluster.local"
        - name: PHPLDAPADMIN_HTTPS
          value: "false"
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 100m
            memory: 128Mi
        ports:
        - containerPort: 80
          name: http
---
apiVersion: v1
kind: Service
metadata:
  name: phpldapadmin
  namespace: identity
  labels:
    app: phpldapadmin
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 80
    name: http
  selector:
    app: phpldapadmin
```

### `manifests/new-user.ldif`
```ldif
dn: uid=cgreen,ou=users,dc=example,dc=org
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
uid: cgreen
cn: Clara Green
cn: cn=grafana-editors,ou=groups,dc=example,dc=org
sn: Green
givenName: Clara
mail: cgreen@example.org
userPassword: password123

dn: cn=grafana-editors,ou=groups,dc=example,dc=org
changetype: modify
add: member
member: uid=cgreen,ou=users,dc=example,dc=org
```

### `dashboards/general-dashboard.json`
```json
{
  "annotations": { "list": [] },
  "editable": true,
  "fiscalYearStartMonth": 0,
  "graphTooltip": 0,
  "links": [],
  "liveNow": false,
  "panels": [
    {
      "type": "stat",
      "title": "Sistem Sağlığı (Uptime)",
      "gridPos": { "h": 6, "w": 8, "x": 0, "y": 0 },
      "id": 1,
      "datasource": { "type": "testdata", "uid": "grafana" },
      "targets": [
        {
          "datasource": { "type": "testdata", "uid": "grafana" },
          "refId": "A",
          "scenarioId": "random_walk"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "color": { "mode": "thresholds" },
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "red", "value": null },
              { "color": "green", "value": 80 }
            ]
          },
          "unit": "percent"
        }
      }
    },
    {
      "type": "timeseries",
      "title": "Genel İstek Trafiği (RPS)",
      "gridPos": { "h": 6, "w": 16, "x": 8, "y": 0 },
      "id": 2,
      "datasource": { "type": "testdata", "uid": "grafana" },
      "targets": [
        {
          "datasource": { "type": "testdata", "uid": "grafana" },
          "refId": "A",
          "scenarioId": "random_walk"
        }
      ]
    }
  ],
  "refresh": "5s",
  "schemaVersion": 38,
  "style": "dark",
  "tags": ["genel", "public"],
  "time": { "from": "now-15m", "to": "now" },
  "title": "Genel Servis Durumu (Herkese Açık)",
  "uid": "general-overview"
}
```

### `dashboards/admin-dashboard.json`
```json
{
  "annotations": { "list": [] },
  "editable": true,
  "fiscalYearStartMonth": 0,
  "graphTooltip": 0,
  "links": [],
  "liveNow": false,
  "panels": [
    {
      "type": "gauge",
      "title": "Hassas Sunucu Kaynak Kullanımı",
      "gridPos": { "h": 8, "w": 12, "x": 0, "y": 0 },
      "id": 1,
      "datasource": { "type": "testdata", "uid": "grafana" },
      "targets": [
        {
          "datasource": { "type": "testdata", "uid": "grafana" },
          "refId": "A",
          "scenarioId": "random_walk"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "color": { "mode": "thresholds" },
          "max": 100,
          "min": 0,
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "green", "value": null },
              { "color": "orange", "value": 70 },
              { "color": "red", "value": 85 }
            ]
          },
          "unit": "percent"
        }
      }
    },
    {
      "type": "stat",
      "title": "Kritik Güvenlik Alarmları (Admin)",
      "gridPos": { "h": 8, "w": 12, "x": 12, "y": 0 },
      "id": 2,
      "datasource": { "type": "testdata", "uid": "grafana" },
      "targets": [
        {
          "datasource": { "type": "testdata", "uid": "grafana" },
          "refId": "A",
          "scenarioId": "random_walk"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "color": { "mode": "thresholds" },
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "red", "value": null }
            ]
          }
        }
      }
    }
  ],
  "refresh": "5s",
  "schemaVersion": 38,
  "style": "dark",
  "tags": ["admin", "security"],
  "time": { "from": "now-15m", "to": "now" },
  "title": "Yönetici & Güvenlik Paneli (Sadece Admin)",
  "uid": "admin-security-overview"
}
```

### `scripts/verify.sh`
```bash
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
```

### `scripts/cleanup.sh`
```bash
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
```

### `.gitignore`
```text
# OS files
.DS_Store
Thumbs.db
desktop.ini

# Editor and IDE configurations
.vscode/
.idea/
*.swp
*.swo

# Temporary runtime logs and directories
*.log
scratch/
tmp/
.temp/
*.pid
```