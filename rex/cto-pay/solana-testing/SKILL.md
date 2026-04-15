---
name: solana-testing
version: 1.0.0
description: >
  Solana program and integration testing in Rust — LiteSVM, Mollusk, Surfpool,
  bankrun, and solana-test-validator. Covers unit tests, integration tests,
  fuzzing, and CI patterns.
---

# Solana Testing (Rust)

## Framework Selection

| Framework | Type | Speed | Best for |
|-----------|------|-------|----------|
| **LiteSVM** | In-process SVM | ⚡ Fastest | Unit tests, CPI tests, account state |
| **Mollusk** | In-process SVM | ⚡ Fast | Single-instruction unit tests |
| **Surfpool** | Local cluster | 🔄 Medium | Integration tests with mainnet state |
| **solana-test-validator** | Full validator | 🐢 Slow | RPC behavior, WebSocket, full flow |
| **bankrun** (solana-program-test) | BanksClient | 🔄 Medium | Legacy, program-test compatibility |

**Default choice:** LiteSVM for unit tests, Surfpool for integration tests.

---

## LiteSVM (Recommended)

Fast, in-process Solana Virtual Machine. No validator startup overhead.

### Setup

```toml
[dev-dependencies]
litesvm = "0.6"
solana-sdk = "2.2"
spl-token = "8"
```

### Basic Test

```rust
use litesvm::LiteSVM;
use solana_sdk::{
    instruction::{AccountMeta, Instruction},
    pubkey::Pubkey,
    signature::Keypair,
    signer::Signer,
    system_instruction,
    transaction::Transaction,
};

#[test]
fn test_initialize_vault() {
    let mut svm = LiteSVM::new();

    // Create and fund payer
    let payer = Keypair::new();
    svm.airdrop(&payer.pubkey(), 10_000_000_000).unwrap();

    // Deploy program (from .so file)
    let program_id = Pubkey::new_unique();
    let program_bytes = include_bytes!("../../target/deploy/cto_pay.so");
    svm.add_program(program_id, program_bytes);

    // Derive PDA
    let (vault_pda, _bump) = Pubkey::find_program_address(
        &[b"vault", payer.pubkey().as_ref()],
        &program_id,
    );

    // Build instruction
    let ix = Instruction::new_with_borsh(
        program_id,
        &InitializeVaultArgs { daily_limit: 1_000_000_000 },
        vec![
            AccountMeta::new(vault_pda, false),
            AccountMeta::new(payer.pubkey(), true),
            AccountMeta::new_readonly(solana_sdk::system_program::id(), false),
        ],
    );

    let blockhash = svm.latest_blockhash();
    let tx = Transaction::new_signed_with_payer(
        &[ix],
        Some(&payer.pubkey()),
        &[&payer],
        blockhash,
    );

    let result = svm.send_transaction(tx);
    assert!(result.is_ok(), "Initialize vault failed: {:?}", result.err());

    // Verify account state
    let vault_account = svm.get_account(&vault_pda).unwrap();
    assert_eq!(vault_account.owner, program_id);
    assert!(vault_account.data.len() > 0);
}
```

### Testing with SPL Tokens

```rust
#[test]
fn test_token_payment() {
    let mut svm = LiteSVM::new();
    let payer = Keypair::new();
    svm.airdrop(&payer.pubkey(), 10_000_000_000).unwrap();

    // Add SPL Token program
    svm.add_program_from_file(
        spl_token::id(),
        "tests/fixtures/spl_token.so",
    );

    // Create mint
    let mint = Keypair::new();
    let create_mint_ixs = vec![
        system_instruction::create_account(
            &payer.pubkey(),
            &mint.pubkey(),
            svm.minimum_balance_for_rent_exemption(spl_token::state::Mint::LEN),
            spl_token::state::Mint::LEN as u64,
            &spl_token::id(),
        ),
        spl_token::instruction::initialize_mint2(
            &spl_token::id(),
            &mint.pubkey(),
            &payer.pubkey(),
            None,
            6, // USDC-like decimals
        ).unwrap(),
    ];

    let blockhash = svm.latest_blockhash();
    let tx = Transaction::new_signed_with_payer(
        &create_mint_ixs,
        Some(&payer.pubkey()),
        &[&payer, &mint],
        blockhash,
    );
    svm.send_transaction(tx).unwrap();

    // Create ATA + mint tokens + test transfer...
}
```

