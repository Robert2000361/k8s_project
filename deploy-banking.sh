#!/bin/bash
# =============================================================================
# Banking Platform on Kubernetes — Full Deploy Script
# Covers Phase 1 → Phase 2 → Phase 3 → Phase 4
# =============================================================================
set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
USERNAME="r0bert000"          # Docker Hub username (already baked into YAML files)
NAMESPACE="banking"
DB_NODE_LABEL="type=high-memory"
DB_TAINT_KEY="database-only"
DB_TAINT_VALUE="true"
DB_TAINT_EFFECT="NoSchedule"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()    { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "\n${BLUE}════════════════════════════════════════${NC}"; echo -e "${BLUE}  $1${NC}"; echo -e "${BLUE}════════════════════════════════════════${NC}"; }

# ── Guard: check required tools ───────────────────────────────────────────────
log_section "Pre-flight Checks"
for tool in kubectl minikube docker; do
  if ! command -v "$tool" &>/dev/null; then
    log_error "'$tool' is not installed or not in PATH. Aborting."
    exit 1
  fi
  log_info "$tool found: $(command -v $tool)"
done

# ── 1. Cluster Setup ──────────────────────────────────────────────────────────
log_section "[1/12] Starting Minikube (3 nodes)"
if minikube status --format='{{.Host}}' 2>/dev/null | grep -q "Running"; then
  log_warn "Minikube is already running — skipping start."
else
  minikube start --nodes 3 --cpus 4 --memory 8192 --driver=docker
fi

log_info "Enabling ingress addon..."
minikube addons enable ingress

log_info "Enabling metrics-server addon (required for HPA)..."
minikube addons enable metrics-server

log_info "Verifying nodes..."
kubectl get nodes

# ── 2. Node Labeling & Tainting ───────────────────────────────────────────────
# CRITICAL: Must happen BEFORE StatefulSet is applied.
# The postgres StatefulSet has nodeAffinity requiring label: type=high-memory
# and a toleration for taint: database-only=true:NoSchedule
log_section "[2/12] Labeling & Tainting Database Node"

# Detect the first worker node dynamically (not the control-plane)
DB_NODE=$(kubectl get nodes --no-headers \
  | grep -v "control-plane\|master" \
  | awk 'NR==1{print $1}')

if [[ -z "$DB_NODE" ]]; then
  log_error "No worker node found. Make sure minikube started with --nodes 3."
  exit 1
fi

log_info "Targeting node '$DB_NODE' as the dedicated database node."

# Label the node (--overwrite is safe if already labeled)
kubectl label node "$DB_NODE" type=high-memory --overwrite
log_info "Label applied: type=high-memory → $DB_NODE"

# Taint the node — only pods with matching toleration will schedule here
# The postgres StatefulSet and fluentd DaemonSet carry this toleration
if kubectl describe node "$DB_NODE" | grep -q "${DB_TAINT_KEY}=${DB_TAINT_VALUE}:${DB_TAINT_EFFECT}"; then
  log_warn "Taint already exists on $DB_NODE — skipping."
else
  kubectl taint nodes "$DB_NODE" "${DB_TAINT_KEY}=${DB_TAINT_VALUE}:${DB_TAINT_EFFECT}"
  log_info "Taint applied: database-only=true:NoSchedule → $DB_NODE"
fi

# Verify
log_info "Node configuration summary:"
kubectl describe node "$DB_NODE" | grep -A5 'Labels\|Taints' | head -20

# ── 3. Docker Images ──────────────────────────────────────────────────────────
log_section "[3/12] Docker Images"
# Images are already pushed to Docker Hub as r0bert000/banking-api:v1.0
# and r0bert000/banking-dashboard:v1.0
# Uncomment the block below ONLY if you need to rebuild and re-push:

# log_info "Building and pushing banking-api:v1.0..."
# docker build -t "${USERNAME}/banking-api:v1.0" ./app/banking-api
# docker push "${USERNAME}/banking-api:v1.0"
#
# log_info "Building and pushing banking-dashboard:v1.0..."
# docker build -t "${USERNAME}/banking-dashboard:v1.0" ./app/banking-dashboard
# docker push "${USERNAME}/banking-dashboard:v1.0"
#
# # Also build v1.1 for Phase 4 Rolling Update demo
# log_info "Building banking-api:v1.1 for rolling update demo..."
# docker build -t "${USERNAME}/banking-api:v1.1" ./app/banking-api
# docker push "${USERNAME}/banking-api:v1.1"

log_info "Using pre-pushed images: ${USERNAME}/banking-api:v1.0 & ${USERNAME}/banking-dashboard:v1.0"

