---
name: solana-sdk-patterns
version: 1.0.0
description: >
  Solana Rust SDK patterns — solana-sdk, solana-client, solana-program crate usage,
  RPC client patterns, transaction building, and keypair management for off-chain
  Rust services and CLI tools.
---

# Solana Rust SDK Patterns

Patterns for Rust services, CLI tools, and off-chain code that interact with Solana.

## Crate Map

| Crate | Use for | Version guidance |
|-------|---------|-----------------|
| `solana-sdk` | Off-chain: keypairs, transactions, signatures | Match cluster version |
| `solana-client` | RPC client (`RpcClient`, `nonblocking::RpcClient`) | Match cluster version |
| `solana-program` | On-chain program code | Match cluster version |
| `solana-transaction-status` | Parsing confirmed transactions | Match cluster version |
| `spl-token` | SPL token instruction builders (off-chain) | Latest compatible |
| `spl-associated-token-account` | ATA derivation and creation | Latest compatible |
| `anchor-client` | Typed Anchor program interaction | Match Anchor version |
| `yellowstone-grpc-client` | gRPC streaming (accounts, transactions, slots) | Match plugin version |

### Cargo.toml

```toml
[dependencies]
solana-sdk = "2.2"
solana-client = "2.2"
solana-transaction-status = "2.2"
spl-token = "8"
spl-associated-token-account = "6"
anchor-client = "0.31"

# Async runtime
tokio = { version = "1", features = ["full"] }

# For gRPC streaming
yellowstone-grpc-client = { git = "https://github.com/rpcpool/yellowstone-grpc", tag = "v12.2.0+solana.3.1.10" }
yellowstone-grpc-proto = { git = "https://github.com/rpcpool/yellowstone-grpc", tag = "v12.2.0+solana.3.1.10" }
```

---

## RPC Client Patterns

### Synchronous Client

```rust
use solana_client::rpc_client::RpcClient;
use solana_sdk::commitment_config::CommitmentConfig;

let rpc = RpcClient::new_with_commitment(
    "https://api.mainnet-beta.solana.com".to_string(),
    CommitmentConfig::confirmed(),
);

// Basic queries
let balance = rpc.get_balance(&pubkey)?;
let slot = rpc.get_slot()?;
let blockhash = rpc.get_latest_blockhash()?;
```

### Async Client

```rust
use solana_client::nonblocking::rpc_client::RpcClient;

let rpc = RpcClient::new_with_commitment(
    "https://api.mainnet-beta.solana.com".to_string(),
    CommitmentConfig::confirmed(),
);

let balance = rpc.get_balance(&pubkey).await?;
```

### Custom RPC (internal node)

```rust
// Connect to our Agave RPC node (hostNetwork on K8s)
let rpc = RpcClient::new_with_commitment(
    std::env::var("SOLANA_RPC_URL")
        .unwrap_or_else(|_| "http://agave-rpc.solana.svc:8899".to_string()),
    CommitmentConfig::confirmed(),
);
```

---

## Transaction Building

### Simple SOL Transfer

```rust
use solana_sdk::{
    signature::{Keypair, Signer},
    system_instruction,
    transaction::Transaction,
};

fn transfer_sol(
    rpc: &RpcClient,
    payer: &Keypair,
    recipient: &Pubkey,
    lamports: u64,
) -> Result<Signature, Box<dyn std::error::Error>> {
    let ix = system_instruction::transfer(&payer.pubkey(), recipient, lamports);
    let blockhash = rpc.get_latest_blockhash()?;
    let tx = Transaction::new_signed_with_payer(
        &[ix],
        Some(&payer.pubkey()),
        &[payer],
        blockhash,
    );
    let sig = rpc.send_and_confirm_transaction(&tx)?;
    Ok(sig)
}
```

### With Priority Fees

```rust
use solana_sdk::compute_budget::ComputeBudgetInstruction;

fn build_priority_tx(
    payer: &Keypair,
    instructions: Vec<Instruction>,
    cu_limit: u32,
    priority_fee_microlamports: u64,
    blockhash: Hash,
) -> Transaction {
    let mut ixs = vec![
        ComputeBudgetInstruction::set_compute_unit_limit(cu_limit),
        ComputeBudgetInstruction::set_compute_unit_price(priority_fee_microlamports),
    ];
    ixs.extend(instructions);

    Transaction::new_signed_with_payer(
        &ixs,
        Some(&payer.pubkey()),
        &[payer],
        blockhash,
    )
}
```

### Versioned Transactions (Address Lookup Tables)

```rust
use solana_sdk::{
    message::{v0, VersionedMessage},
    transaction::VersionedTransaction,
};

fn build_v0_tx(
    payer: &Keypair,
    instructions: Vec<Instruction>,
    address_lookup_tables: Vec<AddressLookupTableAccount>,
    blockhash: Hash,
) -> Result<VersionedTransaction, Box<dyn std::error::Error>> {
    let msg = v0::Message::try_compile(
        &payer.pubkey(),
        &instructions,
        &address_lookup_tables,
        blockhash,
    )?;
    let tx = VersionedTransaction::try_new(
        VersionedMessage::V0(msg),
        &[payer],
    )?;
    Ok(tx)
}
```

