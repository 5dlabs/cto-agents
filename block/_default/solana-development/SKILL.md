---
name: solana-development
description: Solana program development with Rust, Anchor, SPL, and client-side tooling.
version: 1.0.0
tags: [solana, rust, anchor, spl, web3]
---

# Solana Development

Comprehensive skill for building on-chain programs and client applications on Solana.

## Core Concepts

### Account Model

Solana uses an **account-based model** where all state is stored in accounts:

- **Programs** are stateless, executable accounts (marked `executable: true`)
- **Data accounts** store state; every data account has an **owner** program
- Only the owner program can modify an account's data or debit its lamports
- Accounts must be **rent-exempt** (hold ≥ 2 years rent in lamports) or be garbage-collected

Key account fields: `pubkey`, `lamports`, `data`, `owner`, `executable`, `rent_epoch`.

### Instructions & Transactions

- An **instruction** targets one program and includes: program ID, account metas, and data
- A **transaction** bundles 1+ instructions, is signed, and is atomic (all-or-nothing)
- **Versioned transactions** (v0) support **address lookup tables** (ALTs) for more accounts per tx
- Each tx has a 1232-byte size limit and a default 200k **compute unit** budget (max 1.4M with `SetComputeUnitLimit`)

### Commitment Levels

| Level | Meaning |
|-------|---------|
| `processed` | Node processed; no confirmation |
| `confirmed` | Supermajority voted (most common) |
| `finalized` | 31+ confirmed slots (~13s) |

### Slots & Epochs

- **Slot**: ~400ms window for a leader to produce a block
- **Epoch**: 432,000 slots (~2–3 days)

---

## On-Chain Program Development (Rust)

### Project Setup

```bash
# Install Solana CLI
sh -c "$(curl -sSfL https://release.anza.xyz/stable/install)"

# Install Anchor
cargo install --git https://github.com/coral-xyz/anchor avm --force
avm install latest && avm use latest

# New Anchor project
anchor init my_program
```

### Program Derived Addresses (PDAs)

PDAs are deterministic addresses derived from seeds + program ID, not on the ed25519 curve (no private key):

```rust
use anchor_lang::prelude::*;

#[derive(Accounts)]
#[instruction(identifier: String)]
pub struct CreateVault<'info> {
    #[account(
        init,
        payer = authority,
        space = 8 + 32 + 4 + identifier.len() + 8,
        seeds = [b"vault", authority.key().as_ref(), identifier.as_bytes()],
        bump,
    )]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[account]
pub struct Vault {
    pub authority: Pubkey,
    pub identifier: String,
    pub balance: u64,
}
```

Client-side PDA derivation:

```typescript
import { PublicKey } from "@solana/web3.js";

const [vaultPda, bump] = PublicKey.findProgramAddressSync(
  [Buffer.from("vault"), authority.toBuffer(), Buffer.from(identifier)],
  programId
);
```

### Cross-Program Invocations (CPIs)

```rust
use anchor_lang::prelude::*;
use anchor_spl::token::{self, Transfer, TokenAccount, Token};

pub fn transfer_tokens(ctx: Context<TransferTokens>, amount: u64) -> Result<()> {
    let cpi_accounts = Transfer {
        from: ctx.accounts.from_ata.to_account_info(),
        to: ctx.accounts.to_ata.to_account_info(),
        authority: ctx.accounts.signer.to_account_info(),
    };
    let cpi_program = ctx.accounts.token_program.to_account_info();
    token::transfer(CpiContext::new(cpi_program, cpi_accounts), amount)?;
    Ok(())
}

#[derive(Accounts)]
pub struct TransferTokens<'info> {
    #[account(mut)]
    pub from_ata: Account<'info, TokenAccount>,
    #[account(mut)]
    pub to_ata: Account<'info, TokenAccount>,
    pub signer: Signer<'info>,
    pub token_program: Program<'info, Token>,
}
```

### Serialization & Space Calculation

Anchor uses **Borsh** serialization. Space formula:

| Type | Bytes |
|------|-------|
| `bool` | 1 |
| `u8` / `i8` | 1 |
| `u16` / `i16` | 2 |
| `u32` / `i32` | 4 |
| `u64` / `i64` | 8 |
| `u128` / `i128` | 16 |
| `Pubkey` | 32 |
| `String` | 4 + len |
| `Vec<T>` | 4 + (len × T) |
| `Option<T>` | 1 + T |
| Account discriminator | 8 |

---

## Client-Side Development

### @solana/web3.js v2

```typescript
import {
  createSolanaRpc,
  createSolanaRpcSubscriptions,
  generateKeyPairSigner,
  getAddressFromPublicKey,
  pipe,
  createTransactionMessage,
  setTransactionMessageFeePayer,
  setTransactionMessageLifetimeUsingBlockhash,
  appendTransactionMessageInstruction,
  signTransactionMessageWithSigners,
  sendAndConfirmTransactionFactory,
} from "@solana/kit";

// Connect
const rpc = createSolanaRpc("https://api.mainnet-beta.solana.com");
const rpcSubscriptions = createSolanaRpcSubscriptions("wss://api.mainnet-beta.solana.com");

// Get balance
const balance = await rpc.getBalance(address).send();

// Build and send a transaction
const { value: latestBlockhash } = await rpc.getLatestBlockhash().send();

const transactionMessage = pipe(
  createTransactionMessage({ version: 0 }),
  (tx) => setTransactionMessageFeePayer(feePayer.address, tx),
  (tx) => setTransactionMessageLifetimeUsingBlockhash(latestBlockhash, tx),
  (tx) => appendTransactionMessageInstruction(myInstruction, tx),
);

const signedTx = await signTransactionMessageWithSigners(transactionMessage);
const sendAndConfirm = sendAndConfirmTransactionFactory({ rpc, rpcSubscriptions });
const signature = await sendAndConfirm(signedTx, { commitment: "confirmed" });
```

