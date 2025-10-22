#!/bin/bash

# NAT Traversal Docker Testing Script
# Tests real NAT traversal scenarios using Docker containers

set -e

COMPOSE_FILE="docker-compose.nat-test.yml"
DOCKER_IMAGE="chiral-network-nat-test"

# Detect docker-compose command (v1 vs v2)
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
elif docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
else
    echo "Error: Neither 'docker-compose' nor 'docker compose' found"
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker first."
        echo ""
        echo "Install Docker:"
        echo "  Ubuntu/Debian: sudo apt-get install docker.io docker-compose"
        echo "  macOS: Install Docker Desktop from docker.com"
        exit 1
    fi

    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log_error "Docker Compose is not installed."
        exit 1
    fi

    # Check if user can run docker
    if ! docker ps &> /dev/null; then
        log_warning "Cannot run docker commands. You may need to:"
        echo "  1. Add your user to the docker group: sudo usermod -aG docker \$USER"
        echo "  2. Log out and log back in"
        echo "  3. Or run this script with sudo"
        exit 1
    fi

    log_success "All prerequisites met!"
}

# Clean up existing containers
cleanup() {
    log_info "Cleaning up existing containers and networks..."
    $DOCKER_COMPOSE -f "$COMPOSE_FILE" down -v 2>/dev/null || true
    docker network prune -f 2>/dev/null || true
    log_success "Cleanup complete"
}

# Build Docker images
build_images() {
    log_info "Building Docker image for Chiral Network..."
    docker build -f Dockerfile.nat-test -t "$DOCKER_IMAGE" .
    log_success "Docker image built successfully"
}

# Get bootstrap peer ID
get_bootstrap_peer_id() {
    log_info "Waiting for bootstrap node to start..."
    sleep 10

    log_info "Extracting peer ID from bootstrap logs..."

    # Try to extract peer ID from libp2p_swarm log line: local_peer_id=...
    local peer_id
    peer_id=$(docker logs chiral-bootstrap 2>&1 | grep -oP 'local_peer_id=\K[A-Za-z0-9]+' | head -1 || true)

    if [ -z "$peer_id" ]; then
        log_error "Could not extract bootstrap peer ID from logs"
        log_error "Last 30 lines of bootstrap logs:"
        docker logs chiral-bootstrap 2>&1 | tail -30 || true
        log_error "Trying alternative extraction method..."
        peer_id=$(docker logs chiral-bootstrap 2>&1 | grep "local_peer_id" | head -1 | sed 's/.*local_peer_id=\([A-Za-z0-9]*\).*/\1/' || true)

        if [ -z "$peer_id" ]; then
            log_error "All extraction methods failed"
            return 1
        fi
    fi

    log_success "Bootstrap peer ID: $peer_id"
    echo "$peer_id"
}

# Update docker-compose with bootstrap peer ID
update_bootstrap_peer_id() {
    local peer_id=$1
    log_info "Updating docker-compose with bootstrap peer ID: $peer_id"

    # Replace BOOTSTRAP_PEER_ID placeholder in docker-compose file
    sed -i.bak "s/BOOTSTRAP_PEER_ID/$peer_id/g" "$COMPOSE_FILE"
    log_success "Bootstrap peer ID updated"
}

# Start test environment
start_environment() {
    log_info "Starting NAT simulation environment..."
    echo ""
    echo "Network topology:"
    echo "  📡 Bootstrap node:  172.20.0.10 (public network, acts as relay)"
    echo "  🏠 Peer 1:          10.1.0.10 (private network 1 - NAT)"
    echo "  🏢 Peer 2:          10.2.0.10 (private network 2 - different NAT)"
    echo "  🏠 Peer 3:          10.1.0.11 (private network 1 - same NAT as Peer 1)"
    echo "  🌐 Public peer:     172.20.0.20 (public network - no NAT)"
    echo ""

    # Start bootstrap first
    $DOCKER_COMPOSE -f "$COMPOSE_FILE" up -d bootstrap
    log_info "Bootstrap node starting..."

    # Get and set bootstrap peer ID
    BOOTSTRAP_PEER_ID=$(get_bootstrap_peer_id)
    if [ -z "$BOOTSTRAP_PEER_ID" ]; then
        log_error "Failed to get bootstrap peer ID"
        return 1
    fi

    update_bootstrap_peer_id "$BOOTSTRAP_PEER_ID"

    # Start remaining peers
    $DOCKER_COMPOSE -f "$COMPOSE_FILE" up -d
    log_success "All containers started"

    # Restore original docker-compose file
    if [ -f "${COMPOSE_FILE}.bak" ]; then
        mv "${COMPOSE_FILE}.bak" "$COMPOSE_FILE"
    fi
}