### Testing CU Consumption

```rust
#[test]
fn test_compute_budget() {
    let mut svm = LiteSVM::new();
    // ... setup ...

    let result = svm.send_transaction(tx).unwrap();
    let cu_consumed = result.compute_units_consumed;

    // Assert CU is within budget
    assert!(
        cu_consumed < 50_000,
        "Payment instruction consumed too many CUs: {}",
        cu_consumed
    );
}
```

---

## Mollusk

Single-instruction unit testing. Even faster than LiteSVM for isolated tests.

```toml
[dev-dependencies]
mollusk-svm = "0.1"
```

```rust
use mollusk_svm::Mollusk;

#[test]
fn test_single_instruction() {
    let program_id = Pubkey::new_unique();
    let mollusk = Mollusk::new(&program_id, "target/deploy/cto_pay");

    let (vault_pda, bump) = Pubkey::find_program_address(
        &[b"vault", authority.as_ref()],
        &program_id,
    );

    let result = mollusk.process_instruction(
        &instruction,
        &[
            (vault_pda, vault_account),
            (authority, authority_account),
            (system_program::id(), system_account),
        ],
    );

    assert!(!result.program_result.is_err());
}
```

---

## Surfpool (Integration Testing)

Tests against realistic cluster state locally:

```bash
# Install
cargo install surfpool

# Start with mainnet fork
surfpool start --rpc-url https://api.mainnet-beta.solana.com

# Or devnet
surfpool start --rpc-url https://api.devnet.solana.com
```

```rust
#[tokio::test]
async fn test_payment_with_real_tokens() {
    // Surfpool exposes a local RPC at http://localhost:8899
    let rpc = RpcClient::new("http://localhost:8899".to_string());

    // Test against real mainnet token state
    let usdc_mint = Pubkey::from_str("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v").unwrap();
    let mint_info = rpc.get_account(&usdc_mint).await.unwrap();
    assert_eq!(mint_info.owner, spl_token::id());
}
```

---

## Anchor Test Helpers

```rust
use anchor_client::{
    solana_sdk::signature::Keypair,
    Client, Cluster,
};

#[test]
fn test_with_anchor_client() {
    let payer = Keypair::new();
    let client = Client::new(Cluster::Localnet, &payer);
    let program = client.program(program_id).unwrap();

    // Call instruction
    let sig = program
        .request()
        .accounts(cto_pay::accounts::InitializeVault {
            vault: vault_pda,
            authority: payer.pubkey(),
            system_program: system_program::id(),
        })
        .args(cto_pay::instruction::InitializeVault {
            params: VaultParams { daily_limit: 1_000_000_000 },
        })
        .signer(&payer)
        .send()
        .unwrap();
}
```

---

## Fuzzing

### cargo-fuzz + Trident

```toml
# Cargo.toml
[dev-dependencies]
trident-fuzz = "0.8"
```

```rust
use trident_fuzz::fuzz_trident;

fuzz_trident!(fuzz_target = |data: &[u8]| {
    // Parse fuzz input into instruction data
    if let Ok(args) = borsh::from_slice::<PaymentArgs>(data) {
        // Execute instruction with fuzzed args
        // Check invariants hold
    }
});
```

---

## CI Pattern

```yaml
# .github/workflows/test.yml
name: Solana Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: dtolnay/rust-toolchain@stable

      - name: Install Solana CLI
        run: |
          sh -c "$(curl -sSfL https://release.anza.xyz/stable/install)"
          echo "$HOME/.local/share/solana/install/active_release/bin" >> $GITHUB_PATH

      - name: Build program
        run: anchor build

      - name: Run tests
        run: cargo nextest run --workspace

      - name: Run LiteSVM tests
        run: cargo nextest run -p cto-pay-tests
```

---

## Test Organization

```
tests/
├── fixtures/
│   ├── spl_token.so          # SPL Token program binary
│   └── test-accounts.json     # Serialized test account state
├── unit/
│   ├── test_initialize.rs     # LiteSVM unit tests
│   ├── test_payment.rs
│   └── test_limits.rs
├── integration/
│   ├── test_full_flow.rs      # Surfpool integration tests
│   └── test_token_flow.rs
└── fuzz/
    └── fuzz_payment.rs        # Trident fuzz targets
```
