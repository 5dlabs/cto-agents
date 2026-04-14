---
name: solana-node-operations
version: 1.0.0
description: >
  Solana validator and RPC node operations — Agave builds, Kubernetes deployment,
  bare-metal provisioning, Yellowstone gRPC, monitoring, and low-latency tuning.
  Covers the full lifecycle from hardware selection through production cutover.
---

# Solana Node Operations

Production-grade Solana node deployment, monitoring, and operations for the CTO platform.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│  Bare Metal (Latitude.sh / Cherry Servers)              │
│                                                         │
│  ┌─────────────────────────────────────────────────┐    │
│  │  Talos Linux (immutable, API-driven)             │    │
│  │                                                  │    │
│  │  ┌──────────────────────┐  ┌──────────────────┐ │    │
│  │  │  agave-validator     │  │  K8s Services    │ │    │
│  │  │  ├─ RPC :8899        │  │  ├─ Trading bots │ │    │
│  │  │  ├─ WS  :8900        │  │  ├─ DEX indexer  │ │    │
│  │  │  ├─ Gossip :8001     │  │  ├─ QuestDB      │ │    │
│  │  │  └─ gRPC :10000      │  │  ├─ Prometheus   │ │    │
│  │  │     (Yellowstone)     │  │  └─ Grafana      │ │    │
│  │  └──────────────────────┘  └──────────────────┘ │    │
│  │         hostNetwork: true   Cilium eBPF          │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

**Key design decision:** The Agave validator runs with `hostNetwork: true` on a dedicated
bare-metal node. Trading pods on the same Cilium network get sub-microsecond RPC latency
via eBPF socket-level load balancing (bypasses TCP stack entirely).

---

## 1. Hardware Requirements

### Solana RPC Node (Mainnet)

| Resource | Minimum | Recommended | Notes |
|----------|---------|-------------|-------|
| CPU | 16 cores | 32 cores (AMD EPYC) | Zen 4/5 for AVX-512 + SHA-NI |
| RAM | 256 GB | 512–1024 GB | Accounts index lives in memory |
| Storage | 2× NVMe | 4× NVMe | Separate: ledger, accounts, snapshots |
| Network | 1 Gbps | 10 Gbps | UDP gossip is bandwidth-hungry |
| Hugepages | 4 Gi (2Mi pages) | 4 Gi | Pre-allocated via kernel args |

### Bare-Metal Providers

| Provider | Plan | Specs | Cost |
|----------|------|-------|------|
| **Latitude.sh** | `m3-large-x86` | 1024 GB RAM, NVMe | ~$2.57/hr |
| **Cherry Servers** | Gen5 | 256+ GB RAM, NVMe | Variable |
| **OVH** | High-memory | 512 GB RAM | Variable |

Provisioning is automated via `crates/metal/` — supports Latitude, Cherry, Vultr,
Scaleway, Hetzner, OVH, DigitalOcean, and on-prem via the `Provider` trait.

---

## 2. Building Agave from Source

Custom Agave build optimized for AMD EPYC (Zen 4/5) — enables AVX-512 + SHA-NI
for 10-30% improvement on crypto hot paths.

```dockerfile
# Dockerfile.agave — build optimized validator binary
FROM rust:1.86.0-slim-bookworm AS build

RUN apt-get update && apt-get install -y \
    git clang cmake pkg-config libssl-dev \
    protobuf-compiler libudev-dev \
    && rm -rf /var/lib/apt/lists/*

ARG AGAVE_VERSION=v2.2.20

RUN git clone --depth 1 --branch $AGAVE_VERSION \
    https://github.com/anza-xyz/agave.git /agave

WORKDIR /agave

# Target znver4 (Zen 4) — closest stable LLVM target to Zen 5
# Enables: AVX-512, SHA-NI, VAES, VPCLMULQDQ
ENV RUSTFLAGS="-C target-cpu=znver4"

RUN ./scripts/cargo-install-all.sh --validator-only .
RUN strip /agave/bin/*

# --- Runtime ---
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates curl jq \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /agave/bin/ /usr/local/bin/

# jemalloc tuning for Solana's allocation patterns
ENV MALLOC_CONF="background_thread:true,metadata_thp:always,dirty_decay_ms:3000"
ENTRYPOINT ["agave-validator"]
```

