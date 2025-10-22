# Docker-Based NAT Traversal Testing

This directory contains Docker infrastructure for **real-world NAT traversal validation** using isolated container networks.

## 🎯 What This Tests (That Local Tests Can't)

### ✅ Real NAT Scenarios
- **Private ↔ Private connections** across different NAT networks
- **Private ↔ Public connections**
- **Relay circuit establishment** when direct connection fails
- **DCUtR hole-punching** through simulated NATs
- **AutoNAT reachability detection** in realistic network topologies

### ✅ Network Topologies Covered
1. **Symmetric NAT ↔ Symmetric NAT** (Peer 1 ↔ Peer 2)
2. **Same NAT peers** (Peer 1 ↔ Peer 3)
3. **NAT ↔ Public** (Peer 1 ↔ Public Peer)
4. **Public ↔ Public** (Bootstrap ↔ Public Peer)

---

## 📋 Prerequisites

### 1. Install Docker

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install -y docker.io docker-compose
sudo systemctl start docker
sudo systemctl enable docker
```

**macOS:**
```bash
# Install Docker Desktop from https://www.docker.com/products/docker-desktop
```

**Add your user to docker group (Linux):**
```bash
sudo usermod -aG docker $USER
# Log out and log back in
```

### 2. Verify Installation
```bash
docker --version
docker-compose --version
docker ps  # Should not show permission errors
```

---

## 🚀 Quick Start

### Option 1: Automated Test (Recommended)

```bash
# Run the automated test script
./test-nat-docker.sh
```

This script will:
1. ✅ Build the Docker image
2. ✅ Create isolated networks
3. ✅ Start all containers (bootstrap, peers)
4. ✅ Monitor NAT traversal events
5. ✅ Generate a test report

**Duration:** ~3-5 minutes (includes build time)

---

### Option 2: Manual Testing

#### Step 1: Build the Image
```bash
docker build -f Dockerfile.nat-test -t chiral-network-nat-test .
```

#### Step 2: Start the Environment
```bash
# Start bootstrap node first
docker-compose -f docker-compose.nat-test.yml up -d bootstrap

# Wait for bootstrap to initialize (10-15 seconds)
sleep 15

# Get bootstrap peer ID
BOOTSTRAP_ID=$(docker logs chiral-bootstrap 2>&1 | grep -oP 'peer ID: \K[A-Za-z0-9]+' | head -1)
echo "Bootstrap Peer ID: $BOOTSTRAP_ID"

# Update docker-compose.nat-test.yml:
# Replace "BOOTSTRAP_PEER_ID" with the actual peer ID

# Start all other peers
docker-compose -f docker-compose.nat-test.yml up -d
```

#### Step 3: Monitor Logs
```bash
# Watch all logs in real-time
docker-compose -f docker-compose.nat-test.yml logs -f

# Or monitor specific containers
docker logs -f chiral-peer1     # Private peer (NAT 1)
docker logs -f chiral-peer2     # Private peer (NAT 2)
docker logs -f chiral-bootstrap # Bootstrap/relay node
```

#### Step 4: Check NAT Traversal Events
```bash
# Look for DCUtR hole-punching
docker logs chiral-peer1 2>&1 | grep -i "dcutr\|hole-punch"

# Look for AutoNAT reachability detection
docker logs chiral-peer1 2>&1 | grep -i "autonat\|reachability"

# Look for relay circuit establishment
docker logs chiral-bootstrap 2>&1 | grep -i "relay\|circuit"

