---
name: anchor-framework
description: Deep expertise in the Anchor framework for Solana program development.
version: 1.0.0
tags: [anchor, solana, rust, framework]
---

# Anchor Framework

The Anchor framework provides a structured, opinionated approach to Solana program development with automatic account validation, serialization, and IDL generation.

## Project Structure

```
my_project/
├── Anchor.toml              # Workspace config (cluster, programs, test command)
├── programs/
│   └── my_program/
│       ├── Cargo.toml
│       └── src/
│           └── lib.rs        # Program entry point
├── tests/
│   └── my_program.ts         # Integration tests
├── migrations/
│   └── deploy.ts             # Deploy scripts
├── app/                      # Optional frontend
└── target/
    ├── idl/                  # Generated IDL JSON
    └── types/                # Generated TypeScript types
```

### Anchor.toml

```toml
[features]
seeds = false
skip-lint = false

[programs.devnet]
my_program = "Fg6PaFpoGXkYsidMpWTK6W2BeZ7FEfcYkg476zPFsLnS"

[registry]
url = "https://api.apr.dev"

[provider]
cluster = "devnet"
wallet = "~/.config/solana/id.json"

[scripts]
test = "yarn run ts-mocha -p ./tsconfig.json -t 1000000 tests/**/*.ts"
```

---

## Key Macros & Attributes

### `declare_id!`

Sets the program ID. Must match the deployed keypair:

```rust
declare_id!("Fg6PaFpoGXkYsidMpWTK6W2BeZ7FEfcYkg476zPFsLnS");
```

### `#[program]`

Defines the instruction handlers:

```rust
#[program]
pub mod my_program {
    use super::*;

    pub fn initialize(ctx: Context<Initialize>, name: String) -> Result<()> {
        let account = &mut ctx.accounts.my_account;
        account.authority = ctx.accounts.authority.key();
        account.name = name;
        account.bump = ctx.bumps.my_account;
        Ok(())
    }

    pub fn update(ctx: Context<Update>, new_name: String) -> Result<()> {
        let account = &mut ctx.accounts.my_account;
        account.name = new_name;
        Ok(())
    }
}
```

### `#[derive(Accounts)]`

Defines account validation for an instruction:

```rust
#[derive(Accounts)]
#[instruction(name: String)]
pub struct Initialize<'info> {
    #[account(
        init,
        payer = authority,
        space = 8 + 32 + 4 + name.len() + 1,
        seeds = [b"my_account", authority.key().as_ref()],
        bump,
    )]
    pub my_account: Account<'info, MyAccount>,

    #[account(mut)]
    pub authority: Signer<'info>,

    pub system_program: Program<'info, System>,
}
```

### `#[account]`

Defines account data structures (auto-adds 8-byte discriminator):

```rust
#[account]
pub struct MyAccount {
    pub authority: Pubkey,  // 32
    pub name: String,       // 4 + len
    pub bump: u8,           // 1
}
```

---

## Account Constraints

| Constraint | Purpose | Example |
|-----------|---------|---------|
| `init` | Create account | `#[account(init, payer = user, space = 100)]` |
| `init_if_needed` | Create if missing | `#[account(init_if_needed, payer = user, space = 100)]` |
| `mut` | Mark mutable | `#[account(mut)]` |
| `seeds` | PDA seeds | `#[account(seeds = [b"seed", user.key().as_ref()], bump)]` |
| `bump` | PDA bump | `#[account(bump = account.bump)]` (known) or `bump` (find) |
| `has_one` | Field match | `#[account(has_one = authority)]` |
| `constraint` | Custom check | `#[account(constraint = amount > 0 @ MyError::InvalidAmount)]` |
| `close` | Close account | `#[account(mut, close = destination)]` |
| `realloc` | Resize account | `#[account(mut, realloc = new_size, realloc::payer = payer, realloc::zero = false)]` |
| `token::mint` | Validate token mint | `#[account(token::mint = mint, token::authority = authority)]` |
| `associated_token::mint` | ATA validation | `#[account(associated_token::mint = mint, associated_token::authority = user)]` |

---

## Error Handling

