#!/bin/bash

# NOTE: A more reliable Rust version exists at src-tauri/src/bin/nat_test.rs
# Build with: cd src-tauri && cargo build --release --bin nat_test
# Run with: sudo ./src-tauri/target/release/nat_test

# NAT Traversal Validation Test Suite
# Runs comprehensive tests to validate NAT traversal and hole-punching implementation

set -e  # Exit on error

echo "==============================================="
echo "🧪 NAT Traversal Validation Test Suite"
echo "==============================================="
echo ""
echo "Running comprehensive tests to validate:"
echo "  - AutoNAT v2 reachability detection"
echo "  - DCUtR hole-punching functionality"
echo "  - Multi-peer DHT connectivity"
echo "  - NAT resilience and fallback behavior"
echo ""
echo "-----------------------------------------------"
echo ""

# Test counter
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Function to run a test
run_test() {
    local test_name=$1
    local test_command=$2

    echo "🔍 Test $((TESTS_RUN + 1)): $test_name"
    echo "   Command: $test_command"

    TESTS_RUN=$((TESTS_RUN + 1))

    if $test_command; then
        echo "   ✅ PASSED"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "   ❌ FAILED"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    echo ""
}

# Test 1: AutoNAT Reachability Detection
run_test "AutoNAT reachability detection" \
    "cargo test --test nat_traversal_e2e_test test_autonat_detection -- --nocapture"

# Test 2: DCUtR Hole-Punching Enablement
run_test "DCUtR hole-punching enabled" \
    "cargo test --test nat_traversal_e2e_test test_dcutr_enabled -- --nocapture"

# Test 3: DHT Peer Discovery
run_test "DHT peer discovery" \
    "cargo test --test nat_traversal_e2e_test test_dht_peer_discovery -- --nocapture"

# Test 4: File Publish and Search
run_test "File publish and search across peers" \
    "cargo test --test nat_traversal_e2e_test test_file_publish_and_search -- --nocapture"

# Test 5: Multiple AutoNAT Servers
run_test "Multiple AutoNAT servers configuration" \
    "cargo test --test nat_traversal_e2e_test test_multiple_autonat_servers -- --nocapture"

# Test 6: Reachability History Tracking
run_test "Reachability history tracking" \
    "cargo test --test nat_traversal_e2e_test test_reachability_history_tracking -- --nocapture"

# Test 7: Connection Metrics Tracking
run_test "Connection metrics tracking" \
    "cargo test --test nat_traversal_e2e_test test_connection_metrics_tracking -- --nocapture"

# Test 8: NAT Resilience (Private ↔ Public)
run_test "NAT resilience: Private ↔ Public connection" \
    "cargo test --test nat_traversal_e2e_test test_nat_resilience_private_to_public -- --nocapture"

# Test 9: NAT Resilience (Connection Fallback)
run_test "NAT resilience: Connection fallback behavior" \
    "cargo test --test nat_traversal_e2e_test test_nat_resilience_connection_fallback -- --nocapture"

# Bonus: Run NAT settings tests
echo "-----------------------------------------------"
echo "🔍 Bonus: NAT Settings Tests"
echo "-----------------------------------------------"
echo ""

run_test "NAT settings structure validation" \
    "cargo test --test nat_traversal_test -- --nocapture"

# Summary
echo "==============================================="
echo "📊 TEST SUMMARY"
echo "==============================================="
echo ""
echo "Total tests run:    $TESTS_RUN"
echo "Tests passed:       $TESTS_PASSED ✅"
echo "Tests failed:       $TESTS_FAILED ❌"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo "🎉 SUCCESS: All NAT traversal validation tests passed!"
    echo ""
    echo "Validation confirmed:"
    echo "  ✓ AutoNAT v2 correctly detects reachability"
    echo "  ✓ DCUtR hole-punching is properly enabled"
    echo "  ✓ DHT peer discovery works across nodes"
    echo "  ✓ File metadata can be published and searched"
    echo "  ✓ NAT traversal handles different network scenarios"
    echo "  ✓ Connection fallback mechanisms work correctly"
    echo ""
    exit 0
else
    echo "❌ FAILURE: Some tests failed. Please review the output above."
    echo ""
    exit 1
fi