# Check peer connectivity
docker logs chiral-peer1 2>&1 | grep -i "peer count"
```

#### Step 5: Stop the Environment
```bash
docker-compose -f docker-compose.nat-test.yml down -v
```

---

## 🌐 Network Architecture

```
                    ┌─────────────────┐
                    │  Public Network │
                    │   172.20.0.0/16 │
                    └────────┬────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
  ┌─────▼──────┐      ┌─────▼──────┐      ┌─────▼──────┐
  │ Bootstrap  │      │Public Peer │      │   Router   │
  │172.20.0.10 │      │172.20.0.20 │      │  (Docker)  │
  │  (Relay)   │      │  (No NAT)  │      │            │
  └────────────┘      └────────────┘      └─────┬──────┘
                                                 │
                              ┌──────────────────┴──────────────────┐
                              │                                     │
                      ┌───────▼────────┐                  ┌────────▼───────┐
                      │Private Network 1│                  │Private Network 2│
                      │   10.1.0.0/24   │                  │   10.2.0.0/24   │
                      └────────┬────────┘                  └────────┬────────┘
                               │                                    │
                    ┌──────────┴──────────┐                  ┌──────▼──────┐
                    │                     │                  │             │
              ┌─────▼──────┐        ┌────▼───────┐    ┌────▼───────┐
              │   Peer 1   │        │   Peer 3   │    │   Peer 2   │
              │ 10.1.0.10  │        │ 10.1.0.11  │    │ 10.2.0.10  │
              │  (NAT 1)   │        │  (NAT 1)   │    │  (NAT 2)   │
              └────────────┘        └────────────┘    └────────────┘
```

### Container Roles

| Container | Network | IP Address | Role |
|-----------|---------|------------|------|
| `chiral-bootstrap` | Public | 172.20.0.10 | Bootstrap node & relay server |
| `chiral-public-peer` | Public | 172.20.0.20 | Public peer (no NAT) |
| `chiral-peer1` | Private Net 1 + Public | 10.1.0.10 | Behind NAT 1 |
| `chiral-peer2` | Private Net 2 + Public | 10.2.0.10 | Behind NAT 2 (different) |
| `chiral-peer3` | Private Net 1 + Public | 10.1.0.11 | Behind NAT 1 (same as peer1) |

---

## 🔍 What to Look For in Logs

### 1. DCUtR Hole-Punching Success ✅
```
✓ DCUtR hole-punch succeeded → direct connection upgraded
  peer: 12D3KooW...
  attempt: 3
  success_rate: 66.7%
  connection_method: DCUtR_DIRECT
```

### 2. DCUtR Hole-Punching Failure (Relay Fallback) ⚠️
```
✗ DCUtR hole-punch failed → falling back to relay connection
  peer: 12D3KooW...
  error_type: NAT_TRAVERSAL_FAILED
  connection_method: DCUtR_FALLBACK_TO_RELAY
```

### 3. AutoNAT Detection 🔎
```
AutoNAT: reachability changed to Private (confidence: High)
```

### 4. Relay Circuit Establishment 🔄
```
Relay circuit established with peer 12D3KooW...
```

### 5. Peer Discovery 🤝
```
Peer connected: 12D3KooW...
Connected peers: 4
```

---

## 📊 Expected Results

### Peer 1 → Peer 2 (Different NATs)
- **Expected:** Relay circuit or DCUtR hole-punch attempt
- **Success metric:** Connection established (may be via relay)

### Peer 1 → Peer 3 (Same NAT)
- **Expected:** Direct connection (both on 10.1.0.0/24)
- **Success metric:** Fast connection, no relay needed

### Peer 1 → Public Peer (NAT → Public)
- **Expected:** Direct connection after AutoNAT detection
- **Success metric:** Public peer sees Peer 1 as reachable

### Peer 1 → Bootstrap (NAT → Relay)
- **Expected:** Direct connection + relay reservation
- **Success metric:** Relay circuits available for other peers

---

## 🐛 Troubleshooting

### Issue: "Docker not found"
```bash
# Install Docker first (see Prerequisites section)
```

### Issue: "Permission denied"
```bash
# Add user to docker group
sudo usermod -aG docker $USER
# Log out and back in
```

### Issue: "Containers not connecting"
```bash
# Check container logs
docker-compose -f docker-compose.nat-test.yml logs

# Restart the environment
docker-compose -f docker-compose.nat-test.yml down
docker-compose -f docker-compose.nat-test.yml up -d
```

### Issue: "Build fails"
```bash
# Clean build cache
docker system prune -a
# Rebuild
docker build --no-cache -f Dockerfile.nat-test -t chiral-network-nat-test .
```

### Issue: "Bootstrap peer ID not found"
```bash
# Manually check bootstrap logs
docker logs chiral-bootstrap