# Monitor logs for NAT traversal events
monitor_nat_events() {
    log_info "Monitoring NAT traversal events..."
    echo ""
    echo "Looking for:"
    echo "  ✓ DCUtR hole-punch attempts"
    echo "  ✓ AutoNAT reachability detection"
    echo "  ✓ Relay circuit establishment"
    echo "  ✓ Direct connection upgrades"
    echo ""

    sleep 30  # Wait for network to stabilize

    log_info "=== Bootstrap Node (Relay) ==="
    docker logs chiral-bootstrap 2>&1 | grep -i "dcutr\|autonat\|relay\|reachability" | tail -20 || true

    log_info "=== Peer 1 (NAT 1) ==="
    docker logs chiral-peer1 2>&1 | grep -i "dcutr\|autonat\|relay\|hole-punch\|direct connection" | tail -20 || true

    log_info "=== Peer 2 (NAT 2) ==="
    docker logs chiral-peer2 2>&1 | grep -i "dcutr\|autonat\|relay\|hole-punch\|direct connection" | tail -20 || true

    log_info "=== Public Peer (No NAT) ==="
    docker logs chiral-public-peer 2>&1 | grep -i "dcutr\|autonat\|relay\|reachability" | tail -20 || true
}

# Run connectivity tests
run_connectivity_tests() {
    log_info "Running connectivity tests..."
    echo ""

    # Test 1: Peer discovery
    log_info "Test 1: Peer discovery (waiting 60s for DHT convergence)..."
    sleep 60

    # Check peer counts
    log_info "Checking peer counts..."
    for container in chiral-peer1 chiral-peer2 chiral-peer3 chiral-public-peer; do
        local peer_count=$(docker logs $container 2>&1 | grep -oP 'peer count: \K[0-9]+' | tail -1)
        if [ -n "$peer_count" ] && [ "$peer_count" -gt 0 ]; then
            log_success "$container: $peer_count peers connected"
        else
            log_warning "$container: No peer count found (may need more time)"
        fi
    done

    # Test 2: DCUtR hole-punching
    log_info "Test 2: Checking for DCUtR hole-punch attempts..."
    local dcutr_attempts=$(docker logs chiral-peer1 2>&1 | grep -c "DCUtR.*hole-punch" || true)
    local dcutr_successes=$(docker logs chiral-peer1 2>&1 | grep -c "hole-punch succeeded" || true)

    echo "  Peer 1 DCUtR attempts: $dcutr_attempts"
    echo "  Peer 1 DCUtR successes: $dcutr_successes"

    if [ "$dcutr_attempts" -gt 0 ]; then
        log_success "DCUtR hole-punching was attempted"
        if [ "$dcutr_successes" -gt 0 ]; then
            log_success "DCUtR hole-punching succeeded! ✓"
        else
            log_warning "DCUtR attempted but no successes yet (may use relay fallback)"
        fi
    else
        log_warning "No DCUtR attempts detected (may need more time or connections are direct)"
    fi

    # Test 3: Relay usage
    log_info "Test 3: Checking for relay circuit establishment..."
    local relay_circuits=$(docker logs chiral-peer1 2>&1 | grep -c "relay.*circuit\|circuit.*relay" || true)

    if [ "$relay_circuits" -gt 0 ]; then
        log_success "Relay circuits detected: $relay_circuits"
    else
        log_info "No relay circuits detected (peers may be directly connected)"
    fi

    # Test 4: Reachability detection
    log_info "Test 4: Checking AutoNAT reachability detection..."
    for container in chiral-peer1 chiral-peer2 chiral-public-peer; do
        local reachability=$(docker logs $container 2>&1 | grep -oP 'reachability: \K[A-Za-z]+' | tail -1)
        if [ -n "$reachability" ]; then
            echo "  $container: $reachability"
        fi
    done
}

