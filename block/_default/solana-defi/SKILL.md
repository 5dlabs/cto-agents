---
name: solana-defi
description: Solana DeFi protocol expertise including token standards, major protocols, and common patterns.
version: 1.0.0
tags: [solana, defi, jupiter, raydium, spl, token-2022, metaplex]
---

# Solana DeFi

Deep knowledge of Solana DeFi ecosystem: token standards, major protocols, and integration patterns.

## Token Standards

### SPL Token (Original)

The standard fungible/non-fungible token program on Solana:

- **Program ID:** `TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA`
- Supports: mint, transfer, burn, approve/revoke delegate, freeze/thaw
- Associated Token Accounts (ATAs) provide deterministic token account addresses

### Token-2022 (Token Extensions)

Next-generation token program with built-in extensions:

- **Program ID:** `TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb`
- Key extensions:
  - **Transfer Fee** — protocol-level fee on every transfer
  - **Confidential Transfers** — zero-knowledge encrypted balances
  - **Transfer Hook** — custom logic on every transfer (CPI to your program)
  - **Permanent Delegate** — irrevocable delegate authority (e.g., stablecoins)
  - **Non-Transferable** — soulbound tokens
  - **Interest-Bearing** — display-only interest accrual
  - **Default Account State** — accounts created frozen by default
  - **Metadata** — on-chain metadata without Metaplex
  - **Group / Member** — token collections on-chain

### Metaplex Standards

- **Token Metadata** — the original NFT metadata standard (metadata PDA per mint)
- **Bubblegum** — compressed NFTs (cNFTs) using state compression and Merkle trees
- **Core** — next-gen asset standard: single account, plugins, lower cost
- **Candy Machine** — NFT minting/distribution with guards (allowlist, payment, time-based)

---

## Major Protocols

### Jupiter — Aggregator & DeFi Hub

The dominant swap aggregator on Solana.

**Swap API (v6):**

```typescript
// 1. Get quote (read-only, no auth)
const quoteResponse = await fetch(
  `https://quote-api.jup.ag/v6/quote?` +
  `inputMint=So11111111111111111111111111111111111111112` +  // SOL
  `&outputMint=EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v` + // USDC
  `&amount=1000000000` +  // 1 SOL in lamports
  `&slippageBps=50`       // 0.5% slippage
).then(r => r.json());

console.log(`Route: ${quoteResponse.routePlan.map(r => r.swapInfo.label).join(" → ")}`);
console.log(`Out: ${quoteResponse.outAmount} USDC (${quoteResponse.otherAmountThreshold} min)`);

// 2. Get swap transaction
const { swapTransaction } = await fetch("https://quote-api.jup.ag/v6/swap", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    quoteResponse,
    userPublicKey: wallet.publicKey.toBase58(),
    wrapAndUnwrapSol: true,
    dynamicComputeUnitLimit: true,
    prioritizationFeeLamports: "auto",
  }),
}).then(r => r.json());

// 3. Sign and send (⚠️ requires explicit user confirmation)
const tx = VersionedTransaction.deserialize(Buffer.from(swapTransaction, "base64"));
tx.sign([wallet]);
const sig = await connection.sendRawTransaction(tx.serialize());
```

**Other Jupiter Products:**
- **DCA** — Dollar-cost averaging (recurring buys)
- **Limit Orders** — On-chain limit order book
- **Perps** — Perpetual futures (up to 100x leverage)
- **Jupiter Ultra API** — Authenticated, gas-optimized route with MEV protection

### Raydium — AMM & Liquidity

- **AMM v4** — Constant product (x·y=k) with OpenBook integration
- **CLMM** — Concentrated liquidity (like Uniswap v3) for capital efficiency
- **CPMM** — Constant product without OpenBook dependency (simpler)
- Token launch via AcceleRaytor and liquidity bootstrapping

### Orca — Whirlpools

- Concentrated liquidity AMM (Whirlpools)
- Tick-based positions, similar concept to Uniswap v3
- SDK: `@orca-so/whirlpools-sdk`

### Marinade Finance

- **mSOL** — Liquid staking token (stake SOL, receive mSOL)
- Native staking or liquid staking options
- Directed stake for validator support

### Jito

- **JitoSOL** — MEV-enhanced liquid staking (higher yield from MEV tips)
- **Jito Tips** — Priority landing via tip payments to Jito validators
- **Jito Bundles** — Atomic transaction bundles (guaranteed ordering)

```typescript
// Jito bundle submission
const bundleId = await fetch("https://mainnet.block-engine.jito.wtf/api/v1/bundles", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    jsonrpc: "2.0",
    id: 1,
    method: "sendBundle",
    params: [[base58Tx1, base58Tx2]],  // ordered transactions
  }),
}).then(r => r.json());
```

### Kamino Finance

- **Lending** — Supply/borrow with auto-compounding
- **Liquidity Vaults** — Automated concentrated liquidity management
- **Multiply** — Leveraged yield strategies

### Drift Protocol

- **Perpetual Futures** — Up to 20x leverage, cross-margin
- **Spot Trading** — Order book + AMM hybrid
- **Borrow/Lend** — Variable rate lending

### Tensor

- NFT marketplace and AMM
- Collection-wide bids, trait bidding
- Compressed NFT support

---

## Common DeFi Patterns

### Token Swap Pattern

```typescript
async function swapTokens(
  inputMint: string,
  outputMint: string,
  amountLamports: number,
  slippageBps: number = 50,
): Promise<string> {
  // 1. Quote
  const quote = await getJupiterQuote(inputMint, outputMint, amountLamports, slippageBps);

  // 2. Check price impact
  if (parseFloat(quote.priceImpactPct) > 1.0) {
    throw new Error(`Price impact too high: ${quote.priceImpactPct}%`);
  }

  // 3. Get swap tx
  const swapTx = await getJupiterSwapTx(quote, walletPublicKey);

  // 4. Simulate first
  const simulation = await connection.simulateTransaction(swapTx);
  if (simulation.value.err) {
    throw new Error(`Simulation failed: ${JSON.stringify(simulation.value.err)}`);
  }

  // 5. Execute (with user confirmation)
  return await sendAndConfirmTransaction(swapTx);
}
```

### Staking / Unstaking Pattern

```typescript
// Marinade liquid staking
import { Marinade, MarinadeConfig } from "@marinade.finance/marinade-ts-sdk";

const config = new MarinadeConfig({ connection, publicKey: wallet.publicKey });
const marinade = new Marinade(config);

// Stake SOL → mSOL
const { transaction } = await marinade.deposit(new BN(1_000_000_000)); // 1 SOL
await wallet.sendTransaction(transaction, connection);

// Unstake mSOL → SOL (delayed unstake for better rate)
const { transaction: unstakeTx } = await marinade.liquidUnstake(new BN(msolAmount));
```

### Yield Farming Lifecycle

1. **Deposit** → LP tokens or receipt tokens
2. **Stake** LP tokens in farm/gauge for reward emissions
3. **Harvest** accumulated rewards periodically
4. **Compound** by swapping rewards back and adding more liquidity
5. **Withdraw** when exiting position

### Price Oracle Pattern

```typescript
// Pyth price feeds
import { PythHttpClient, getPythProgramKeyForCluster } from "@pythnetwork/client";

const pythClient = new PythHttpClient(connection, getPythProgramKeyForCluster("mainnet-beta"));
const data = await pythClient.getData();
const solPrice = data.productPrice.get("Crypto.SOL/USD");
console.log(`SOL: $${solPrice?.aggregate.price} ± $${solPrice?.aggregate.confidence}`);
```