# Look for line: "peer ID: 12D3KooW..."
# Update docker-compose.nat-test.yml manually
```

---

## 📈 Interpreting Test Results

### ✅ Success Indicators
1. **All peers discover each other** (peer count > 0)
2. **DCUtR attempts occur** (shows hole-punching is active)
3. **Relay circuits established** (fallback works)
4. **AutoNAT detects reachability** (Private/Public state changes)

### ⚠️ Partial Success (Expected in Some Cases)
1. **DCUtR fails but relay succeeds** (normal for symmetric NAT)
2. **Some connections direct, some relayed** (topology-dependent)
3. **Reachability stays "Unknown"** (may need more time/probes)

### ❌ Failure Indicators
1. **Peer count stays 0** (no discovery)
2. **No DCUtR or relay attempts** (protocols not working)
3. **Containers crash or restart** (code issues)

---

## 🔬 Advanced Testing Scenarios

### Test 1: Force Relay Usage (Disable DCUtR)
```bash
# Edit docker-compose.nat-test.yml
# Add to peer environment:
CHIRAL_DISABLE_DCUTR=1
```

### Test 2: Test Different Network Latencies
```bash
# Add network delay (requires tc/netem)
docker exec chiral-peer1 tc qdisc add dev eth0 root netem delay 100ms
```

### Test 3: Simulate Network Partitions
```bash
# Disconnect peer from network temporarily
docker network disconnect docker-compose_public_net chiral-peer1
sleep 30
docker network connect docker-compose_public_net chiral-peer1
```

### Test 4: Long-Running Stability Test
```bash
# Leave environment running for 24 hours
docker-compose -f docker-compose.nat-test.yml up -d

# Monitor periodically
watch -n 60 'docker-compose -f docker-compose.nat-test.yml logs --tail=20'
```

---

## 📝 Collecting Test Evidence for Review

### 1. Generate Full Log Dump
```bash
docker-compose -f docker-compose.nat-test.yml logs > nat_test_full_logs.txt
```

### 2. Extract NAT-Specific Events
```bash
# DCUtR events
docker-compose -f docker-compose.nat-test.yml logs | grep -i dcutr > dcutr_events.txt

# AutoNAT events
docker-compose -f docker-compose.nat-test.yml logs | grep -i autonat > autonat_events.txt

# Relay events
docker-compose -f docker-compose.nat-test.yml logs | grep -i relay > relay_events.txt
```

### 3. Take Screenshots
```bash
# Terminal output showing:
# - Container startup
# - Peer discovery messages
# - DCUtR success/failure logs
# - Final peer counts
```

---

## 🎓 Understanding the Test Results

### What This Proves vs. Local Tests

| Aspect | Local Tests | Docker Tests |
|--------|-------------|--------------|
| **Code works** | ✅ Yes | ✅ Yes |
| **Peers connect** | ✅ Locally | ✅ Across NATs |
| **AutoNAT detects NAT** | ❌ Always Unknown | ✅ Detects Private |
| **DCUtR hole-punches** | ❌ No NAT to punch | ✅ Real attempts |
| **Relay fallback** | ❌ No failures | ✅ Real fallback |
| **Topology-specific** | ❌ No | ✅ Yes |

### Real-World Applicability

These Docker tests simulate **realistic NAT scenarios** but still have limitations:

✅ **Tests:**
- NAT traversal protocols (DCUtR, AutoNAT, Relay)
- Different network topologies
- Fallback mechanisms

⚠️ **Doesn't test:**
- Real ISP NAT behaviors
- Actual internet latency/packet loss
- Hardware router quirks
- Firewall policies beyond Docker

**For production validation**, you'd still need multi-cloud/multi-region testing.

---

## 📚 Next Steps

After running Docker tests:

1. **Review generated report** (`NAT_DOCKER_TEST_REPORT_*.md`)
2. **Collect evidence** (logs, screenshots)
3. **Compare with local tests** to show improvement
4. **Document findings** in progress review
5. **Plan real-world testing** (cloud VMs, different ISPs)

---

## 🤝 Contributing

To improve these Docker tests:

1. Add more network scenarios (IPv6, port restrictions)
2. Implement automated assertions (not just log monitoring)
3. Add performance benchmarks (connection time, bandwidth)
4. Create CI/CD integration for automated testing

---

**Created:** October 22, 2025
**Status:** Ready for testing (requires Docker installation)
**Purpose:** Real-world NAT traversal validation beyond local tests