---

## SPL Token Operations

### Create Associated Token Account

```rust
use spl_associated_token_account::{
    get_associated_token_address,
    instruction::create_associated_token_account,
};

let ata = get_associated_token_address(&owner, &mint);
let create_ata_ix = create_associated_token_account(
    &payer.pubkey(),  // funding account
    &owner,           // wallet that owns the ATA
    &mint,            // token mint
    &spl_token::id(), // token program (or spl_token_2022::id())
);
```

### Transfer Tokens

```rust
use spl_token::instruction::transfer_checked;

let transfer_ix = transfer_checked(
    &spl_token::id(),
    &source_ata,         // source token account
    &mint,               // mint (for decimals verification)
    &destination_ata,    // destination token account
    &authority,          // owner of source
    &[],                 // multisig signers (usually empty)
    amount,              // raw token amount
    decimals,            // mint decimals (e.g., 6 for USDC)
)?;
```

### Get Token Balance

```rust
let token_balance = rpc.get_token_account_balance(&ata)?;
println!("Balance: {} ({})", token_balance.ui_amount_string, token_balance.amount);
```

---

## Keypair Management

### ⚠️ Security Rules

1. **NEVER hardcode private keys** in source code
2. **NEVER log keypair bytes** — not even in debug builds
3. Load from environment or K8s secrets only
4. Use `Keypair::from_bytes()` with `zeroize` crate for memory cleanup
5. For agents: keypairs are per-pod K8s Secrets (see `identitySecret` in CRD)

### Loading Keypairs

```rust
use solana_sdk::signature::Keypair;
use std::fs;

// From file (local dev / K8s secret mount)
fn load_keypair(path: &str) -> Result<Keypair, Box<dyn std::error::Error>> {
    let bytes = fs::read(path)?;
    let json: Vec<u8> = serde_json::from_slice(&bytes)?;
    Ok(Keypair::from_bytes(&json)?)
}

// From environment (base58-encoded)
fn load_keypair_from_env(var: &str) -> Result<Keypair, Box<dyn std::error::Error>> {
    let encoded = std::env::var(var)?;
    let bytes = bs58::decode(&encoded).into_vec()?;
    Ok(Keypair::from_bytes(&bytes)?)
}

// ⚠️ Standard paths for cto-pay:
// K8s: /etc/solana/agent-keypair.json (mounted from Secret)
// Env: SOLANA_KEYPAIR_PATH or SOLANA_PRIVATE_KEY
```

### Read-Only Public Key (Preferred)

```rust
use solana_sdk::pubkey::Pubkey;
use std::str::FromStr;

// When you only need the public key (most operations)
let pubkey = Pubkey::from_str("PAYxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")?;
```

---

## Yellowstone gRPC Streaming

For real-time account and transaction monitoring:

```rust
use yellowstone_grpc_client::GeyserGrpcClient;
use yellowstone_grpc_proto::prelude::*;

async fn subscribe_account_updates(
    endpoint: &str,
    accounts: Vec<String>,
) -> Result<(), Box<dyn std::error::Error>> {
    let mut client = GeyserGrpcClient::connect(endpoint, None, None)?;

    let mut accounts_filter = HashMap::new();
    accounts_filter.insert(
        "vault_watch".to_string(),
        SubscribeRequestFilterAccounts {
            account: accounts,
            owner: vec![],
            filters: vec![],
            nonempty_txn_signature: None,
        },
    );

    let (mut subscribe, _) = client
        .subscribe_with_request(Some(SubscribeRequest {
            accounts: accounts_filter,
            ..Default::default()
        }))
        .await?;

    while let Some(msg) = subscribe.next().await {
        match msg?.update_oneof {
            Some(UpdateOneof::Account(account)) => {
                println!("Account updated: {:?}", account);
            }
            _ => {}
        }
    }
    Ok(())
}
```

---

## Error Handling Pattern

```rust
use thiserror::Error;
use solana_client::client_error::ClientError;
use solana_sdk::program_error::ProgramError;

#[derive(Error, Debug)]
pub enum PayServiceError {
    #[error("RPC error: {0}")]
    Rpc(#[from] ClientError),

    #[error("Transaction simulation failed: {0}")]
    Simulation(String),

    #[error("Insufficient balance: need {needed} lamports, have {available}")]
    InsufficientBalance { needed: u64, available: u64 },

    #[error("Daily limit exceeded for vault {vault}")]
    DailyLimitExceeded { vault: String },

    #[error("Keypair error: {0}")]
    Keypair(String),
}
```

---

## Testing Utilities

```rust
#[cfg(test)]
mod tests {
    use solana_sdk::signature::Keypair;
    use solana_sdk::signer::Signer;

    /// Create a funded keypair for tests (never use in production)
    fn test_keypair() -> Keypair {
        Keypair::new()
    }

    /// Assert transaction succeeded
    fn assert_tx_success(rpc: &RpcClient, sig: &Signature) {
        let status = rpc
            .get_signature_status(sig)
            .unwrap()
            .expect("Transaction not found");
        assert!(status.is_ok(), "Transaction failed: {:?}", status);
    }
}
```
