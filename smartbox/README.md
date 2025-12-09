# FHIR App Portal - Kubernetes Deployment Guide

This guide will help you deploy the FHIR App Portal solution to your Kubernetes cluster using Kustomize.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Architecture](#architecture)
- [Configuration](#configuration)
- [Deployment](#deployment)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)

---

## Overview

The solution consists of four components:

| Component | Description | Namespace |
|-----------|-------------|-----------|
| **AidboxDB** | PostgreSQL database for Aidbox | `aidbox-db` |
| **Aidbox Portal** | FHIR server for admin portal (production data) | `aidbox-portal` |
| **Aidbox Sandbox** | FHIR server for developer portal (test data) | `aidbox-sandbox` |
| **FHIR App Portal** | Web application serving both portals | `fhir-app-portal` |

---

## Prerequisites

### Required Infrastructure

- Kubernetes cluster v1.24+
- NGINX Ingress Controller
- cert-manager with `letsencrypt` ClusterIssuer
- Flux CD (for HelmRelease resources) or Helm CLI
- Aidbox license key (contact https://aidbox.app)
- Storage class for PersistentVolumeClaim (default or specify in `database/pvc.yaml`)

### Required DNS Records

Configure 4 DNS A/CNAME records pointing to your ingress:

| Purpose | Example |
|---------|---------|
| Admin Aidbox | `aidbox.yourdomain.com` |
| Sandbox Aidbox | `aidbox-sandbox.yourdomain.com` |
| Admin Portal | `portal.yourdomain.com` |
| Developer Portal | `portal-sandbox.yourdomain.com` |

---

## Architecture

```
                           ┌─────────────────────────────┐
                           │     NGINX Ingress           │
                           └──────────┬──────────────────┘
                                      │
         ┌────────────────────────────┼────────────────────────────┐
         │                            │                            │
         ▼                            ▼                            ▼
┌─────────────────┐        ┌─────────────────┐        ┌─────────────────┐
│  Aidbox Portal  │        │ Aidbox Sandbox  │        │ FHIR App Portal │
│ (aidbox-portal) │◄──────►│(aidbox-sandbox) │◄──────►│(fhir-app-portal)│
└────────┬────────┘        └────────┬────────┘        └─────────────────┘
         │                          │
         └──────────┬───────────────┘
                    ▼
           ┌─────────────────┐
           │    AidboxDB     │
           │   (aidbox-db)   │
           └─────────────────┘
```

---

## Configuration

### Step 1: Update Domain Names

Replace `yourdomain.com` with your actual domain in the following files:

#### Aidbox Portal (`aidbox/portal/`)

**aidbox.yaml** - Update host:
```yaml
host: aidbox.yourdomain.com
```

**init-bundle.json** - Update OAuth redirect URI:
```json
"redirect_uri": "https://portal.yourdomain.com/api/admin/auth/callback"
```

#### Aidbox Sandbox (`aidbox/sandbox/`)

**aidbox.yaml** - Update host:
```yaml
host: aidbox-sandbox.yourdomain.com
```

**init-bundle.json** - Update OAuth redirect URI:
```json
"redirect_uri": "https://portal-sandbox.yourdomain.com/api/developer/auth/callback"
```

**init-bundle.json** - Update TokenIntrospector (for cross-instance auth):
```json
"jwt": {
  "iss": "https://aidbox.yourdomain.com"
},
"jwks_uri": "https://aidbox.yourdomain.com/.well-known/jwks.json"
```

**init-bundle.json** - Update AccessPolicy issuer:
```json
"iss": {
  "constant": "https://aidbox.yourdomain.com"
}
```

#### FHIR App Portal (`fhir-app-portal/`)

**configmap.yaml** - Update all URLs:
```yaml
CORS_ORIGINS: "https://portal.yourdomain.com,https://portal-sandbox.yourdomain.com"
ADMIN_FRONTEND_URL: "https://portal.yourdomain.com"
DEVELOPER_FRONTEND_URL: "https://portal-sandbox.yourdomain.com"
AIDBOX_ADMIN_PUBLIC_URL: "https://aidbox.yourdomain.com"
AIDBOX_DEV_PUBLIC_URL: "https://aidbox-sandbox.yourdomain.com"
ADMIN_AIDBOX_PUBLIC_URL: "https://aidbox.yourdomain.com"
DEVELOPER_AIDBOX_PUBLIC_URL: "https://aidbox-sandbox.yourdomain.com"
```

**ingress.yaml** - Update hosts:
```yaml
tls:
- hosts:
  - portal.yourdomain.com
  - portal-sandbox.yourdomain.com
rules:
- host: portal.yourdomain.com
- host: portal-sandbox.yourdomain.com
```

### Step 2: Configure Database Storage (Optional)

If you need a specific storage class, update `database/pvc.yaml`:

```yaml
spec:
  storageClassName: your-storage-class
  resources:
    requests:
      storage: 50Gi  # Adjust as needed
```

---

## Deployment

### Step 1: Deploy Database

```bash
# Create database namespace and secret
kubectl create namespace aidbox-db

kubectl create secret generic aidboxdb-secret \
  --namespace aidbox-db \
  --from-literal=POSTGRES_USER=postgres \
  --from-literal=POSTGRES_PASSWORD=<your-secure-password>

# Deploy database
kubectl apply -k database/
```

Wait for the database to be ready:

```bash
kubectl wait --for=condition=ready pod -l service=aidboxdb -n aidbox-db --timeout=120s
```

### Step 2: Create Aidbox Secrets

```bash
# Aidbox Portal secrets
kubectl create namespace aidbox-portal

kubectl create secret generic postgres-secrets \
  --namespace aidbox-portal \
  --from-literal=BOX_DB_USER=postgres \
  --from-literal=BOX_DB_PASSWORD=<your-db-password>

kubectl create secret generic aidbox-secrets \
  --namespace aidbox-portal \
  --from-literal=AIDBOX_LICENSE=<your-aidbox-license> \
  --from-literal=BOX_AUTH_KEYS_SECRET=<your-jwt-secret> \
  --from-literal=BOX_ADMIN_PASSWORD=<your-admin-password>
```

```bash
# Aidbox Sandbox secrets
kubectl create namespace aidbox-sandbox

kubectl create secret generic postgres-secrets \
  --namespace aidbox-sandbox \
  --from-literal=BOX_DB_USER=postgres \
  --from-literal=BOX_DB_PASSWORD=<your-db-password>

kubectl create secret generic aidbox-secrets \
  --namespace aidbox-sandbox \
  --from-literal=AIDBOX_LICENSE=<your-aidbox-license> \
  --from-literal=BOX_AUTH_KEYS_SECRET=<your-jwt-secret> \
  --from-literal=BOX_ADMIN_PASSWORD=<your-admin-password>
```

### Step 3: Create FHIR App Portal Secrets

```bash
kubectl create namespace fhir-app-portal

kubectl create secret generic fhir-app-portal--session-secret \
  --namespace fhir-app-portal \
  --from-literal=SESSION_SECRET=$(openssl rand -hex 32) \
  --from-literal=ADMIN_API_CLIENT_SECRET=<your-admin-api-secret> \
  --from-literal=DEVELOPER_API_CLIENT_SECRET=<your-developer-api-secret>
```

### Step 4: Deploy with Kustomize

#### Option A: Using Flux CD (Recommended)

If you have Flux CD installed, apply the manifests:

```bash
# Deploy Aidbox Portal
kubectl apply -k aidbox/portal/

# Deploy Aidbox Sandbox
kubectl apply -k aidbox/sandbox/

# Deploy FHIR App Portal
kubectl apply -k fhir-app-portal/
```

Flux will reconcile the HelmRelease resources and deploy Aidbox via Helm.

#### Option B: Without Flux (Manual Helm)

If you don't have Flux CD, deploy Aidbox using Helm directly:

```bash
# Add Aidbox Helm repository
helm repo add aidbox https://aidbox.github.io/helm-charts
helm repo update
```

**Deploy Aidbox Portal:**

```bash
kubectl create configmap init-bundle \
  --namespace aidbox-portal \
  --from-file=init-bundle.json=aidbox/portal/init-bundle.json

helm install aidbox aidbox/aidbox \
  --namespace aidbox-portal \
  --set host=aidbox.yourdomain.com \
  --set protocol=https \
  --set image.tag=2510 \
  --set config.BOX_ID=aidbox-portal \
  --set config.BOX_INSTANCE_NAME=aidbox-portal \
  --set config.BOX_DB_HOST=aidboxdb.aidbox-db.svc.cluster.local \
  --set config.BOX_DB_PORT=5432 \
  --set config.BOX_DB_DATABASE=portal \
  --set config.BOX_INIT_BUNDLE=file:///init-bundle/init-bundle.json \
  --set ingress.enabled=true \
  --set ingress.className=nginx \
  --set 'ingress.annotations.cert-manager\.io/cluster-issuer=letsencrypt' \
  --set 'extraEnvFromSecrets[0]=aidbox-secrets' \
  --set 'extraEnvFromSecrets[1]=postgres-secrets' \
  --set 'volumes[0].name=init-bundle' \
  --set 'volumes[0].configMap.name=init-bundle' \
  --set 'volumeMounts[0].name=init-bundle' \
  --set 'volumeMounts[0].mountPath=/init-bundle' \
  --wait --timeout 10m
```

**Deploy Aidbox Sandbox:**

```bash
kubectl create configmap init-bundle \
  --namespace aidbox-sandbox \
  --from-file=init-bundle.json=aidbox/sandbox/init-bundle.json

helm install aidbox aidbox/aidbox \
  --namespace aidbox-sandbox \
  --set host=aidbox-sandbox.yourdomain.com \
  --set protocol=https \
  --set image.tag=2510 \
  --set config.BOX_ID=aidbox-sandbox \
  --set config.BOX_INSTANCE_NAME=aidbox-sandbox \
  --set config.BOX_DB_HOST=aidboxdb.aidbox-db.svc.cluster.local \
  --set config.BOX_DB_PORT=5432 \
  --set config.BOX_DB_DATABASE=sandbox \
  --set config.BOX_INIT_BUNDLE=file:///init-bundle/init-bundle.json \
  --set ingress.enabled=true \
  --set ingress.className=nginx \
  --set 'ingress.annotations.cert-manager\.io/cluster-issuer=letsencrypt' \
  --set 'extraEnvFromSecrets[0]=aidbox-secrets' \
  --set 'extraEnvFromSecrets[1]=postgres-secrets' \
  --set 'volumes[0].name=init-bundle' \
  --set 'volumes[0].configMap.name=init-bundle' \
  --set 'volumeMounts[0].name=init-bundle' \
  --set 'volumeMounts[0].mountPath=/init-bundle' \
  --wait --timeout 10m
```

**Deploy FHIR App Portal:**

```bash
kubectl apply -k fhir-app-portal/
```

---

## Verification

### Check Pod Status

```bash
# Database
kubectl get pods -n aidbox-db

# Aidbox instances
kubectl get pods -n aidbox-portal
kubectl get pods -n aidbox-sandbox

# Portal application
kubectl get pods -n fhir-app-portal
```

All pods should be in `Running` state.

### Check Ingresses

```bash
kubectl get ingress --all-namespaces
```

### Check Certificates

```bash
kubectl get certificates --all-namespaces
```

Certificates should show `Ready: True`.

### Test Endpoints

After deployment, access your applications:

| Application | URL |
|-------------|-----|
| Admin Portal | `https://portal.yourdomain.com` |
| Developer Portal | `https://portal-sandbox.yourdomain.com` |
| Admin Aidbox | `https://aidbox.yourdomain.com` |
| Sandbox Aidbox | `https://aidbox-sandbox.yourdomain.com` |

**Default Aidbox Credentials:**
- Username: `admin`
- Password: Value set in `BOX_ADMIN_PASSWORD` secret

---

## Troubleshooting

### Database Issues

```bash
# Check database pod status
kubectl describe pod -n aidbox-db -l service=aidboxdb

# Check database logs
kubectl logs -n aidbox-db -l service=aidboxdb

# Connect to database manually
kubectl exec -it -n aidbox-db statefulset/aidboxdb -- psql -U postgres

# List databases
kubectl exec -it -n aidbox-db statefulset/aidboxdb -- psql -U postgres -c "\l"
```

### Aidbox Pods Not Starting

```bash
# Check pod events
kubectl describe pod -n aidbox-portal -l app.kubernetes.io/name=aidbox

# Check logs
kubectl logs -n aidbox-portal -l app.kubernetes.io/name=aidbox

# Check database connectivity
kubectl exec -it -n aidbox-portal <pod-name> -- nc -zv aidboxdb.aidbox-db.svc.cluster.local 5432
```

### Certificate Issues

```bash
# Check certificate status
kubectl describe certificate -n aidbox-portal

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager
```

### Ingress Not Working

```bash
# Check ingress status
kubectl describe ingress -n aidbox-portal

# Check ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
```

### HelmRelease Not Reconciling (Flux)

```bash
# Check HelmRelease status
kubectl get helmrelease -n aidbox-portal

# Check Flux logs
kubectl logs -n flux-system -l app=helm-controller

# Force reconciliation
flux reconcile helmrelease aidbox -n aidbox-portal
```

---

## File Structure

```
customer-deployment/
├── README.md
├── database/
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── configmap.yaml           # PostgreSQL configuration
│   ├── pvc.yaml                 # Persistent Volume Claim
│   ├── statefulset.yaml         # Database StatefulSet
│   └── service.yaml             # Database Service
├── aidbox/
│   ├── portal/
│   │   ├── kustomization.yaml
│   │   ├── namespace.yaml
│   │   ├── aidbox.yaml          # HelmRepository + HelmRelease
│   │   └── init-bundle.json     # OAuth clients & access policies
│   └── sandbox/
│       ├── kustomization.yaml
│       ├── namespace.yaml
│       ├── aidbox.yaml          # HelmRepository + HelmRelease
│       └── init-bundle.json     # OAuth clients, policies & test data
├── fhir-app-portal/
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── configmap.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   └── ingress.yaml
└── secrets/
    └── secrets-template.env     # Template for secrets reference
```

---

## Configuration Reference

### Required Secrets

| Namespace | Secret Name | Keys |
|-----------|-------------|------|
| `aidbox-db` | `aidboxdb-secret` | `POSTGRES_USER`, `POSTGRES_PASSWORD` |
| `aidbox-portal` | `aidbox-secrets` | `AIDBOX_LICENSE`, `BOX_AUTH_KEYS_SECRET`, `BOX_ADMIN_PASSWORD` |
| `aidbox-portal` | `postgres-secrets` | `BOX_DB_USER`, `BOX_DB_PASSWORD` |
| `aidbox-sandbox` | `aidbox-secrets` | `AIDBOX_LICENSE`, `BOX_AUTH_KEYS_SECRET`, `BOX_ADMIN_PASSWORD` |
| `aidbox-sandbox` | `postgres-secrets` | `BOX_DB_USER`, `BOX_DB_PASSWORD` |
| `fhir-app-portal` | `fhir-app-portal--session-secret` | `SESSION_SECRET`, `ADMIN_API_CLIENT_SECRET`, `DEVELOPER_API_CLIENT_SECRET` |

### Database Connection

The Aidbox instances connect to the database using:

```
Host: aidboxdb.aidbox-db.svc.cluster.local
Port: 5432
Databases: portal, sandbox
```

---

## Deployment Order Summary

1. **Database** → `kubectl apply -k database/`
2. **Secrets** → Create all secrets in respective namespaces
3. **Aidbox Portal** → `kubectl apply -k aidbox/portal/`
4. **Aidbox Sandbox** → `kubectl apply -k aidbox/sandbox/`
5. **FHIR App Portal** → `kubectl apply -k fhir-app-portal/`

---

## Support

- **Aidbox Documentation**: https://docs.aidbox.app
- **Aidbox Support**: https://aidbox.app/support
