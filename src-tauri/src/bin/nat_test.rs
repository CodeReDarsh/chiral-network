use std::process::Command;
use std::thread;
use std::time::Duration;
use std::fs;
use regex::Regex;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("===============================================");
    println!("🧪 Docker NAT Traversal Testing Suite (Rust)");
    println!("===============================================\n");

    // Step 1: Cleanup
    println!("🧹 Cleaning up existing containers...");
    let _ = Command::new("docker")
        .args(&["compose", "-f", "docker-compose.nat-test.yml", "down", "-v"])
        .output();

    // Force remove the bootstrap container to clear old logs
    let _ = Command::new("docker")
        .args(&["rm", "-f", "chiral-bootstrap"])
        .output();

    // Step 2: Build image
    println!("🔨 Building Docker image...");
    let build = Command::new("docker")
        .args(&["build", "-f", "Dockerfile.nat-test", "-t", "chiral-network-nat-test", "."])
        .status()?;

    if !build.success() {
        eprintln!("❌ Docker build failed");
        return Err("Build failed".into());
    }
    println!("✅ Docker image built\n");

    // Step 3: Start bootstrap node
    println!("🚀 Starting bootstrap node...");
    let start = Command::new("docker")
        .args(&["compose", "-f", "docker-compose.nat-test.yml", "up", "-d", "bootstrap"])
        .status()?;

    if !start.success() {
        eprintln!("❌ Failed to start bootstrap");
        return Err("Bootstrap start failed".into());
    }

    // Step 4: Wait and extract peer ID with retry
    println!("🔍 Waiting for bootstrap peer ID...");

    // Get container start time to filter logs from THIS run only
    let start_output = Command::new("sh")
        .arg("-c")
        .arg("docker inspect --format='{{.State.StartedAt}}' chiral-bootstrap")
        .output()?;

    let start_time = String::from_utf8_lossy(&start_output.stdout).trim().to_string();

    // Retry up to 20 times (1 second each = 20 seconds total)
    let peer_id_regex = Regex::new(r"local_peer_id=(12D3[A-Za-z0-9]{44,})")?;
    let mut peer_id = None;

    for attempt in 1..=20 {
        thread::sleep(Duration::from_secs(1));

        // Get logs since container start and grep for peer ID
        let grep_cmd = format!(
            "docker logs --since '{}' chiral-bootstrap 2>&1 | grep 'local_peer_id='",
            start_time
        );

        let grep_output = Command::new("sh")
            .arg("-c")
            .arg(&grep_cmd)
            .output()?;

        let peer_id_line = String::from_utf8_lossy(&grep_output.stdout);

        if !peer_id_line.trim().is_empty() {
            // Extract the peer ID
            if let Some(captures) = peer_id_regex.captures(&peer_id_line) {
                if let Some(id) = captures.get(1) {
                    peer_id = Some(id.as_str().to_string());
                    println!("✅ Bootstrap Peer ID: {} (found after {}s)\n", id.as_str(), attempt);
                    break;
                }
            }
        }

        if attempt % 5 == 0 {
            println!("   Still waiting... ({}s)", attempt);
        }
    }

    let peer_id = peer_id.ok_or("Could not extract peer ID from bootstrap logs after 20 seconds. Check container logs with: docker logs chiral-bootstrap")?;

    // Step 5: Update docker-compose with peer ID
    println!("📝 Updating docker-compose with peer ID...");
    let compose_content = fs::read_to_string("docker-compose.nat-test.yml")?;
    let updated_content = compose_content.replace("BOOTSTRAP_PEER_ID", &peer_id);
    fs::write("docker-compose.nat-test.yml", &updated_content)?;
    println!("✅ Docker-compose updated\n");

    // Step 6: Start all peers
    println!("🚀 Starting all peers...");
    let start_all = Command::new("docker")
        .args(&["compose", "-f", "docker-compose.nat-test.yml", "up", "-d"])
        .status()?;

    if !start_all.success() {
        eprintln!("❌ Failed to start peers");
        return Err("Peer start failed".into());
    }
    println!("✅ All containers started\n");

    // Restore original docker-compose
    let original_content = updated_content.replace(&peer_id, "BOOTSTRAP_PEER_ID");
    fs::write("docker-compose.nat-test.yml", &original_content)?;

    // Step 7: Monitor
    println!("⏳ Waiting 60s for network stabilization...");
    thread::sleep(Duration::from_secs(60));

    // Step 8: Verify peer ID configuration
    println!("\n🔍 Verifying bootstrap peer ID configuration...");
    let inspect = Command::new("docker")
        .args(&["inspect", "chiral-peer1", "--format", "{{.Config.Cmd}}"])
        .output()?;

    let cmd_str = String::from_utf8_lossy(&inspect.stdout);
    if cmd_str.contains(&peer_id) {
        println!("✅ Peer1 configured with correct bootstrap peer ID");
    } else {
        println!("⚠️  WARNING: Peer1 bootstrap config may not match extracted peer ID");
        println!("   Expected: {}", &peer_id);
        println!("   Config: {}", cmd_str.trim());
    }

    // Step 9: Check connections
    println!("\n📊 Checking peer connections...");
    for container in &["chiral-peer1", "chiral-peer2", "chiral-peer3", "chiral-public-peer"] {
        let logs = Command::new("docker")
            .args(&["logs", container])
            .output()?;

        let combined = format!(
            "{}{}",
            String::from_utf8_lossy(&logs.stdout),
            String::from_utf8_lossy(&logs.stderr)
        );

        let connected = combined.contains("Connected to") || combined.contains("Total connected peers");
        let status = if connected { "✅" } else { "⚠️" };

        println!("{} {}: {}", status, container, if connected { "Connected" } else { "No connections detected" });
    }

    println!("\n📡 Checking NAT traversal activity...");

    // Check for DCUtR
    let peer1_logs = Command::new("docker")
        .args(&["logs", "chiral-peer1"])
        .output()?;
    let peer1_combined = format!(
        "{}{}",
        String::from_utf8_lossy(&peer1_logs.stdout),
        String::from_utf8_lossy(&peer1_logs.stderr)
    );

    let dcutr_count = peer1_combined.matches("DCUtR").count();
    let autonat_count = peer1_combined.matches("AutoNAT").count();
    let reachability_count = peer1_combined.matches("Reachability").count();

    println!("  DCUtR mentions: {}", dcutr_count);
    println!("  AutoNAT mentions: {}", autonat_count);
    println!("  Reachability mentions: {}", reachability_count);

    println!("\n===============================================");
    println!("✅ Test Complete!");
    println!("===============================================");
    println!("\nContainers are still running. View logs with:");
    println!("  docker logs -f chiral-peer1");
    println!("  docker logs -f chiral-bootstrap");
    println!("\nStop all containers with:");
    println!("  docker compose -f docker-compose.nat-test.yml down");

    Ok(())
}