# ── 4. YAML Username Injection ────────────────────────────────────────────────
# NOTE: The YAML files already have r0bert000 hardcoded.
# This step is a safety net in case placeholder text was re-introduced.
log_section "[4/12] Verifying Docker Hub Username in YAML Files"
for yaml_file in k8s/04-api-deployment.yaml k8s/05-dashboard-deployment.yaml; do
  if grep -q "YOUR_DOCKERHUB_USERNAME" "$yaml_file" 2>/dev/null; then
    log_warn "Found placeholder in $yaml_file — replacing with '${USERNAME}'..."
    sed -i "s/YOUR_DOCKERHUB_USERNAME/${USERNAME}/g" "$yaml_file"
  else
    log_info "$yaml_file: username is correctly set."
  fi
done

# ── 5. Phase 1 — Core Stack ───────────────────────────────────────────────────
log_section "[5/12] Phase 1 — Deploying Core Stack"

# 5a. Namespace — everything lives here
log_info "Applying namespace..."
kubectl apply -f k8s/00-namespace.yaml

# 5b. ConfigMap — non-sensitive config (DB_HOST, DB_PORT, LOG_LEVEL, etc.)
log_info "Applying ConfigMap..."
kubectl apply -f k8s/01-configmap.yaml

# 5c. Secrets — DB_PASSWORD, JWT_SECRET, dockerhub-token (Opaque, base64-encoded)
log_info "Applying Secrets..."
kubectl apply -f k8s/02-secret.yaml

# 5d. Replication scripts ConfigMap — MUST be applied BEFORE the StatefulSet.
#     03-postgres-statefulset.yaml references the 'pg-replication-scripts' ConfigMap
#     (setup-master.sh + setup-slave.sh mounted into /docker-entrypoint-initdb.d/).
#     Without this, the StatefulSet pods will fail to start (volume mount error).
log_info "Applying PostgreSQL replication scripts ConfigMap (08-pg-scripts.yaml)..."
kubectl apply -f k8s/08-pg-scripts.yaml

# 5e. PostgreSQL StatefulSet — includes headless Service (postgres-svc)
#     - 2 replicas: postgres-db-0 (master) + postgres-db-1 (replica)
#     - NodeAffinity requires type=high-memory label (applied in step 2)
#     - Toleration for database-only:NoSchedule taint
#     - PVC template: 5Gi ReadWriteOnce per pod
#     - initContainer 'fix-permissions' + 3 health probes (startup/readiness/liveness)
log_info "Applying PostgreSQL StatefulSet..."
kubectl apply -f k8s/03-postgres-statefulset.yaml

log_info "Waiting for postgres-db-0 to be Ready (may take 60-120s for startup probe + init)..."
kubectl wait --for=condition=ready pod/postgres-db-0 \
  -n "${NAMESPACE}" \
  --timeout=180s

log_info "postgres-db-0 is Ready. Waiting for postgres-db-1..."
kubectl wait --for=condition=ready pod/postgres-db-1 \
  -n "${NAMESPACE}" \
  --timeout=180s

log_info "Both PostgreSQL pods are Running:"
kubectl get pods -n "${NAMESPACE}" -l app=postgres-db -o wide

# 5f. API Deployment — 2 replicas, init container waits for postgres-svc:5432
log_info "Applying Banking API Deployment..."
kubectl apply -f k8s/04-api-deployment.yaml

# 5g. Dashboard Deployment — 1 replica, nginx serving the SPA
log_info "Applying Banking Dashboard Deployment..."
kubectl apply -f k8s/05-dashboard-deployment.yaml

# 5h. ClusterIP Services — banking-api-service:3000 and banking-dashboard-service:80
log_info "Applying ClusterIP Services..."
kubectl apply -f k8s/06-services.yaml

# 5i. Specialized PostgreSQL Services — postgres-master (write) + postgres-replica (read)
#     These use statefulset.kubernetes.io/pod-name selector to pin traffic to specific pods:
#       postgres-master  → postgres-db-0 (read/write)
#       postgres-replica → postgres-db-1 (read-only, load offload)
#     Correct filename: 06-DBservices.yaml (NOT 06-postgres-specialized-svcs.yaml)
log_info "Applying specialized PostgreSQL read/write services..."
kubectl apply -f k8s/06-DBservices.yaml

# ── 6. Phase 2 — Security ─────────────────────────────────────────────────────
log_section "[6/12] Phase 2 — Applying Security Layers"

# 6a. Ingress — NGINX routes: banking.local/ → dashboard, banking.local/api/* → API
log_info "Applying Ingress..."
kubectl apply -f k8s/07-ingress.yaml

# 6b. RBAC — ServiceAccounts, developer Role (read-only pods), RoleBindings
log_info "Applying RBAC..."
kubectl apply -f k8s/09-rbac.yaml