```bash
# Build and push
docker build --build-arg AGAVE_VERSION=v2.2.20 \
  -t ghcr.io/5dlabs/agave:v2.2.20-znver4 \
  -f Dockerfile.agave .
docker push ghcr.io/5dlabs/agave:v2.2.20-znver4
```

---

## 3. Yellowstone gRPC Plugin

Real-time gRPC streaming from the validator via Yellowstone geyser plugin.

```dockerfile
# Dockerfile.yellowstone-grpc — build geyser plugin .so
FROM rust:1.86-slim-bookworm AS build
RUN apt-get update && apt-get install -y \
    git clang cmake pkg-config libssl-dev protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*

ARG YELLOWSTONE_VERSION=v12.2.0+solana.3.1.10

RUN git clone --depth 1 --branch "${YELLOWSTONE_VERSION}" \
    https://github.com/rpcpool/yellowstone-grpc.git /yellowstone-grpc
WORKDIR /yellowstone-grpc
RUN cargo build --release --package yellowstone-grpc-geyser
RUN mkdir -p /output \
    && cp target/release/libyellowstone_grpc_geyser.so /output/ \
    && strip /output/libyellowstone_grpc_geyser.so

FROM scratch
COPY --from=build /output/libyellowstone_grpc_geyser.so /output/
```

```bash
# Extract and deploy .so to the Solana node
docker create --name ys-extract yellowstone-grpc-builder:v3.1.x
docker cp ys-extract:/output/libyellowstone_grpc_geyser.so .
docker rm ys-extract
scp libyellowstone_grpc_geyser.so solana-rpc-01:/var/mnt/yellowstone/lib/
```

---

## 4. Kubernetes Deployment

### Agave RPC Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: agave-rpc
  namespace: solana
