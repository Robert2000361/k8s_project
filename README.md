<div align="center">

# 🏦 Cloud-Native Banking Platform on Kubernetes

### A Production-Grade, Four-Phase Kubernetes Capstone Project

[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.34-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15--alpine-4169E1?style=for-the-badge&logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![Node.js](https://img.shields.io/badge/Node.js-18--alpine-339933?style=for-the-badge&logo=nodedotjs&logoColor=white)](https://nodejs.org/)
[![Nginx](https://img.shields.io/badge/Nginx-1.25--alpine-009639?style=for-the-badge&logo=nginx&logoColor=white)](https://nginx.org/)
[![Docker](https://img.shields.io/badge/Docker-Hub-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://hub.docker.com/)
[![Minikube](https://img.shields.io/badge/Minikube-v1.37+-F7931E?style=for-the-badge&logo=kubernetes&logoColor=white)](https://minikube.sigs.k8s.io/)

*A real banking application — account management and money transfers — deployed on a fully production-hardened Kubernetes cluster, covering every major K8s object in one cohesive system.*

</div>

---

## 📑 Table of Contents

1. [Project Overview](#-project-overview)
2. [Architecture & Mental Model](#-architecture--mental-model)
3. [Repository Structure](#-repository-structure)
4. [Kubernetes Objects Inventory](#-kubernetes-objects-inventory)
5. [Prerequisites](#-prerequisites)
6. [Quick Start — One-Command Deploy](#-quick-start--one-command-deploy)
7. [Step-by-Step Deployment (All 4 Phases)](#-step-by-step-deployment-all-4-phases)
   - [Pre-Setup: Node Configuration](#pre-setup-node-labeling--tainting)
   - [Phase 1 — It Works](#phase-1--it-works)
   - [Phase 2 — It Is Secure](#phase-2--it-is-secure)
   - [Phase 3 — It Scales](#phase-3--it-scales)
   - [Phase 4 — It Survives](#phase-4--it-survives)
8. [API Endpoint Reference](#-api-endpoint-reference)
9. [Environment Variables & Configuration](#-environment-variables--configuration)
10. [Security Architecture](#-security-architecture)
11. [Key Architectural Decisions](#-key-architectural-decisions-the-why)
12. [Testing & Validation Playbook](#-testing--validation-playbook)
13. [Troubleshooting & Common Pitfalls](#-troubleshooting--common-pitfalls)
14. [Useful Operations Commands](#-useful-operations-commands)

---

## 🎯 Project Overview

This project is the capstone of a Kubernetes engineering course. The goal is to deploy a real, three-tier banking application — **not** just sample YAMLs — on a fully configured Kubernetes cluster built from scratch.

By the end of all four phases, every major Kubernetes object is in production use in a real context:

| Phase | Theme | What Gets Deployed |
|-------|-------|--------------------|
| **Phase 1** | It Works | Namespace, ConfigMap, Secret, StatefulSet, Deployments, Services |
| **Phase 2** | It Is Secure | Ingress, RBAC, SecurityContext, NetworkPolicy (Zero Trust) |
| **Phase 3** | It Scales | HPA, VPA, Node Affinity, Taints & Tolerations, Health Probes |
| **Phase 4** | It Survives | Data Persistence, Rolling Update, Rollback, DaemonSet Logging |

**The application** lets users open bank accounts, check balances, and transfer money between accounts through a live web UI backed by a Node.js API and a highly available PostgreSQL cluster.

---

## 🏛 Architecture & Mental Model

```
                          ┌─────────────────────────────────────────────────────────────┐
                          │                   banking namespace                          │
    ┌──────────┐          │  ┌──────────────────────────────────────────────────────┐   │
    │ Internet │──HTTPS──▶│  │         NGINX Ingress Controller                     │   │
    │          │          │  │  banking.local/      ──▶  banking-dashboard-svc:80   │   │
    └──────────┘          │  │  banking.local/api/* ──▶  banking-api-svc:3000       │   │
   banking.local          │  │  banking.local/health──▶  banking-api-svc:3000       │   │
                          │  └──────────────────────────────────────────────────────┘   │
                          │              │                      │                        │
                          │  ┌───────────▼──────────┐  ┌───────▼──────────────────┐    │
                          │  │  Worker Node 1        │  │  Worker Node 2           │    │
                          │  │  (App + DB Primary)   │  │  (App Replica + DB Rep.) │    │
                          │  │                       │  │                          │    │
                          │  │  ┌─────────────────┐  │  │  ┌──────────────────┐   │    │
                          │  │  │  banking-api    │  │  │  │  banking-api     │   │    │
                          │  │  │  Pod 1/2        │  │  │  │  Pod 2/2         │   │    │
                          │  │  │  :3000          │  │  │  │  :3000           │   │    │
                          │  │  │  HPA: 2→10 pods │  │  │  │  TopologySpread  │   │    │
                          │  │  └────────┬────────┘  │  │  └────────┬─────────┘   │    │
                          │  │           │            │  │           │             │    │
                          │  │  ┌────────▼────────┐  │  │           │             │    │
                          │  │  │ banking-dashboard│  │  │           │             │    │
                          │  │  │  Pod 1/1  :80   │  │  │           │             │    │
                          │  │  └─────────────────┘  │  │           │             │    │
                          │  │                       │  │           │             │    │
                          │  │  ┌─────────────────┐  │  │  ┌────────▼─────────┐   │    │
                          │  │  │  postgres-db-0  │  │  │  │  postgres-db-1   │   │    │
                          │  │  │  PRIMARY  :5432 │  │  │  │  REPLICA   :5432 │   │    │
                          │  │  │  PVC: 5Gi RWO   │  │  │  │  PVC: 5Gi  RWO  │   │    │
                          │  │  └─────────────────┘  │  │  └──────────────────┘   │    │
                          │  │                       │  │                          │    │
                          │  │  ┌─────────────────┐  │  │  ┌──────────────────┐   │    │
                          │  │  │ fluentd DaemonSet│  │  │  │ fluentd DaemonSet│   │    │
                          │  │  │  (tolerates all) │  │  │  │  (tolerates all) │   │    │
                          │  │  └─────────────────┘  │  │  └──────────────────┘   │    │
                          │  └───────────────────────┘  └──────────────────────────┘   │
                          │                                                             │
                          │  ─────────────── Kubernetes Services ─────────────────     │
                          │  banking-api-service      ClusterIP      :3000             │
                          │  banking-dashboard-service ClusterIP     :80               │
                          │  postgres-svc             Headless       :5432             │
                          │  postgres-master          ClusterIP      :5432  (W only)   │
                          │  postgres-replica         ClusterIP      :5432  (R only)   │
                          └─────────────────────────────────────────────────────────────┘
```

### Component Summary

| Component | Technology | K8s Object | Replicas | Role |
|-----------|------------|------------|----------|------|
| Banking API | Node.js 18 + Express | `Deployment` | 2 (HPA: max 10) | Business logic, transactions, accounts |
| Banking Dashboard | HTML/JS + Nginx 1.25 | `Deployment` | 1 | Live UI, auto-refresh every 10s |
| Database Primary | PostgreSQL 15-alpine | `StatefulSet` (pod-0) | 1 | Read + Write operations |
| Database Replica | PostgreSQL 15-alpine | `StatefulSet` (pod-1) | 1 | Read-only, HA failover |
| Log Aggregator | Fluentd | `DaemonSet` | 1 per node | Collects all banking namespace logs |
| Ingress | NGINX Ingress Controller | `Ingress` | — | Single entry point, path-based routing |

---

## 📁 Repository Structure

```
k8s-banking-platform/
│
├── app/
│   ├── banking-api/
│   │   ├── app.js              # Express API — accounts, transactions, health
│   │   ├── package.json
│   │   ├── Dockerfile          # Multi-stage Node 18 build, non-root UID 1000
│   │   └── .dockerignore
│   │
│   └── banking-dashboard/
│       ├── index.html          # SPA dashboard, polls /api/* every 10s
│       ├── nginx.conf          # Proxies /api/* to banking-api-service:3000
│       └── Dockerfile          # Nginx 1.25-alpine, non-root UID 101
│
├── k8s/
│   ├── 00-namespace.yaml             # banking namespace (env: production)
│   ├── 01-configmap.yaml             # Non-sensitive config (DB_HOST, ports, limits)
│   ├── 02-secret.yaml                # DB_PASSWORD, JWT_SECRET, dockerhub-token
│   ├── 03-postgres-statefulset.yaml  # PostgreSQL StatefulSet + headless service
│   ├── 04-api-deployment.yaml        # Banking API (2 replicas, init container)
│   ├── 05-dashboard-deployment.yaml  # Dashboard (1 replica, nginx)
│   ├── 06-services.yaml              # ClusterIP services for API + Dashboard
│   ├── 06-DBservices.yaml            # Specialized postgres-master + postgres-replica services
│   ├── 07-ingress.yaml               # NGINX Ingress routing rules
│   ├── 08-hpa-vpa.yaml               # HPA for API + VPA for PostgreSQL
│   ├── 08-pg-scripts.yaml            # ConfigMap: pg replication shell scripts
│   ├── 09-rbac.yaml                  # ServiceAccounts, Roles, RoleBindings
│   ├── 10-networkpolicy.yaml         # 7 NetworkPolicies (deny-all + explicit allows)
│   ├── 11-daemonset-fluentd.yaml     # Fluentd DaemonSet (log collection)
│   └── 12-setup-nodes.sh             # Node label + taint script (run before StatefulSet)
│
└── deploy-banking.sh                 # One-command full deploy script (all 4 phases)
```

---

## 📦 Kubernetes Objects Inventory

Every object below must be present in the cluster at completion:

| Object | Count | File | Purpose |
|--------|-------|------|---------|
| `Namespace` | 1 | `00-namespace.yaml` | Isolates all resources under `banking` |
| `ConfigMap` | 1 | `01-configmap.yaml` | Non-sensitive env vars injected into API pods |
| `Secret` | 1 | `02-secret.yaml` | `DB_PASSWORD`, `JWT_SECRET`, `dockerhub-token` |
| `StatefulSet` | 1 | `03-postgres-statefulset.yaml` | PostgreSQL with stable pod identity & ordered startup |
| `PVC` | 2 (auto) | via `volumeClaimTemplates` | 5Gi `ReadWriteOnce` per postgres pod |
| `Deployment` | 2 | `04, 05` | Banking API (2 replicas) + Dashboard (1 replica) |
| `Service (ClusterIP)` | 5 | `06-services.yaml`, `06-DBservices.yaml` | Internal routing + specialized DB read/write split |
| `Ingress` | 1 | `07-ingress.yaml` | External entry point with path-based routing |
| `HPA` | 1 | `08-hpa-vpa.yaml` | Auto-scales API: min 2 → max 10 at 60% CPU |
| `VPA` | 1 | `08-hpa-vpa.yaml` | Resource recommendations for PostgreSQL (mode: Off) |
| `ConfigMap` | 1 | `08-pg-scripts.yaml` | Replication shell scripts mounted into postgres pods |
| `Role + RoleBinding` | 3 | `09-rbac.yaml` | Least-privilege `developer` role (read-only pods) |
| `ServiceAccount` | 2 | `09-rbac.yaml` | `banking-api-sa`, `banking-dashboard-sa` |
| `NetworkPolicy` | 7 | `10-networkpolicy.yaml` | Zero-trust: deny-all + 6 explicit allow rules |
| `DaemonSet` | 1 | `11-daemonset-fluentd.yaml` | 1 Fluentd pod per node, tolerates all taints |

---

## 🛠 Prerequisites

Ensure the following tools are installed and working **before** running anything:

| Tool | Min Version | Install | Verify |
|------|-------------|---------|--------|
| `minikube` | v1.30+ | [minikube.sigs.k8s.io](https://minikube.sigs.k8s.io/docs/start/) | `minikube version` |
| `kubectl` | v1.29+ | [kubernetes.io/docs](https://kubernetes.io/docs/tasks/tools/) | `kubectl version --client` |
| `docker` | 24+ | [docs.docker.com](https://docs.docker.com/get-docker/) | `docker --version` |
| `bash` | 4+ | pre-installed on Linux/macOS | `bash --version` |

**Cluster requirements:** 3 nodes (1 control-plane + 2 workers), minimum 4 CPUs + 8 GB RAM total.

```bash
# Start a 3-node cluster (skip if already running)
minikube start --nodes 3 --cpus 4 --memory 8192 --driver=docker

# Verify all 3 nodes are Ready
kubectl get nodes
# Expected:
# NAME           STATUS   ROLES           AGE
# minikube       Ready    control-plane   ...
# minikube-m02   Ready    <none>          ...
# minikube-m03   Ready    <none>          ...
```

---

## 🚀 Quick Start — One-Command Deploy

For a fully automated deployment across all 4 phases:

```bash
# 1. Clone the repository
git clone https://github.com/r0bert000/k8s-banking-platform.git
cd k8s-banking-platform

# 2. Make the deploy script executable
chmod +x deploy-banking.sh

# 3. Run the full deploy
./deploy-banking.sh
```

Once complete, open **http://banking.local** in your browser.

> **Note:** The script automatically detects your first worker node, applies the database node label and taint, applies all 12 YAML files in the correct dependency order, and waits for each tier to be healthy before proceeding.

---

## 📋 Step-by-Step Deployment (All 4 Phases)

### Pre-Setup: Node Labeling & Tainting

> ⚠️ **Critical — run this BEFORE the StatefulSet.** PostgreSQL uses `nodeAffinity` requiring `type=high-memory` and a `NoSchedule` taint to ensure it runs on a dedicated node, isolated from application workloads.

```bash
# Label the dedicated database node
kubectl label node minikube-m02 type=high-memory --overwrite

# Taint the node — only pods with a matching toleration will schedule here
kubectl taint nodes minikube-m02 database-only=true:NoSchedule

# Verify both were applied
kubectl describe node minikube-m02 | grep -A5 'Labels\|Taints'
```

---

### Phase 1 — It Works

**Objective:** Deploy the full application stack and verify all pods are Running, PVCs are Bound, and all endpoints respond.

#### Step 1: Namespace

```bash
kubectl apply -f k8s/00-namespace.yaml
kubectl get namespace banking
# Expected: banking   Active
```

#### Step 2: ConfigMap & Secrets

```bash
kubectl apply -f k8s/01-configmap.yaml
kubectl apply -f k8s/02-secret.yaml

kubectl describe configmap banking-config -n banking
# Expected keys: DB_HOST, DB_USER, DB_NAME, DB_PORT, LOG_LEVEL, MAX_TRANSACTION_LIMIT
```

#### Step 3: PostgreSQL Replication Scripts

> ⚠️ **Must be applied BEFORE the StatefulSet.** The StatefulSet mounts the `pg-replication-scripts` ConfigMap (containing `setup-master.sh` and `setup-slave.sh`) into `/docker-entrypoint-initdb.d/`. Without this ConfigMap, pods fail to start with a volume mount error.

```bash
kubectl apply -f k8s/08-pg-scripts.yaml
kubectl get configmap pg-replication-scripts -n banking
# Expected: pg-replication-scripts   2   ...
```

#### Step 4: PostgreSQL StatefulSet

```bash
kubectl apply -f k8s/03-postgres-statefulset.yaml

# Wait for db-0 first — the StatefulSet starts pods in order (0 → 1)
kubectl wait --for=condition=ready pod/postgres-db-0 -n banking --timeout=180s
kubectl wait --for=condition=ready pod/postgres-db-1 -n banking --timeout=180s

# Verify PVCs — must show Bound
kubectl get pvc -n banking
# Expected:
# postgres-data-postgres-db-0   Bound   5Gi   RWO
# postgres-data-postgres-db-1   Bound   5Gi   RWO

# Verify postgres is on the tainted database node
kubectl get pod postgres-db-0 -n banking -o wide
# NODE column must show: minikube-m02

# Test database connectivity
kubectl exec -it postgres-db-0 -n banking -- pg_isready -U bankuser
# Expected: /var/run/postgresql:5432 - accepting connections
```

#### Step 5: API + Dashboard Deployments

```bash
kubectl apply -f k8s/04-api-deployment.yaml
kubectl apply -f k8s/05-dashboard-deployment.yaml

# Watch pods — API pods briefly show Init:0/1 while init container waits for postgres
kubectl get pods -n banking -w

# Expected final state:
# NAME                               READY   STATUS    RESTARTS
# banking-api-xxx                    1/1     Running   0
# banking-api-yyy                    1/1     Running   0
# banking-dashboard-zzz              1/1     Running   0
# postgres-db-0                      1/1     Running   0
# postgres-db-1                      1/1     Running   0
```

#### Step 6: Services

```bash
# ClusterIP services for API (:3000) and Dashboard (:80)
kubectl apply -f k8s/06-services.yaml

# Specialized read/write split services for PostgreSQL
kubectl apply -f k8s/06-DBservices.yaml

kubectl get services -n banking
# Expected:
# banking-api-service         ClusterIP   ...   3000/TCP
# banking-dashboard-service   ClusterIP   ...   80/TCP
# postgres-svc                ClusterIP   None  5432/TCP  ← headless
# postgres-master             ClusterIP   ...   5432/TCP  ← write traffic
# postgres-replica            ClusterIP   ...   5432/TCP  ← read traffic
```

#### Phase 1 Verification

```bash
# Full stack status
kubectl get all -n banking

# Test via port-forward
kubectl port-forward svc/banking-api-service 3000:3000 -n banking &
curl http://localhost:3000/health
# Expected: {"status":"ok","version":"v1.0","timestamp":"..."}

curl http://localhost:3000/ready
# Expected: {"status":"ready","db":"connected"}

curl http://localhost:3000/api/accounts
# Expected: JSON array with 3 seeded accounts (Ahmed, Sara, Omar)
kill %1
```

---

### Phase 2 — It Is Secure

**Objective:** Enable Ingress routing, enforce RBAC least-privilege, harden containers with SecurityContext, and lock down all traffic with NetworkPolicy.

#### Ingress

```bash
# Ensure the NGINX Ingress Controller is running
kubectl get pods -n ingress-nginx

kubectl apply -f k8s/07-ingress.yaml

# Add banking.local to /etc/hosts
echo "$(minikube ip) banking.local" | sudo tee -a /etc/hosts

# Test routing
curl http://banking.local/              # → HTML dashboard
curl http://banking.local/health        # → {"status":"ok"}
curl http://banking.local/api/accounts  # → JSON accounts array
```

#### RBAC

```bash
kubectl apply -f k8s/09-rbac.yaml

# Verify least-privilege enforcement
kubectl auth can-i get pods    -n banking --as developer   # → yes
kubectl auth can-i delete pods -n banking --as developer   # → no
kubectl auth can-i get secrets -n banking --as developer   # → no
```

#### SecurityContext (already embedded in Deployment YAMLs)

| Container | `runAsUser` | `runAsNonRoot` | `readOnlyRootFilesystem` | Capabilities |
|-----------|-------------|----------------|--------------------------|--------------|
| `banking-api` | `1000` | `true` | `true` | — |
| `banking-dashboard` | `101` | — | — | `NET_BIND_SERVICE` only |
| `postgres-db` | `999` | — | — | — |

```bash
# Verify API container security context
kubectl get pod -n banking -l app=banking-api \
  -o jsonpath='{.items[0].spec.containers[0].securityContext}' | python3 -m json.tool
# Expected: runAsUser:1000, runAsNonRoot:true, readOnlyRootFilesystem:true
```

#### NetworkPolicy

> ⚠️ **Apply the entire file at once.** It contains all 7 policies. Applying `deny-all` alone will immediately block all traffic including DNS resolution, breaking every pod.

```bash
kubectl apply -f k8s/10-networkpolicy.yaml

# Verify all 7 policies
kubectl get netpol -n banking
# Expected: 7 rows

# Test: Dashboard CANNOT reach postgres (must fail — policy working)
DASH_POD=$(kubectl get pod -n banking -l app=banking-dashboard -o name | head -1)
kubectl exec -n banking $DASH_POD -- nc -zv postgres-svc 5432 --wait=3
# Expected: connection timed out ✓

# Test: API CAN reach postgres (must succeed)
API_POD=$(kubectl get pod -n banking -l app=banking-api -o name | head -1)
kubectl exec -n banking $API_POD -- nc -zv postgres-svc 5432
# Expected: open ✓
```

The 7 NetworkPolicies in `10-networkpolicy.yaml`:

| Policy | Direction | Rule |
|--------|-----------|------|
| `deny-all` | Ingress + Egress | Blocks all traffic by default |
| `allow-dns` | Egress | Allows port 53 (UDP/TCP) — essential for pod DNS resolution |
| `dashboard-allow-ingress` | Ingress | Allows traffic to dashboard on port 80 |
| `dashboard-allow-egress-to-api` | Egress | Dashboard → API on port 3000 |
| `api-allow-ingress` | Ingress | Allows traffic to API on port 3000 |
| `api-allow-egress-to-db` | Egress | API → postgres pods on port 5432 |
| `postgres-allow-ingress-from-api` | Ingress | postgres ← API only on port 5432 |
| `postgres-internal-replication` | Ingress + Egress | postgres-db-0 ↔ postgres-db-1 on port 5432 |

---

### Phase 3 — It Scales

**Objective:** Configure HPA for API auto-scaling, VPA for PostgreSQL resource recommendations, verify node scheduling constraints, and confirm all health probes pass.

```bash
# Enable metrics-server first (required for HPA)
minikube addons enable metrics-server

kubectl apply -f k8s/08-hpa-vpa.yaml

# Verify HPA
kubectl get hpa -n banking
# Expected: banking-api-hpa   Deployment/banking-api   <x>%/60%   2   10   2

# Note: TARGETS may show <unknown> for ~2 minutes while metrics-server gathers data
kubectl top pods -n banking   # wait until this returns data

# Verify VPA (recommendation-only, will not restart pods)
kubectl get vpa -n banking
# Expected: postgres-db-vpa   Off
```

#### Health Probe Configuration

| Container | Probe | Method | Endpoint | Timing |
|-----------|-------|--------|----------|--------|
| `banking-api` | Startup | HTTP GET | `/health` | 10 × 5s = 50s max window |
| `banking-api` | Readiness | HTTP GET | `/ready` | every 10s — verifies DB connected |
| `banking-api` | Liveness | HTTP GET | `/health` | every 20s |
| `banking-dashboard` | Readiness | HTTP GET | `/` | every 5s |
| `banking-dashboard` | Liveness | HTTP GET | `/` | every 10s |
| `postgres-db` | Startup | exec | `pg_isready -U bankuser` | 20 × 5s = 100s max |
| `postgres-db` | Readiness | exec | `pg_isready -U bankuser` | every 10s |
| `postgres-db` | Liveness | exec | `pg_isready -U bankuser` | every 30s |

```bash
# Verify probe events on API pod
kubectl describe pod -n banking -l app=banking-api | grep -A10 'Liveness\|Readiness\|Startup'

# Verify scheduling constraints
kubectl get pods -n banking -o wide
# postgres-db-0 and postgres-db-1 → NODE must be minikube-m02 (tainted node)
# banking-api pods              → NODE must be minikube-m03 (NOT the DB node)
```

---

### Phase 4 — It Survives

**Objective:** Prove data persistence through pod deletion, demonstrate zero-downtime rolling updates, rollback capability, and DaemonSet log collection on every node.

#### Fluentd DaemonSet

```bash
kubectl apply -f k8s/11-daemonset-fluentd.yaml

kubectl get daemonset -n banking
# Expected: DESIRED=2, CURRENT=2, READY=2

# Verify one pod per node (including the tainted database node — thanks to tolerations: Exists)
kubectl get pods -n banking -l app=fluentd -o wide
# Expected: one pod on minikube-m02, one on minikube-m03
```

#### Data Persistence Demo

```bash
# Step 1: Verify data exists in the database
kubectl exec -it postgres-db-0 -n banking -- \
  psql -U bankuser -d banking_db -c 'SELECT * FROM accounts;'

# Step 2: Simulate catastrophic pod failure
kubectl delete pod postgres-db-0 -n banking

# Step 3: Watch StatefulSet self-heal with the SAME name and SAME PVC
kubectl get pods -n banking -w
# Expected: postgres-db-0: Terminating → ContainerCreating → Running

# Step 4: Data MUST survive pod deletion (PVC is decoupled from pod lifecycle)
kubectl exec -it postgres-db-0 -n banking -- \
  psql -U bankuser -d banking_db -c 'SELECT * FROM accounts;'
# Expected: identical rows as Step 1
```

#### Rolling Update & Rollback (Zero Downtime)

```bash
# Show current version
kubectl describe deployment banking-api -n banking | grep Image
# Expected: r0bert000/banking-api:v1.0

# Trigger rolling update to v1.1
kubectl set image deployment/banking-api \
  banking-api=r0bert000/banking-api:v1.1 -n banking

# Watch: old pods remain RUNNING until new pods pass readiness probe
kubectl rollout status deployment/banking-api -n banking

# Show deployment history
kubectl rollout history deployment/banking-api -n banking

# Rollback to v1.0 (instant, no downtime)
kubectl rollout undo deployment/banking-api -n banking
kubectl describe deployment banking-api -n banking | grep Image
# Expected: r0bert000/banking-api:v1.0
```

---

## 🔌 API Endpoint Reference

All endpoints are accessible via `http://banking.local` through the Ingress.

| Method | Path | Description | Response |
|--------|------|-------------|----------|
| `GET` | `/health` | Liveness check — process alive | `{"status":"ok","version":"v1.0"}` |
| `GET` | `/ready` | Readiness check — DB connected | `{"status":"ready","db":"connected"}` |
| `GET` | `/api/stats` | Dashboard statistics | `{total_accounts, total_balance, total_transactions}` |
| `GET` | `/api/accounts` | List all accounts (newest first) | Array of account objects |
| `POST` | `/api/accounts` | Open a new account | Created account object |
| `GET` | `/api/transactions` | Last 50 transactions with owner names | Array of transaction objects |
| `POST` | `/api/transactions` | Transfer money between accounts | Created transaction object |

**Example — Open an account:**
```bash
curl -X POST http://banking.local/api/accounts \
  -H 'Content-Type: application/json' \
  -d '{"owner": "Mohamed Ali", "initial_balance": 5000}'
```

**Example — Transfer money:**
```bash
curl -X POST http://banking.local/api/transactions \
  -H 'Content-Type: application/json' \
  -d '{"from_account": 1, "to_account": 2, "amount": 500, "note": "Rent"}'
```

**Transaction business rules enforced by the API:**
- Source and destination accounts must be different
- Amount must be positive and not exceed `MAX_TRANSACTION_LIMIT` (default: `10000` EGP)
- Source account must have sufficient balance
- All transfers are atomic using PostgreSQL transactions (`BEGIN` / `COMMIT` / `ROLLBACK`)

---

## ⚙️ Environment Variables & Configuration

### ConfigMap (`01-configmap.yaml`) — Non-sensitive

| Key | Value | Used By |
|-----|-------|---------|
| `DB_HOST` | `postgres-db-0.postgres-svc.banking.svc.cluster.local` | API — database connection |
| `DB_USER` | `bankuser` | API — database auth |
| `DB_NAME` | `banking_db` | API — database selection |
| `DB_PORT` | `5432` | API — database port |
| `LOG_LEVEL` | `debug` | API — logging verbosity |
| `MAX_TRANSACTION_LIMIT` | `10000` | API — transaction cap in EGP |
| `POSTGRES_DB` | `banking_db` | PostgreSQL init — creates the database |

### Secret (`02-secret.yaml`) — Sensitive (base64-encoded)

| Key | Decoded Value | Used By |
|-----|---------------|---------|
| `DB_PASSWORD` | `password123` | API + PostgreSQL — database password |
| `JWT_SECRET` | `my-super-secret-key` | API — JWT token signing |
| `dockerhub-token` | Docker Hub PAT | Image pull authentication |

> **Production note:** Never commit real secrets to source control. Use `kubectl create secret generic` with `--from-env-file` or integrate with a secrets manager (HashiCorp Vault, AWS Secrets Manager) for real workloads.

---

## 🔒 Security Architecture

### Zero-Trust Network Model

The network starts with a **deny-all** posture. Every communication path requires an explicit `NetworkPolicy` allow rule with pod label selectors. There is no implicit trust between any two pods.

```
Internet → [Ingress Controller] → Dashboard pod (:80)
Internet → [Ingress Controller] → API pod (:3000)
Dashboard pod → API pod (:3000)          ← explicit allow
API pod → postgres-db pod (:5432)        ← explicit allow
postgres-db-0 ↔ postgres-db-1 (:5432)   ← explicit allow (WAL replication)
All pods → kube-dns (:53)               ← explicit allow (DNS resolution)
Dashboard pod → postgres-db pod          ← BLOCKED ✗
```

### RBAC — Principle of Least Privilege

| Subject | Object Type | Verbs Allowed | Verbs Blocked |
|---------|-------------|---------------|----------------|
| `developer` (User) | `pods` | `get`, `list`, `watch` | `create`, `delete`, `update`, `patch` |
| `developer` (User) | `secrets` | — | all |
| `banking-api-sa` | ServiceAccount | — | no K8s API access granted |
| `banking-dashboard-sa` | ServiceAccount | — | no K8s API access granted |

### Container Hardening (SecurityContext)

Every container runs as a **non-root user**. The API additionally uses a **read-only root filesystem**, preventing any malware from writing to disk.

---

## 🧠 Key Architectural Decisions (The "Why")

### 1. StatefulSet for PostgreSQL (not a Deployment)

A `Deployment` gives pods random names and shared or ephemeral storage. PostgreSQL requires stable pod identity for replication and stable storage for data persistence. The `StatefulSet` guarantees:

| Feature | Deployment | StatefulSet |
|---------|------------|-------------|
| Pod names | `pod-abc12` (random) | `postgres-db-0`, `postgres-db-1` (stable) |
| DNS | Not stable | `postgres-db-0.postgres-svc.banking.svc.cluster.local` |
| Storage | Shared or none | Individual PVC per pod (`postgres-data-postgres-db-{0,1}`) |
| Start order | All at once | Ordered: `db-0` first, then `db-1` |
| Stop order | Random | Reverse: `db-1` first, then `db-0` |

### 2. Read/Write Service Segregation (The Critical Fix)

**The problem:** A standard `Service` for a StatefulSet load-balances randomly across all pods. When the API sent an `INSERT` to `postgres-db-1` (the Replica), PostgreSQL rejected it with `ERROR: cannot execute INSERT in a read-only transaction`.

**The solution (`06-DBservices.yaml`):** Two specialized services using the `statefulset.kubernetes.io/pod-name` selector to pin traffic to a specific pod:

```yaml
# postgres-master → ALWAYS postgres-db-0 (Primary — accepts writes)
selector:
  statefulset.kubernetes.io/pod-name: postgres-db-0

# postgres-replica → ALWAYS postgres-db-1 (Replica — read-only)
selector:
  statefulset.kubernetes.io/pod-name: postgres-db-1
```

By setting `DB_HOST: postgres-db-0.postgres-svc.banking.svc.cluster.local` in the ConfigMap, the API always connects directly to the Primary, guaranteeing 100% write success while keeping the Replica available for HA failover.

### 3. Init Container Pattern — Dependency Ordering

The API `Deployment` uses an init container that runs:
```bash
until nc -z postgres-svc 5432; do echo "Waiting..."; sleep 2; done
```
This blocks the API process from starting until PostgreSQL is accepting connections, preventing connection-refused errors and crash loops during cluster startup. The init container exits with code `0` once the port is open, then Kubernetes starts the main container.

### 4. Node Isolation for PostgreSQL

PostgreSQL is isolated to a dedicated worker node using two mechanisms that work together:

- **`nodeAffinity`** (required): `type: high-memory` — the pod will only be scheduled on nodes with this label.
- **`taint + toleration`**: `database-only=true:NoSchedule` — the node rejects all pods *except* those that explicitly tolerate this taint. PostgreSQL and Fluentd carry this toleration; the API does not.

This prevents application workloads from consuming the database node's memory and CPU, ensuring predictable database performance.

### 5. DaemonSet for Fluentd with `tolerations: Exists`

A DaemonSet normally respects node taints and won't schedule on tainted nodes. By using `tolerations: - operator: Exists` (tolerates **all** taints unconditionally), Fluentd is guaranteed to run on every node in the cluster — including the tainted database node — ensuring no log lines are ever missed.

### 6. HPA Stabilization Window

The HPA is configured to scale up aggressively when CPU exceeds 60%, but Kubernetes enforces a built-in 5-minute stabilization window before scaling down. This prevents "thrashing" — a situation where pods are rapidly created and destroyed as traffic fluctuates around the threshold.

### 7. Multi-Stage Docker Build (API)

The API `Dockerfile` uses a two-stage build:
- **Stage 1 (builder):** Full Node 18 Alpine with all dev tools — installs npm dependencies.
- **Stage 2 (production):** Clean Node 18 Alpine — copies only the built app, no build tools.

Result: the production image contains no compilers, no dev tools, and no build-time artifacts, significantly reducing the attack surface.

---

## 🧪 Testing & Validation Playbook

### 1. HPA Stress Test (Trigger Auto-Scaling)

```bash
# Inject the app=banking-dashboard label to bypass NetworkPolicy
# (dashboard pods are allowed to reach the API)
kubectl run -i --tty load-generator \
  --rm \
  --image=busybox:1.28 \
  --labels="app=banking-dashboard" \
  -n banking \
  --restart=Never \
  -- /bin/sh -c "while true; do wget -q -O- http://banking-api-service:3000/api/accounts; done"

# In a separate terminal — watch the HPA scale from 2 → 10 replicas
kubectl get hpa banking-api-hpa -n banking --watch
```

> **Why the label?** The `deny-all` NetworkPolicy blocks the load-generator pod by default. Adding `app=banking-dashboard` grants it the same network access as the dashboard pod, allowing it to reach the API on port 3000.

### 2. Chaos Engineering — Database Failure

```bash
# Simulate master database pod failure
kubectl delete pod postgres-db-0 -n banking

# Watch StatefulSet self-heal: same name, same PVC
kubectl get pods -n banking -w

# Verify data survived
kubectl exec -it postgres-db-0 -n banking -- \
  psql -U bankuser -d banking_db -c 'SELECT * FROM accounts;'
```

### 3. RBAC Validation

```bash
kubectl auth can-i get    pods    -n banking --as developer   # → yes
kubectl auth can-i delete pods    -n banking --as developer   # → no
kubectl auth can-i get    secrets -n banking --as developer   # → no
kubectl auth can-i create pods    -n banking --as developer   # → no
```

### 4. NetworkPolicy Enforcement

```bash
# Dashboard CANNOT reach the database directly (must time out)
DASH_POD=$(kubectl get pod -n banking -l app=banking-dashboard -o name | head -1)
kubectl exec -n banking $DASH_POD -- nc -zv -w 3 postgres-svc 5432
# Expected: nc: postgres-svc: Connection timed out ✓

# API CAN reach the database
API_POD=$(kubectl get pod -n banking -l app=banking-api -o name | head -1)
kubectl exec -n banking $API_POD -- nc -zv postgres-svc 5432
# Expected: open ✓
```

### 5. End-to-End Browser Validation

| Step | Action | What to Verify |
|------|--------|----------------|
| 1 | Open `http://banking.local` | HTML dashboard loads, API status dot is green |
| 2 | Fill "Open Account" form | New account appears in the table after submit |
| 3 | Fill "Transfer Money" form | Transfer appears in recent transactions |
| 4 | Wait 10 seconds | Dashboard auto-refreshes, stats update |
| 5 | Visit `http://banking.local/api/accounts` | Ingress routes `/api/*` to API, returns JSON |

---

## ⚠️ Troubleshooting & Common Pitfalls

| Symptom | Root Cause | Exact Fix |
|---------|------------|-----------|
| **`ImagePullBackOff`** on API or Dashboard pods | Docker Hub username still set to `YOUR_DOCKERHUB_USERNAME` in YAML | `sed -i 's/YOUR_DOCKERHUB_USERNAME/REALNAME/g' k8s/04-api-deployment.yaml k8s/05-dashboard-deployment.yaml` |
| **StatefulSet pods `Pending`** — no matching node | `nodeAffinity` requires `type=high-memory` but the label hasn't been applied | `kubectl label node minikube-m02 type=high-memory` |
| **StatefulSet pods fail to start** — volume mount error | `pg-replication-scripts` ConfigMap not applied before the StatefulSet | `kubectl apply -f k8s/08-pg-scripts.yaml` then `kubectl rollout restart statefulset postgres-db -n banking` |
| **API pods stuck in `Init:0/1`** | Init container `wait-for-db` cannot reach `postgres-svc:5432` — postgres not ready yet | Wait 60–120s for postgres startup probes to pass, or check: `kubectl logs postgres-db-0 -n banking` |
| **`PVC Pending`** | No `StorageClass` provisioner available | `minikube addons enable default-storageclass storage-provisioner` |
| **404 on `banking.local`** | NGINX Ingress Controller not running, or `/etc/hosts` entry missing | `minikube addons enable ingress` then `echo "$(minikube ip) banking.local" \| sudo tee -a /etc/hosts` |
| **`/ready` returns 503** | API cannot connect to the database — DB still initializing | Wait 30–60s. Check: `kubectl logs -l app=banking-api -n banking` |
| **HPA shows `<unknown>/60%`** | `metrics-server` not running or not yet scraped | `minikube addons enable metrics-server` then wait 2 minutes. Check: `kubectl top pods -n banking` |
| **Database `ReadOnly` error in UI** | API is hitting the Replica (`postgres-db-1`) for write operations | Ensure `DB_HOST` in ConfigMap points to `postgres-db-0.postgres-svc.banking.svc.cluster.local` and restart the API: `kubectl rollout restart deployment banking-api -n banking` |
| **`wget: bad address` in load test** | Load-generator pod blocked by `deny-all` NetworkPolicy — DNS fails | Add `--labels="app=banking-dashboard"` to the `kubectl run` command |
| **All traffic blocked after NetworkPolicy** | Applied `deny-all` alone without the 6 allow rules | `kubectl apply -f k8s/10-networkpolicy.yaml` (the file contains all 7 — apply the whole file) |
| **Fluentd not running on database node** | DaemonSet missing the universal toleration | Verify `11-daemonset-fluentd.yaml` has `tolerations: - operator: Exists` |

---

## 💻 Useful Operations Commands

### Cluster Health

```bash
# Full namespace overview
kubectl get all,pvc,netpol,hpa,vpa -n banking

# Node placement of all pods
kubectl get pods -n banking -o wide

# Resource consumption
kubectl top pods -n banking
kubectl top nodes
```

### Logs

```bash
# API logs (follow, last 50 lines)
kubectl logs -l app=banking-api -n banking --tail=50 -f

# Specific pod logs (including previous crash)
kubectl logs <pod-name> -n banking --previous

# Fluentd collected logs from all nodes
kubectl logs -l app=fluentd -n banking --tail=30

# PostgreSQL logs
kubectl logs postgres-db-0 -n banking
```

### Debugging

```bash
# Describe any resource for full event log
kubectl describe pod <pod-name> -n banking
kubectl describe deployment banking-api -n banking

# Interactive shell into any pod
kubectl exec -it <pod-name> -n banking -- sh

# Test database query directly
kubectl exec -it postgres-db-0 -n banking -- \
  psql -U bankuser -d banking_db -c 'SELECT * FROM accounts;'

# Check init container completion
kubectl describe pod -n banking -l app=banking-api | grep -A5 'Init Containers'
# Expected: State: Terminated, Reason: Completed, Exit Code: 0

# Check RBAC permissions
kubectl auth can-i <verb> <resource> -n banking --as <user>
```

### Scaling & Updates

```bash
# Manual scale (overrides HPA temporarily)
kubectl scale deployment banking-api --replicas=5 -n banking

# Restart a deployment (picks up new ConfigMap values)
kubectl rollout restart deployment banking-api -n banking
kubectl rollout restart deployment banking-dashboard -n banking

# Rolling update
kubectl set image deployment/banking-api \
  banking-api=r0bert000/banking-api:v1.1 -n banking

# Check update status
kubectl rollout status deployment/banking-api -n banking

# View rollout history
kubectl rollout history deployment/banking-api -n banking

# Rollback to previous version
kubectl rollout undo deployment/banking-api -n banking
```

### Complete Teardown

```bash
# Delete all resources in the namespace
kubectl delete namespace banking

# Stop the cluster
minikube stop

# Destroy the cluster entirely (removes all data)
minikube delete
```

---

<div align="center">

**Banking Platform on Kubernetes** — Capstone Project

*Demonstrating every major Kubernetes object in a real, production-grade banking application.*

Built with ☕ and a lot of `kubectl describe pod` commands.

</div>
