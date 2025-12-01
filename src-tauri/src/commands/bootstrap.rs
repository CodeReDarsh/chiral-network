// Shared bootstrap node configuration
// This module provides bootstrap nodes for both Tauri commands and headless mode

use tauri::command;

pub fn get_bootstrap_nodes() -> Vec<String> {
    vec![
        // GCP relay node - TESTING ONLY (temporarily using only this node)
        "/ip4/35.237.133.42/tcp/4001/p2p/12D3KooWBeY3FuPXggnUu8f56TQde1xfvFpdsLV5coXptn5ztVJG"
            .to_string(),

        // Other bootstrap nodes temporarily commented out for testing
        // Uncomment these after verifying GCP relay connection
        // "/ip4/134.199.240.145/tcp/4001/p2p/12D3KooWFYTuQ2FY8tXRtFKfpXkTSipTF55mZkLntwtN1nHu83qE"
        //     .to_string(),
        // "/ip4/104.198.62.217/tcp/4001/p2p/12D3KooWETLNJUVLbkAbenbSPPdwN9ZLkBU3TLfyAeEUW2dsVptr"
        //     .to_string(),
        // "/ip4/104.198.62.217/tcp/4002/p2p/12D3KooWGV5BUSYMhNMrhdPh9EUbuLrvAiDsMXEMRpGGvt4LQneA"
        //     .to_string(),
        // "/ip4/130.245.173.105/tcp/4001/p2p/12D3KooWSDDA2jyo6Cynr7SHPfhdQoQazu1jdUEAp7rLKKKLqqTr"
        //     .to_string(),
    ]
}

#[command]
pub fn get_bootstrap_nodes_command() -> Vec<String> {
    get_bootstrap_nodes()
}