spec:
  replicas: 1
  strategy:
    type: Recreate          # Never run two validators with same identity
  selector:
    matchLabels:
      app: agave-rpc
  template:
    metadata:
      labels:
        app: agave-rpc
    spec:
      nodeSelector:
        kubernetes.io/hostname: solana-rpc-01
      hostNetwork: true       # Direct host networking for gossip UDP
      dnsPolicy: ClusterFirstWithHostNet
      terminationGracePeriodSeconds: 120
      containers:
        - name: agave
          image: ghcr.io/dysnix/docker-agave:v2.2.20
          command: ["agave-validator"]
          args:
            - --identity
            - /etc/solana/validator-keypair.json
            - --ledger
            - /mnt/ledger
            - --accounts
            - /mnt/accounts
            - --snapshots
            - /mnt/ledger/snapshots
            - --rpc-port
            - "8899"
            - --rpc-bind-address
            - 0.0.0.0
            - --private-rpc
            - --full-rpc-api
            - --no-voting
            - --account-index
            - spl-token-owner
            - --account-index
            - program-id
            - --account-index
            - spl-token-mint
            - --limit-ledger-size
            - "500000000"
            - --expected-genesis-hash
            - 5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d
            - --entrypoint
            - entrypoint.mainnet-beta.solana.com:8001
            - --entrypoint
            - entrypoint2.mainnet-beta.solana.com:8001
            - --entrypoint
            - entrypoint3.mainnet-beta.solana.com:8001
            - --known-validator
            - 7Np41oeYqPefeNQEHSv1UDhYrehxin3NStELsSKCT4K2
            - --known-validator
            - GdnSyH3YtwcxFvQrVVJMm1JhTS4QVX7MFsX56uJLUfiZ
            - --known-validator
            - dDzy5SR3AXdYWVqbDEkVFdvSPCtS9ihF5kJkHCtXoFs
            - --known-validator
            - Ft5fbkqNa76vnsjYNwjDZUXoTWpP7VYm3mtsaQckQADN
            - --dynamic-port-range
            - "8000-8020"
            - --gossip-port
            - "8001"
            - --no-port-check
            - --wal-recovery-mode
            - skip_any_corrupted_record
            - --use-snapshot-archives-at-startup
            - when-newest
            - --log
            - "-"
          env:
            - name: RUST_LOG
              value: "solana=info"
            - name: MALLOC_CONF
              value: "background_thread:true,metadata_thp:always,dirty_decay_ms:3000"
          ports:
            - { name: rpc, containerPort: 8899, protocol: TCP }
            - { name: ws, containerPort: 8900, protocol: TCP }
            - { name: gossip-tcp, containerPort: 8001, protocol: TCP }
            - { name: gossip-udp, containerPort: 8001, protocol: UDP }
          volumeMounts:
            - { name: accounts, mountPath: /mnt/accounts }
            - { name: ledger, mountPath: /mnt/ledger }
            - { name: identity, mountPath: /etc/solana, readOnly: true }
          resources:
            requests: { cpu: "16", memory: 512Gi, hugepages-2Mi: 4Gi }
            limits:   { cpu: "16", memory: 750Gi, hugepages-2Mi: 4Gi }
        # Metrics sidecar
        - name: solana-exporter
          image: ghcr.io/asymmetric-research/solana-exporter:v3.0.2
          args: ["-rpc-url=http://localhost:8899", "-listen-address=:9179", "-light-mode"]
          ports:
            - { name: metrics, containerPort: 9179, protocol: TCP }
          resources:
            requests: { cpu: 100m, memory: 64Mi }
            limits:   { cpu: 200m, memory: 128Mi }
      volumes:
        - name: accounts
          hostPath: { path: /var/mnt/accounts, type: DirectoryOrCreate }
        - name: ledger
          hostPath: { path: /var/mnt/ledger, type: DirectoryOrCreate }
        - name: identity
          secret: { secretName: agave-identity }
```

### Services

```yaml
# Yellowstone gRPC service (for dex-indexer, trading bots)
apiVersion: v1
kind: Service
metadata:
  name: agave-rpc-grpc
  namespace: solana
spec:
  type: ClusterIP
  selector: { app: agave-rpc }
  ports:
    - { name: grpc, port: 10000, targetPort: grpc, protocol: TCP }
---
# Prometheus metrics
apiVersion: v1
kind: Service
metadata:
  name: solana-exporter
  namespace: solana
spec:
  selector: { app: agave-rpc }
  ports:
    - { name: metrics, port: 9179, targetPort: 9179 }
```

### Identity Secret

```bash
# ⚠️ SECURITY: Never log or expose validator identity keys
# Generate a new identity (or use existing keypair)
solana-keygen new --outfile validator-keypair.json --no-bip39-passphrase

# Create K8s secret
kubectl -n solana create secret generic agave-identity \
  --from-file=validator-keypair.json=./validator-keypair.json

# Delete local copy immediately
shred -u validator-keypair.json
```

---

## 5. CTO Blockchain Operator (CRD)

The `cto-blockchain-operator` provides a Kubernetes operator with a `SolanaNode` CRD
for declarative node management.

```yaml
# API: blockchain.5dlabs.io/v1alpha1
apiVersion: blockchain.5dlabs.io/v1alpha1
kind: SolanaNode
metadata:
  name: mainnet-validator