# 6c. NetworkPolicy — CRITICAL: apply the full file with ALL 7 policies at once.
#     The file contains: deny-all + allow-dns + 5 specific allow rules.
#     Applying deny-all alone blocks all traffic immediately.
log_info "Applying NetworkPolicies (all 7 in one apply)..."
kubectl apply -f k8s/10-networkpolicy.yaml

log_info "Verifying 7 NetworkPolicies are present..."
NETPOL_COUNT=$(kubectl get netpol -n "${NAMESPACE}" --no-headers | wc -l)
if [[ "$NETPOL_COUNT" -lt 7 ]]; then
  log_warn "Expected 7 NetworkPolicies, found ${NETPOL_COUNT}. Check 10-networkpolicy.yaml."
else
  log_info "All ${NETPOL_COUNT} NetworkPolicies applied successfully."
fi

# ── 7. Phase 3 — Scaling ──────────────────────────────────────────────────────
log_section "[7/12] Phase 3 — Configuring Autoscaling"
# HPA: banking-api — minReplicas:2, maxReplicas:10, CPU target:60%
# VPA: postgres-db — updateMode:Off (recommendations only, no auto-eviction)
log_info "Applying HPA and VPA..."
kubectl apply -f k8s/08-hpa-vpa.yaml

log_info "HPA status (TARGETS may show '<unknown>' for ~2 min until metrics-server scrapes):"
kubectl get hpa -n "${NAMESPACE}" || true

# ── 8. Phase 4 — Reliability ──────────────────────────────────────────────────
log_section "[8/12] Phase 4 — Deploying DaemonSet (Fluentd)"
# Fluentd DaemonSet: 1 pod per node, reads /var/log/containers/*banking*.log
# Uses 'tolerations: - operator: Exists' to also run on the tainted database node
log_info "Applying Fluentd DaemonSet..."
kubectl apply -f k8s/11-daemonset-fluentd.yaml

# ── 9. /etc/hosts Update ──────────────────────────────────────────────────────
log_section "[9/12] Updating /etc/hosts for banking.local"
MINIKUBE_IP=$(minikube ip)
if grep -q 'banking.local' /etc/hosts; then
  log_warn "'banking.local' already in /etc/hosts — skipping."
else
  echo "${MINIKUBE_IP} banking.local" | sudo tee -a /etc/hosts
  log_info "Added: ${MINIKUBE_IP} banking.local"
fi

# ── 10. Wait for API and Dashboard to be Ready ────────────────────────────────
log_section "[10/12] Waiting for API & Dashboard Pods to be Ready"
log_info "Waiting for banking-api deployment rollout..."
kubectl rollout status deployment/banking-api -n "${NAMESPACE}" --timeout=120s

log_info "Waiting for banking-dashboard deployment rollout..."
kubectl rollout status deployment/banking-dashboard -n "${NAMESPACE}" --timeout=60s

# ── 11. Final Status ──────────────────────────────────────────────────────────
log_section "[11/12] Final Cluster Status"

echo ""
log_info "All Pods:"
kubectl get pods -n "${NAMESPACE}" -o wide

echo ""
log_info "Services:"
kubectl get services -n "${NAMESPACE}"

echo ""
log_info "PersistentVolumeClaims:"
kubectl get pvc -n "${NAMESPACE}"

echo ""
log_info "Ingress:"
kubectl get ingress -n "${NAMESPACE}"

echo ""
log_info "HPA:"
kubectl get hpa -n "${NAMESPACE}"

echo ""
log_info "VPA:"
kubectl get vpa -n "${NAMESPACE}" 2>/dev/null || log_warn "VPA CRD not installed — skipping."

echo ""
log_info "NetworkPolicies:"
kubectl get netpol -n "${NAMESPACE}"

echo ""
log_info "DaemonSet:"
kubectl get daemonset -n "${NAMESPACE}"

# ── 12. RBAC Smoke Test ───────────────────────────────────────────────────────
log_section "[12/12] RBAC Smoke Test"
log_info "Can developer GET pods?    $(kubectl auth can-i get pods -n ${NAMESPACE} --as developer)"
log_info "Can developer DELETE pods? $(kubectl auth can-i delete pods -n ${NAMESPACE} --as developer)"
log_info "Can developer GET secrets? $(kubectl auth can-i get secrets -n ${NAMESPACE} --as developer)"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅  Banking Platform deployed successfully!     ║${NC}"
echo -e "${GREEN}║                                                  ║${NC}"
echo -e "${GREEN}║  Dashboard: http://banking.local                 ║${NC}"
echo -e "${GREEN}║  API Health: http://banking.local/health         ║${NC}"
echo -e "${GREEN}║  API Accounts: http://banking.local/api/accounts ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
log_info "Quick test: curl -s http://banking.local/health | python3 -m json.tool"