### SPL Token Operations

```typescript
import {
  createMint,
  getOrCreateAssociatedTokenAccount,
  mintTo,
  transfer,
} from "@solana/spl-token";

// Create a new token mint
const mint = await createMint(
  connection,
  payer,
  mintAuthority.publicKey,
  freezeAuthority.publicKey,
  9 // decimals
);

// Get or create ATA
const ata = await getOrCreateAssociatedTokenAccount(
  connection, payer, mint, owner.publicKey
);

// Mint tokens
await mintTo(connection, payer, mint, ata.address, mintAuthority, 1_000_000_000n);

// Transfer tokens
await transfer(connection, payer, sourceAta, destAta, owner, 500_000_000n);
```

### Priority Fees & Compute Budget

```typescript
import {
  ComputeBudgetProgram,
  Transaction,
} from "@solana/web3.js";

const tx = new Transaction().add(
  ComputeBudgetProgram.setComputeUnitLimit({ units: 400_000 }),
  ComputeBudgetProgram.setComputeUnitPrice({ microLamports: 50_000 }),
  // ... your instructions
);
```

---

## RPC Endpoints

| Network | HTTP | WebSocket |
|---------|------|-----------|
| Mainnet | `https://api.mainnet-beta.solana.com` | `wss://api.mainnet-beta.solana.com` |
| Devnet | `https://api.devnet.solana.com` | `wss://api.devnet.solana.com` |
| Localnet | `http://127.0.0.1:8899` | `ws://127.0.0.1:8900` |

> **Tip:** Use a dedicated RPC provider (Helius, Triton, QuickNode) for production. Public endpoints are rate-limited.

---

## CLI Tools

```bash
# Solana CLI
solana config set --url devnet
solana balance
solana airdrop 2
solana transfer <RECIPIENT> 1 --allow-unfunded-recipient

# SPL Token CLI
spl-token create-token
spl-token create-account <MINT>
spl-token mint <MINT> 1000

# Anchor CLI
anchor build
anchor deploy
anchor test
anchor idl init <PROGRAM_ID> --filepath target/idl/my_program.json

# Local validator
solana-test-validator
solana-test-validator --clone <PROGRAM_ID> --url mainnet-beta
```

---

## Testing

### Anchor Integration Tests (TypeScript)

```typescript
import * as anchor from "@coral-xyz/anchor";
import { Program } from "@coral-xyz/anchor";
import { MyProgram } from "../target/types/my_program";
import { expect } from "chai";

describe("my_program", () => {
  const provider = anchor.AnchorProvider.env();
  anchor.setProvider(provider);
  const program = anchor.workspace.MyProgram as Program<MyProgram>;

  it("initializes vault", async () => {
    const [vaultPda] = anchor.web3.PublicKey.findProgramAddressSync(
      [Buffer.from("vault"), provider.wallet.publicKey.toBuffer()],
      program.programId
    );
    await program.methods
      .initialize("my-vault")
      .accounts({ vault: vaultPda, authority: provider.wallet.publicKey })
      .rpc();

    const vault = await program.account.vault.fetch(vaultPda);
    expect(vault.authority.toBase58()).to.equal(provider.wallet.publicKey.toBase58());
  });
});
```

### Bankrun (Fast Solana Testing)

```typescript
import { start } from "solana-bankrun";
import { PublicKey, Transaction, SystemProgram } from "@solana/web3.js";

const context = await start(
  [{ name: "my_program", programId: new PublicKey("...") }],
  []
);
const client = context.banksClient;
const payer = context.payer;

const blockhash = context.lastBlockhash;
const tx = new Transaction();
tx.recentBlockhash = blockhash;
tx.add(/* instruction */);
tx.sign(payer);
await client.processTransaction(tx);
```

### solana-program-test (Rust)

```rust
use solana_program_test::*;
use solana_sdk::{signature::Signer, transaction::Transaction};

#[tokio::test]
async fn test_initialize() {
    let program_id = Pubkey::new_unique();
    let mut test = ProgramTest::new("my_program", program_id, processor!(process_instruction));
    let (mut banks_client, payer, recent_blockhash) = test.start().await;

    let tx = Transaction::new_signed_with_payer(
        &[/* instruction */],
        Some(&payer.pubkey()),
        &[&payer],
        recent_blockhash,
    );
    banks_client.process_transaction(tx).await.unwrap();
}
```

---

## Security Checklist

| Check | Description |
|-------|-------------|
| **Signer checks** | Verify all expected accounts are signers |
| **Owner checks** | Confirm account owners match expected programs |
| **PDA validation** | Re-derive PDA seeds and verify bump; don't trust client-provided bumps |
| **Integer overflow** | Use `checked_add`, `checked_mul`, `checked_sub` — never raw arithmetic |
| **Close account drain** | When closing, zero data and transfer all lamports atomically |
| **Duplicate accounts** | Ensure distinct accounts when multiple account metas are expected |
| **Reinitialization** | Guard `init` with a discriminator check or use Anchor's `init` constraint |
| **Type cosplay** | Verify account discriminators to prevent type confusion |
| **Arbitrary CPI** | Validate program IDs before CPI calls |
| **Remaining accounts** | Validate any accounts passed via `remaining_accounts` |