spec:
  nodeType: validator       # validator | rpc | archival
  enableVoting: false
  identitySecret: "solana-identity"
  image: "anzaxyz/agave:v3.1.9"     # default
  rpcPort: 8899                      # default
  gossipPort: 8001                   # default
  knownValidators:
    - "7Np41oeYqPefeNQEHSv1UDhYrehxin3NStELsSKCT4K2"
    - "HEL1USMZKAL2odpNBj2oCjffnFGaYwmbGmyewGv1e2TU"
  entrypoints:
    - "entrypoint.mainnet-beta.solana.com:8001"
    - "entrypoint2.mainnet-beta.solana.com:8001"
  config:
    expectedGenesisHash: "5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d"
    limitLedgerSize: 200000000
    fullRpcApi: true
    enableAccountsDiskIndex: true
    skipStartupLedgerVerification: true
    rpcThreads: 128
    maximumFullSnapshotsToRetain: 2
    walRecoveryMode: "skip_any_corrupted_record"
  resources:
    cpuRequest: "28"
    memoryRequest: "64Gi"
    cpuLimit: "32"
    memoryLimit: "128Gi"
```

**Status tracking** — the operator reports:
- `phase`: Pending → Initializing → Running → Error
- `slotHeight`: Current slot
- `healthy`: Boolean health check
- `slotsBehind`: Slots behind network tip

---

## 6. Low-Latency Tuning (Talos Linux)

Applied via `machine.install.extraKernelArgs` and `machine.sysctls`:

### Kernel Arguments

```yaml
machine:
  install:
    extraKernelArgs:
      # CPU — max performance, no frequency scaling
      - cpufreq.default_governor=performance
      - idle=poll
      - processor.max_cstate=0
      - isolcpus=16-31
      - nohz_full=16-31
      - rcu_nocbs=16-31
      - preempt=full
      # Timekeeping
      - tsc=reliable
      - clocksource=tsc
      - nmi_watchdog=0
      - nosoftlockup
      - skew_tick=1
      # Memory
      - hugepagesz=2M
      - hugepages=2048
      - transparent_hugepage=madvise
      # Performance over security
      - mitigations=off
      - audit=0
      # I/O
      - nvme_core.io_timeout=4294967295
      - iommu.strict=0
```

### Sysctls

```yaml
machine:
  sysctls:
    # UDP gossip buffers (128 MB)
    net.core.rmem_max: "134217728"
    net.core.wmem_max: "134217728"
    net.core.rmem_default: "134217728"
    net.core.wmem_default: "134217728"
    net.ipv4.udp_mem: "65536 131072 262144"
    # TCP tuning
    net.ipv4.tcp_rmem: "4096 1048576 67108864"
    net.ipv4.tcp_wmem: "4096 1048576 67108864"
    net.ipv4.tcp_fastopen: "3"
    net.ipv4.tcp_tw_reuse: "1"
    net.ipv4.tcp_low_latency: "1"
    # Socket busy-polling (~10-50µs latency reduction)
    net.core.busy_poll: "50"
    net.core.busy_read: "50"
    # Connection handling
    net.core.somaxconn: "8192"
    net.core.netdev_max_backlog: "10000"
    # Agave file descriptors and mmap
    fs.file-max: "2097152"
    fs.nr_open: "2097152"
    vm.max_map_count: "2000000"
    vm.swappiness: "1"