# Generate test report
generate_report() {
    log_info "Generating test report..."

    REPORT_FILE="NAT_DOCKER_TEST_REPORT_$(date +%Y%m%d_%H%M%S).md"

    cat > "$REPORT_FILE" <<EOF
# Docker NAT Traversal Test Report

**Date:** $(date)
**Test Environment:** Docker containers with simulated NAT

## Network Topology

\`\`\`
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
\`\`\`

## Test Scenarios

### 1. Peer Discovery
EOF

    # Append peer counts
    for container in chiral-peer1 chiral-peer2 chiral-peer3 chiral-public-peer; do
        local peer_count=$(docker logs $container 2>&1 | grep -oP 'peer count: \K[0-9]+' | tail -1)
        echo "- **$container**: ${peer_count:-Unknown} peers" >> "$REPORT_FILE"
    done

    cat >> "$REPORT_FILE" <<EOF

### 2. DCUtR Hole-Punching Results

\`\`\`
$(docker logs chiral-peer1 2>&1 | grep "DCUtR" | tail -10)
\`\`\`

### 3. AutoNAT Reachability Detection

\`\`\`
$(docker logs chiral-peer1 2>&1 | grep "reachability\|AutoNAT" | tail -10)
\`\`\`

### 4. Relay Circuit Usage

\`\`\`
$(docker logs chiral-bootstrap 2>&1 | grep "relay\|circuit" | tail -10)
\`\`\`

## Full Container Logs

<details>
<summary>Bootstrap Node Logs</summary>

\`\`\`
$(docker logs chiral-bootstrap 2>&1 | tail -50)
\`\`\`
</details>

<details>
<summary>Peer 1 Logs (NAT 1)</summary>

\`\`\`
$(docker logs chiral-peer1 2>&1 | tail -50)
\`\`\`
</details>

<details>
<summary>Peer 2 Logs (NAT 2)</summary>

\`\`\`
$(docker logs chiral-peer2 2>&1 | tail -50)
\`\`\`
</details>

## Conclusion

- **Peer Discovery:** $([ -n "$(docker logs chiral-peer1 2>&1 | grep 'peer count' | tail -1)" ] && echo "✓ Working" || echo "? Needs verification")
- **DCUtR Hole-Punching:** $([ "$(docker logs chiral-peer1 2>&1 | grep -c 'hole-punch succeeded')" -gt 0 ] && echo "✓ Successful" || echo "⚠ Not detected")
- **Relay Fallback:** $([ "$(docker logs chiral-peer1 2>&1 | grep -c 'relay')" -gt 0 ] && echo "✓ Available" || echo "? Not used")
- **AutoNAT Detection:** $([ -n "$(docker logs chiral-peer1 2>&1 | grep 'reachability' | tail -1)" ] && echo "✓ Working" || echo "? Needs verification")

**Test Duration:** Started at $(date)
EOF

    log_success "Report generated: $REPORT_FILE"
}

# Main execution
main() {
    echo "==============================================="
    echo "🧪 Docker NAT Traversal Testing Suite"
    echo "==============================================="
    echo ""

    check_prerequisites
    cleanup
    build_images
    start_environment

    log_info "Waiting for network to stabilize (60s)..."
    sleep 60

    run_connectivity_tests
    monitor_nat_events
    generate_report

    echo ""
    echo "==============================================="
    echo "📊 Test Summary"
    echo "==============================================="
    log_success "Docker NAT test environment is running!"
    echo ""
    echo "Commands:"
    echo "  View logs:     $DOCKER_COMPOSE -f $COMPOSE_FILE logs -f [service]"
    echo "  Stop:          $DOCKER_COMPOSE -f $COMPOSE_FILE down"
    echo "  Restart:       $DOCKER_COMPOSE -f $COMPOSE_FILE restart"
    echo ""
    echo "Services:"
    echo "  - bootstrap (relay node)"
    echo "  - peer1 (NAT 1)"
    echo "  - peer2 (NAT 2)"
    echo "  - peer3 (NAT 1, same as peer1)"
    echo "  - public-peer (no NAT)"
    echo ""
    log_info "Leave the environment running to observe long-term behavior,"
    log_info "or run '$DOCKER_COMPOSE -f $COMPOSE_FILE down' to stop."
}

# Trap Ctrl+C
trap 'log_warning "Test interrupted. Run: $DOCKER_COMPOSE -f $COMPOSE_FILE down"; exit 1' INT

# Run main
main "$@"
