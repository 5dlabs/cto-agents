---
name: solana-program-development
version: 1.0.0
description: >
  Solana on-chain program development in Rust — Anchor (default) and Pinocchio
  (performance). Covers account validation, PDAs, CPIs, SPL token operations,
  and the cto-pay payment system patterns.
---

# Solana Program Development (Rust)

## Framework Selection

| Criterion | Anchor | Pinocchio |
|-----------|--------|-----------|
| **Use when** | Fast iteration, IDL generation, mature tooling | Max CU efficiency, minimal binary, zero deps |
| **CU overhead** | Baseline | ~84% savings vs Anchor |
| **IDL** | Auto-generated | Manual |
| **Best for** | Most programs, cto-pay default | Hot-path instructions, token vaults |

**Default to Anchor** unless CU budget is critical.

---

## Anchor Programs

### Project Setup

```bash
anchor init cto-pay --template single
cd cto-pay
```

### Core Structure

```rust
use anchor_lang::prelude::*;

declare_id!("PAYxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx");

#[program]
pub mod cto_pay {
    use super::*;

    pub fn initialize_vault(ctx: Context<InitializeVault>, params: VaultParams) -> Result<()> {
        let vault = &mut ctx.accounts.vault;
        vault.authority = ctx.accounts.authority.key();
        vault.bump = ctx.bumps.vault;
        vault.daily_limit = params.daily_limit;
        vault.spent_today = 0;
        vault.last_reset = Clock::get()?.unix_timestamp;
        Ok(())
    }

    pub fn execute_payment(ctx: Context<ExecutePayment>, amount: u64) -> Result<()> {
        let vault = &mut ctx.accounts.vault;

        // Reset daily spend if new day
        let now = Clock::get()?.unix_timestamp;
        if now - vault.last_reset >= 86_400 {
            vault.spent_today = 0;
            vault.last_reset = now;
        }

        require!(
            vault.spent_today.checked_add(amount).unwrap() <= vault.daily_limit,
            PayError::DailyLimitExceeded
        );
        vault.spent_today += amount;

        // Transfer SOL from vault PDA
        let seeds = &[b"vault", vault.authority.as_ref(), &[vault.bump]];
        let signer_seeds = &[&seeds[..]];

        anchor_lang::system_program::transfer(
            CpiContext::new_with_signer(
                ctx.accounts.system_program.to_account_info(),
                anchor_lang::system_program::Transfer {
                    from: ctx.accounts.vault_sol.to_account_info(),
                    to: ctx.accounts.recipient.to_account_info(),
                },
                signer_seeds,
            ),
            amount,
        )?;

        Ok(())
    }
}
```

### Account Definitions

```rust
#[derive(Accounts)]
pub struct InitializeVault<'info> {
    #[account(
        init,
        payer = authority,
        space = 8 + Vault::INIT_SPACE,
        seeds = [b"vault", authority.key().as_ref()],
        bump,
    )]
    pub vault: Account<'info, Vault>,

    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct ExecutePayment<'info> {
    #[account(
        mut,
        seeds = [b"vault", vault.authority.as_ref()],
        bump = vault.bump,
        has_one = authority @ PayError::Unauthorized,
    )]
    pub vault: Account<'info, Vault>,

    /// CHECK: PDA that holds SOL
    #[account(
        mut,
        seeds = [b"vault", vault.authority.as_ref()],
        bump = vault.bump,
    )]
    pub vault_sol: UncheckedAccount<'info>,

    #[account(mut)]
    /// CHECK: Recipient can be any account
    pub recipient: UncheckedAccount<'info>,

    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[account]
#[derive(InitSpace)]
pub struct Vault {
    pub authority: Pubkey,
    pub bump: u8,
    pub daily_limit: u64,
    pub spent_today: u64,
    pub last_reset: i64,
}

#[error_code]
pub enum PayError {
    #[msg("Daily spending limit exceeded")]
    DailyLimitExceeded,
    #[msg("Unauthorized — signer is not vault authority")]
    Unauthorized,
}
```

### Account Constraints Reference

| Constraint | Purpose |
|-----------|---------|
| `init, payer, space` | Create + fund new account |
| `seeds, bump` | PDA derivation and validation |
| `has_one = field` | Verify account field matches a signer/key |
| `constraint = expr` | Arbitrary boolean check |
| `mut` | Account is writable |
| `close = target` | Close account, send rent to target |
| `realloc, realloc::payer, realloc::zero` | Resize account data |
| `token::mint, token::authority` | SPL token account validation |

### SPL Token Operations (Anchor)

```rust
use anchor_spl::token::{self, Token, TokenAccount, Mint, Transfer};

#[derive(Accounts)]
pub struct TokenPayment<'info> {
    #[account(
        mut,
        token::mint = mint,
        token::authority = vault,
    )]
    pub vault_token: Account<'info, TokenAccount>,

    #[account(mut)]
    pub recipient_token: Account<'info, TokenAccount>,

    pub mint: Account<'info, Mint>,

    #[account(seeds = [b"vault", authority.key().as_ref()], bump)]
    pub vault: Account<'info, Vault>,

    pub authority: Signer<'info>,
    pub token_program: Program<'info, Token>,
}

pub fn transfer_tokens(ctx: Context<TokenPayment>, amount: u64) -> Result<()> {
    let seeds = &[b"vault", ctx.accounts.authority.key().as_ref(), &[ctx.accounts.vault.bump]];
    token::transfer(
        CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            Transfer {
                from: ctx.accounts.vault_token.to_account_info(),
                to: ctx.accounts.recipient_token.to_account_info(),
                authority: ctx.accounts.vault.to_account_info(),
            },
            &[seeds],
        ),
        amount,
    )
}
```