```

---

## 7. Monitoring & Observability

### Prometheus Targets

- `solana-exporter:9179` — Validator metrics (slot height, health, SOL balance)
- `yellowstone:8999` — gRPC plugin metrics
- `node-exporter:9100` — Host metrics (CPU, memory, disk, network)

### Key Metrics

| Metric | Alert Threshold | Meaning |
|--------|----------------|---------|
| `solana_node_is_healthy` | `== 0` for 5m | RPC unreachable or delinquent |
| `solana_node_slot_height` | Stale for 2m | Node stopped processing slots |
| `solana_active_validators` | Drop > 10% | Network-wide issue |
| Host disk usage | > 80% | Ledger/accounts filling up |

### Grafana Dashboard

A pre-built dashboard is available at `skills/trader/k8s/observability/dashboards/solana-validator.yaml`:
- Node phase (STARTING → CATCHING UP → SYNCED)
- Slot height (current vs network)
- RPC health status
- SOL balance
- Validator logs (via Loki)

---

## 8. Bare-Metal Provisioning

The `crates/metal/` Rust crate automates bare-metal provisioning:

```rust
// Provider trait — implemented for each bare-metal provider
pub trait Provider {
    async fn list_servers(&self) -> Result<Vec<Server>>;
    async fn provision(&self, spec: &ServerSpec) -> Result<Server>;
    async fn destroy(&self, server_id: &str) -> Result<()>;
}
```

### Supported Providers

- **Latitude.sh** — Primary (iPXE boot, API provisioning)
- **Cherry Servers** — Secondary (GRUB-based Talos boot)
- **Vultr**, **Scaleway**, **Hetzner**, **OVH**, **DigitalOcean**, **On-Prem**

### Provisioning Flow

```
1. Provider API → Order bare metal server
2. iPXE/GRUB → Boot Talos Linux installer
3. Talos API → Apply machine config (kernel args, sysctls, kubelet)
4. Bootstrap → Initialize K8s control plane
5. Cilium → Install CNI with eBPF
6. ArgoCD → Deploy Solana stack from GitOps
```

### Disk Layout (Solana Node)

```
/var/mnt/
├── accounts/       # NVMe 1 — Accounts DB (random I/O heavy)
├── ledger/         # NVMe 2 — Ledger + snapshots (sequential write)
│   └── snapshots/
└── yellowstone/    # Host path for gRPC plugin .so
    └── lib/
```

> **Critical:** Accounts and ledger MUST be on separate NVMe drives.
> Sharing a drive causes I/O contention that degrades slot processing.

---

## 9. GitOps Deployment

ArgoCD applications manage the full Solana stack:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: latitude-solana
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/5dlabs/cto
    path: skills/trader/k8s
    targetRevision: main
  destination:
    server: https://<cluster-ip>:6443
    namespace: solana
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

Kustomize overlays per provider: `skills/trader/k8s/overlays/latitude/kustomization.yaml`

---

## 10. Operational Runbook

### First-Time Setup

```bash
# 1. Provision bare metal
metal provision --provider latitude --plan m3-large-x86

# 2. Bootstrap Talos
talosctl apply-config --nodes <IP> --file controlplane.yaml

# 3. Deploy Solana namespace
kubectl create namespace solana

# 4. Create identity secret
kubectl -n solana create secret generic agave-identity \
  --from-file=validator-keypair.json

# 5. Apply manifests (or let ArgoCD sync)
kubectl apply -f skills/trader/k8s/agave-rpc.yaml

# 6. Monitor bootstrap (takes 30-60 min for snapshot download)
kubectl -n solana logs deploy/agave-rpc -c agave -f
```

### Health Checks

```bash
# RPC responding
curl -s http://solana-rpc-01:8899 -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}' | jq .

# Current slot
curl -s http://solana-rpc-01:8899 -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}' | jq .result

# Yellowstone gRPC reachable
grpcurl -plaintext solana-rpc-01:10000 list

# Exporter metrics
curl -s http://solana-rpc-01:9179/metrics | grep solana_node
```

### Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Pod stuck CrashLoopBackOff | Identity secret missing | `kubectl -n solana get secret agave-identity` |
| Gossip port 8001 already bound | Stale hostNetwork pod | Apply `agave-port-cleanup-pod.yaml` |
| Yellowstone crash at startup | `.so` version mismatch | Rebuild plugin matching Agave version |
| Slow catch-up (>2 hrs) | Accounts on same drive as ledger | Move to separate NVMe |
| OOM killed | Insufficient hugepages | Verify kernel args: `hugepages=2048` |

---

## Security Rules

1. **Identity keys** are K8s Secrets — NEVER log, print, or expose them
2. **No voting** on RPC nodes — voting requires staked SOL and different security posture
3. **Private RPC** (`--private-rpc`) — only expose to known consumers
4. **Shred local copies** of keypair files after creating K8s secrets
5. **Network isolation** — Twingate for admin access, no public SSH
