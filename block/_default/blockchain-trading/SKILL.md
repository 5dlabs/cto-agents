---
name: blockchain-trading
description: "Security-first blockchain trading skill: DEX quoting, swap execution, market data, and risk management."
version: 1.0.0
tags: [trading, defi, jupiter, uniswap, market-data, risk]
---

# Blockchain Trading

> **Security policy:** This skill operates in **read-only / quote-only mode** by default. Any transaction that moves funds requires **explicit user confirmation** before signing. Never store, log, or echo private keys. Prefer wallet file paths or hardware signer references over raw key material.

---

## Solana DEX — Jupiter

### Get Quote (Read-Only)

```typescript
const quote = await fetch(
  "https://quote-api.jup.ag/v6/quote?" +
  new URLSearchParams({
    inputMint: "So11111111111111111111111111111111111111112",   // SOL
    outputMint: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", // USDC
    amount: "1000000000",   // 1 SOL in lamports
    slippageBps: "50",      // 0.5%
  })
).then(r => r.json());

console.log(`Expected output: ${quote.outAmount} USDC lamports`);
console.log(`Price impact: ${quote.priceImpactPct}%`);
console.log(`Route: ${quote.routePlan.map(r => r.swapInfo.label).join(" → ")}`);
```

### Token Search

```typescript
// Jupiter token list
const tokens = await fetch("https://token.jup.ag/strict").then(r => r.json());
const usdc = tokens.find(t => t.symbol === "USDC");

// Birdeye token search (requires API key)
const search = await fetch(
  `https://public-api.birdeye.so/defi/v3/search?keyword=BONK&chain=solana`,
  { headers: { "X-API-KEY": process.env.BIRDEYE_API_KEY } }
).then(r => r.json());
```

### Swap Execution (⚠️ Requires User Confirmation)

```typescript
// ⚠️ WARNING: This sends a transaction that moves funds.
// Always confirm with the user before executing.

const { swapTransaction } = await fetch("https://quote-api.jup.ag/v6/swap", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    quoteResponse: quote,
    userPublicKey: wallet.publicKey.toBase58(),
    wrapAndUnwrapSol: true,
    dynamicComputeUnitLimit: true,
    prioritizationFeeLamports: "auto",
  }),
}).then(r => r.json());

const tx = VersionedTransaction.deserialize(Buffer.from(swapTransaction, "base64"));
tx.sign([wallet.payer]);
const sig = await connection.sendRawTransaction(tx.serialize(), {
  skipPreflight: false,
  maxRetries: 3,
});
await connection.confirmTransaction(sig, "confirmed");
```

### Jupiter Ultra API (Authenticated)

```typescript
// Ultra API — gas-optimized, MEV-protected swaps
// Requires JUP_API_KEY
const ultraQuote = await fetch("https://lite-api.jup.ag/ultra/v1/order", {
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    "x-api-key": process.env.JUP_API_KEY,
  },
  body: JSON.stringify({
    inputMint: "So11111111111111111111111111111111111111112",
    outputMint: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
    amount: 1_000_000_000,
    taker: wallet.publicKey.toBase58(),
  }),
}).then(r => r.json());
```

---

## Wallet Operations

### Balance Check (Read-Only)

```typescript
import { Connection, PublicKey, LAMPORTS_PER_SOL } from "@solana/web3.js";

const connection = new Connection(process.env.SOLANA_RPC_URL || "https://api.mainnet-beta.solana.com");

// SOL balance
const balance = await connection.getBalance(new PublicKey(address));
console.log(`SOL: ${balance / LAMPORTS_PER_SOL}`);

// Token balances
const tokenAccounts = await connection.getParsedTokenAccountsByOwner(
  new PublicKey(address),
  { programId: new PublicKey("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA") }
);
for (const { account } of tokenAccounts.value) {
  const info = account.data.parsed.info;
  console.log(`${info.mint}: ${info.tokenAmount.uiAmount}`);
}
```

### Transfer (⚠️ Requires User Confirmation)

```typescript
// ⚠️ WARNING: This sends a transaction that moves funds.
import { SystemProgram, Transaction, sendAndConfirmTransaction } from "@solana/web3.js";

const tx = new Transaction().add(
  SystemProgram.transfer({
    fromPubkey: sender.publicKey,
    toPubkey: new PublicKey(recipient),
    lamports: amount * LAMPORTS_PER_SOL,
  })
);
// Confirm with user before signing
const sig = await sendAndConfirmTransaction(connection, tx, [sender]);
```

---

## EVM DEX — Read-Only Quoting

### 1inch Quote

```typescript
const quote = await fetch(
  `https://api.1inch.dev/swap/v6.0/1/quote?` +
  new URLSearchParams({
    src: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",  // USDC
    dst: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",  // WETH
    amount: "1000000000",  // 1000 USDC (6 decimals)
  }),
  { headers: { Authorization: `Bearer ${process.env.ONEINCH_API_KEY}` } }
).then(r => r.json());
```

### Uniswap v3 Quoter

```typescript
import { ethers } from "ethers";

const quoterAbi = ["function quoteExactInputSingle(tuple(address tokenIn, address tokenOut, uint256 amountIn, uint24 fee, uint160 sqrtPriceLimitX96)) external returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate)"];

const quoter = new ethers.Contract(QUOTER_V2_ADDRESS, quoterAbi, provider);
const [amountOut] = await quoter.quoteExactInputSingle.staticCall({
  tokenIn: USDC_ADDRESS,
  tokenOut: WETH_ADDRESS,
  amountIn: ethers.parseUnits("1000", 6),
  fee: 3000,
  sqrtPriceLimitX96: 0,
});
```

---

## Market Data (No Auth Required)

### CoinGecko

```typescript
// Price
const prices = await fetch(
  "https://api.coingecko.com/api/v3/simple/price?ids=solana,ethereum,bitcoin&vs_currencies=usd&include_24hr_change=true"
).then(r => r.json());