```rust
#[error_code]
pub enum MyError {
    #[msg("The provided name is too long (max 32 chars)")]
    NameTooLong,
    #[msg("Unauthorized: signer is not the authority")]
    Unauthorized,
    #[msg("Invalid amount: must be greater than zero")]
    InvalidAmount,
    #[msg("Account already initialized")]
    AlreadyInitialized,
}

// Usage in instruction:
pub fn update(ctx: Context<Update>, name: String) -> Result<()> {
    require!(name.len() <= 32, MyError::NameTooLong);
    require_keys_eq!(
        ctx.accounts.my_account.authority,
        ctx.accounts.authority.key(),
        MyError::Unauthorized
    );
    Ok(())
}
```

---

## CPI Patterns

### Simple CPI

```rust
use anchor_lang::prelude::*;
use anchor_spl::token::{self, Transfer, Token, TokenAccount};

pub fn pay(ctx: Context<Pay>, amount: u64) -> Result<()> {
    let cpi_ctx = CpiContext::new(
        ctx.accounts.token_program.to_account_info(),
        Transfer {
            from: ctx.accounts.source.to_account_info(),
            to: ctx.accounts.destination.to_account_info(),
            authority: ctx.accounts.authority.to_account_info(),
        },
    );
    token::transfer(cpi_ctx, amount)
}
```

### CPI with PDA Signer (invoke_signed)

```rust
pub fn pay_from_vault(ctx: Context<PayFromVault>, amount: u64) -> Result<()> {
    let seeds = &[
        b"vault".as_ref(),
        ctx.accounts.vault.authority.as_ref(),
        &[ctx.accounts.vault.bump],
    ];
    let signer_seeds = &[&seeds[..]];

    let cpi_ctx = CpiContext::new_with_signer(
        ctx.accounts.token_program.to_account_info(),
        Transfer {
            from: ctx.accounts.vault_ata.to_account_info(),
            to: ctx.accounts.destination.to_account_info(),
            authority: ctx.accounts.vault.to_account_info(),
        },
        signer_seeds,
    );
    token::transfer(cpi_ctx, amount)
}
```

---

## Testing

### TypeScript Integration Tests

```typescript
import * as anchor from "@coral-xyz/anchor";
import { Program } from "@coral-xyz/anchor";
import { MyProgram } from "../target/types/my_program";
import { expect } from "chai";

describe("my_program", () => {
  const provider = anchor.AnchorProvider.env();
  anchor.setProvider(provider);
  const program = anchor.workspace.MyProgram as Program<MyProgram>;

  it("initializes", async () => {
    const [pda] = anchor.web3.PublicKey.findProgramAddressSync(
      [Buffer.from("my_account"), provider.wallet.publicKey.toBuffer()],
      program.programId
    );

    await program.methods
      .initialize("test")
      .accounts({
        myAccount: pda,
        authority: provider.wallet.publicKey,
        systemProgram: anchor.web3.SystemProgram.programId,
      })
      .rpc();

    const account = await program.account.myAccount.fetch(pda);
    expect(account.name).to.equal("test");
  });

  it("fails with unauthorized signer", async () => {
    const attacker = anchor.web3.Keypair.generate();
    try {
      await program.methods
        .update("hacked")
        .accounts({ myAccount: pda, authority: attacker.publicKey })
        .signers([attacker])
        .rpc();
      expect.fail("Should have thrown");
    } catch (err) {
      expect(err.error.errorCode.code).to.equal("Unauthorized");
    }
  });
});
```

### Bankrun (Fast Tests)

```typescript
import { startAnchor } from "solana-bankrun";
import { BankrunProvider } from "anchor-bankrun";
import { Program } from "@coral-xyz/anchor";

const context = await startAnchor(".", [], []);
const provider = new BankrunProvider(context);
const program = new Program(idl, provider);

await program.methods.initialize("test").rpc();
```

---

## Build & Deploy Workflow

```bash
# Build (compiles .so, generates IDL and types)
anchor build

# Show program keypair address
solana address -k target/deploy/my_program-keypair.json

# Deploy to devnet
anchor deploy --provider.cluster devnet

# Deploy to mainnet (use with caution)
anchor deploy --provider.cluster mainnet

# Upgrade existing program
anchor upgrade target/deploy/my_program.so --program-id <PROGRAM_ID>

# Initialize / update IDL on-chain
anchor idl init <PROGRAM_ID> --filepath target/idl/my_program.json
anchor idl upgrade <PROGRAM_ID> --filepath target/idl/my_program.json

# Run tests
anchor test                    # Starts local validator, deploys, runs tests
anchor test --skip-local-validator  # Use existing validator
anchor test --skip-deploy      # Skip deploy step
```