### Token-2022 (Token Extensions)

```rust
use anchor_spl::token_2022::{self, Token2022};
use anchor_spl::token_interface::{TokenAccount, Mint, TokenInterface};

// Use TokenInterface for programs that support both SPL Token and Token-2022
#[derive(Accounts)]
pub struct FlexibleTransfer<'info> {
    #[account(mut)]
    pub source: InterfaceAccount<'info, TokenAccount>,
    #[account(mut)]
    pub destination: InterfaceAccount<'info, TokenAccount>,
    pub mint: InterfaceAccount<'info, Mint>,
    pub authority: Signer<'info>,
    pub token_program: Interface<'info, TokenInterface>,
}
```

---

## Pinocchio Programs

For CU-critical paths (e.g., high-frequency payment processing).

### Entrypoint Pattern

```rust
use pinocchio::{
    account::AccountView,
    address::Address,
    entrypoint,
    error::ProgramError,
    ProgramResult,
};

entrypoint!(process_instruction);

pub const ID: Address = Address::new_from_array([/* 32 bytes */]);

fn process_instruction(
    _program_id: &Address,
    accounts: &[AccountView],
    data: &[u8],
) -> ProgramResult {
    match data.split_first() {
        Some((0, rest)) => process_deposit(accounts, rest),
        Some((1, rest)) => process_withdraw(accounts, rest),
        Some((2, rest)) => process_payment(accounts, rest),
        _ => Err(ProgramError::InvalidInstructionData),
    }
}
```

### Zero-Copy Account Parsing

```rust
use pinocchio::account::AccountView;

pub struct VaultAccount<'a> {
    raw: &'a AccountView,
}

impl<'a> VaultAccount<'a> {
    const AUTHORITY_OFFSET: usize = 0;
    const BUMP_OFFSET: usize = 32;
    const DAILY_LIMIT_OFFSET: usize = 33;
    const SPENT_TODAY_OFFSET: usize = 41;

    pub fn from_account(account: &'a AccountView) -> Result<Self, ProgramError> {
        if account.data_len() < 49 {
            return Err(ProgramError::InvalidAccountData);
        }
        Ok(Self { raw: account })
    }

    pub fn authority(&self) -> &[u8; 32] {
        self.raw.data()[Self::AUTHORITY_OFFSET..Self::AUTHORITY_OFFSET + 32]
            .try_into()
            .unwrap()
    }

    pub fn daily_limit(&self) -> u64 {
        u64::from_le_bytes(
            self.raw.data()[Self::DAILY_LIMIT_OFFSET..Self::DAILY_LIMIT_OFFSET + 8]
                .try_into()
                .unwrap(),
        )
    }
}
```

### CPI with Pinocchio

```rust
use pinocchio::instruction::{AccountMeta, Instruction};
use pinocchio::program::invoke_signed;

fn transfer_sol<'a>(
    from: &AccountView,
    to: &AccountView,
    system_program: &AccountView,
    amount: u64,
    signer_seeds: &[&[u8]],
) -> ProgramResult {
    let ix = Instruction {
        program_id: system_program.key(),
        accounts: &[
            AccountMeta { pubkey: from.key(), is_signer: true, is_writable: true },
            AccountMeta { pubkey: to.key(), is_signer: false, is_writable: true },
        ],
        data: &[2, 0, 0, 0]  // Transfer instruction discriminator
            .iter()
            .chain(&amount.to_le_bytes())
            .copied()
            .collect::<Vec<u8>>(),
    };
    invoke_signed(&ix, &[from, to, system_program], &[signer_seeds])
}
```

---

## PDA Patterns

```rust
// Derive PDA address
let (pda, bump) = Pubkey::find_program_address(
    &[b"vault", authority.key().as_ref()],
    &program_id,
);

// Common seed patterns for cto-pay
// Per-agent vault:  [b"vault", agent_pubkey]
// Per-agent token:  [b"token", agent_pubkey, mint_pubkey]
// Payment record:   [b"payment", vault_pubkey, &payment_id.to_le_bytes()]
// Config:           [b"config"]
```

---

## Cross-Program Invocation (CPI) Checklist

1. **Verify program IDs** — always check the program being invoked is the expected one
2. **Signer seeds** — include bump seed in PDA signer seeds
3. **Account ordering** — must match the target program's expected order
4. **Remaining accounts** — pass through when the callee needs them
5. **Re-entrancy** — Solana prevents re-entrancy by default; CPIs into your own program fail

---

## Security Checklist

- [ ] All accounts validated (owner, signer, writable, PDA derivation)
- [ ] Arithmetic uses `checked_*` operations (no overflow/underflow)
- [ ] Close instructions zero data and transfer all lamports
- [ ] PDAs use canonical bump (from `find_program_address`)
- [ ] Authority checks on all privileged operations
- [ ] Token account mint + authority validated before transfers
- [ ] ⚠️ **NEVER log, emit, or return private keys or seed phrases**