// OHLCV (14 days)
const ohlcv = await fetch(
  "https://api.coingecko.com/api/v3/coins/solana/ohlc?vs_currency=usd&days=14"
).then(r => r.json());
```

### Binance Public API

```typescript
// Ticker price
const ticker = await fetch(
  "https://api.binance.com/api/v3/ticker/24hr?symbol=SOLUSDT"
).then(r => r.json());

// Klines (candlesticks)
const klines = await fetch(
  "https://api.binance.com/api/v3/klines?symbol=SOLUSDT&interval=1h&limit=100"
).then(r => r.json());
```

### DeFiLlama

```typescript
// Protocol TVL
const tvl = await fetch("https://api.llama.fi/tvl/jupiter").then(r => r.json());

// All protocols
const protocols = await fetch("https://api.llama.fi/protocols").then(r => r.json());

// Historical chain TVL
const chainTvl = await fetch("https://api.llama.fi/v2/historicalChainTvl/Solana").then(r => r.json());
```

---

## Technical Analysis Patterns

### RSI (Relative Strength Index)

```typescript
function calculateRSI(closes: number[], period: number = 14): number {
  if (closes.length < period + 1) return 50;

  let gains = 0, losses = 0;
  for (let i = 1; i <= period; i++) {
    const diff = closes[i] - closes[i - 1];
    if (diff > 0) gains += diff;
    else losses -= diff;
  }

  let avgGain = gains / period;
  let avgLoss = losses / period;

  for (let i = period + 1; i < closes.length; i++) {
    const diff = closes[i] - closes[i - 1];
    avgGain = (avgGain * (period - 1) + Math.max(diff, 0)) / period;
    avgLoss = (avgLoss * (period - 1) + Math.max(-diff, 0)) / period;
  }

  if (avgLoss === 0) return 100;
  const rs = avgGain / avgLoss;
  return 100 - (100 / (1 + rs));
}
```

### Support / Resistance

```typescript
function findLevels(highs: number[], lows: number[], lookback: number = 20): { support: number[]; resistance: number[] } {
  const support: number[] = [];
  const resistance: number[] = [];

  for (let i = lookback; i < lows.length - lookback; i++) {
    const isSupport = lows.slice(i - lookback, i).every(l => l >= lows[i]) &&
                      lows.slice(i + 1, i + lookback + 1).every(l => l >= lows[i]);
    if (isSupport) support.push(lows[i]);
  }

  for (let i = lookback; i < highs.length - lookback; i++) {
    const isResistance = highs.slice(i - lookback, i).every(h => h <= highs[i]) &&
                         highs.slice(i + 1, i + lookback + 1).every(h => h <= highs[i]);
    if (isResistance) resistance.push(highs[i]);
  }

  return { support, resistance };
}
```

---

## DeFi Protocol Interactions

### Staking (Example: Marinade)

```typescript
import { Marinade, MarinadeConfig } from "@marinade.finance/marinade-ts-sdk";

const config = new MarinadeConfig({ connection, publicKey: wallet.publicKey });
const marinade = new Marinade(config);
const { transaction } = await marinade.deposit(new BN(1_000_000_000));
// ⚠️ Confirm with user before sending
await wallet.sendTransaction(transaction, connection);
```

### Lending (Example: Kamino)

Read position data (safe):
```typescript
const obligation = await kaminoMarket.getObligationByWallet(wallet.publicKey);
console.log(`Deposited: $${obligation.depositedValue}`);
console.log(`Borrowed: $${obligation.borrowedValue}`);
console.log(`LTV: ${obligation.loanToValue}%`);
```

---

## Risk Management Rules

| Rule | Guideline |
|------|-----------|
| **Position sizing** | Never risk more than 2–5% of portfolio on a single trade |
| **Stop-loss** | Always define exit criteria before entering a position |
| **Slippage** | Set explicit slippage tolerance (≤1% for majors, ≤3% for small caps) |
| **Contract verification** | Verify contract source on block explorer before interacting |
| **Honeypot check** | Check sell tax, owner privileges, and liquidity lock before buying tokens |
| **Cool-down** | Wait 5 minutes between consecutive trades to avoid emotional decisions |
| **Diversification** | Don't concentrate >25% of portfolio in any single asset |
| **Simulation first** | Always simulate transactions before broadcasting |

---

## Environment Variables

| Variable | Purpose | Required |
|----------|---------|----------|
| `SOLANA_KEYPAIR_PATH` | Path to Solana keypair JSON file | For signing |
| `SOLANA_RPC_URL` | Solana RPC endpoint | Yes |
| `JUP_API_KEY` | Jupiter Ultra API key | For Ultra API |
| `HELIUS_API_KEY` | Helius RPC and DAS API | Recommended |
| `BIRDEYE_API_KEY` | Birdeye token data API | For token search |
| `ONEINCH_API_KEY` | 1inch API key | For EVM quotes |
| `ETH_RPC_URL` | Ethereum RPC endpoint | For EVM ops |
| `BASE_RPC_URL` | Base RPC endpoint | For Base ops |

---

## Security Note

- **All keys via env vars or secure file paths** — never hardcode secrets in source
- **Never echo or log private key material** — not in console, not in files, not in error messages
- **Prefer hardware wallets** (Ledger) for production/mainnet operations
- **Verify all contract addresses** against official documentation before interaction
- **Simulate before broadcast** — use `simulateTransaction` (Solana) or `eth_call` (EVM) before signing
- **Require explicit user confirmation** for any transaction that moves funds
