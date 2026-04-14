---
name: cross-chain
description: Cross-chain development with CCTP, Wormhole, LayerZero, and Axelar.
version: 1.0.0
tags: [cross-chain, bridge, cctp, wormhole, layerzero, axelar]
---

# Cross-Chain Development

Patterns and integrations for bridging assets and messages across blockchain networks.

## Circle CCTP (Cross-Chain Transfer Protocol)

Native USDC bridging — burn on source, mint on destination. No wrapped tokens.

### Supported Chains & Domain IDs

| Chain | Domain ID | TokenMessenger | MessageTransmitter |
|-------|-----------|---------------|-------------------|
| Ethereum | 0 | `0xBd3fa81B58Ba92a82136038B25aDec7066af3155` | `0x0a992d191DEeC32aFe36203Ad87D7d289a738F81` |
| Avalanche | 1 | `0x6B25532e1060CE10cc3B0A99e5683b91BFDe6982` | `0x8186359aF5F57FbB40c6b14A588d2A59C0C29880` |
| Optimism | 2 | `0x2B4069517957735bE00ceE0fadAE88a26365528f` | `0x4D41f22c5a0e5c74090899E5a8Fb597a8842b3e8` |
| Arbitrum | 3 | `0x19330d10D9Cc8751218eaf51E8885D058642E08A` | `0xC30362313FBBA5cf9163F0bb16a0e01f01A896ca` |
| Base | 6 | `0x1682Ae6375C4E4A97e4B583BC394c861A46D8962` | `0xAD09780d193884d503182aD4F75D113B9B2b0Cd9` |
| Solana | 5 | Program: `CCTPiPYPc6AsJuwueEnWgSgucamXDZwBd53dQ11YiKX3` | — |

### CCTP Flow

1. **Approve** USDC spend to TokenMessenger
2. **Burn** via `depositForBurn(amount, destinationDomain, mintRecipient, usdc)`
3. **Attestation** — wait for Circle attestation API (`https://iris-api.circle.com/attestations/{messageHash}`)
4. **Mint** on destination via `receiveMessage(message, attestation)`

### Code Example (EVM → EVM)

```typescript
import { ethers } from "ethers";

// Step 1: Approve and burn on source chain
const tokenMessenger = new ethers.Contract(TOKEN_MESSENGER_ADDR, TOKEN_MESSENGER_ABI, signer);
const usdc = new ethers.Contract(USDC_ADDR, ERC20_ABI, signer);

await usdc.approve(TOKEN_MESSENGER_ADDR, amount);
const burnTx = await tokenMessenger.depositForBurn(
  amount,
  destinationDomain,     // e.g., 6 for Base
  ethers.zeroPadValue(recipientAddress, 32),  // bytes32 mint recipient
  USDC_ADDR
);
const receipt = await burnTx.wait();

// Step 2: Extract message bytes from MessageSent event
const eventTopic = ethers.id("MessageSent(bytes)");
const log = receipt.logs.find(l => l.topics[0] === eventTopic);
const messageBytes = ethers.AbiCoder.defaultAbiCoder().decode(["bytes"], log.data)[0];
const messageHash = ethers.keccak256(messageBytes);

// Step 3: Poll for attestation
let attestation;
while (!attestation) {
  const resp = await fetch(`https://iris-api.circle.com/attestations/${messageHash}`);
  const data = await resp.json();
  if (data.status === "complete") {
    attestation = data.attestation;
  } else {
    await new Promise(r => setTimeout(r, 10_000));
  }
}

// Step 4: Receive on destination chain
const destTransmitter = new ethers.Contract(DEST_TRANSMITTER_ADDR, TRANSMITTER_ABI, destSigner);
await destTransmitter.receiveMessage(messageBytes, attestation);
```

---

## Wormhole

General-purpose cross-chain messaging protocol. Supports 30+ chains.

### Key Concepts

- **Guardian Network** — 19 validators that observe and attest to messages
- **VAA (Verified Action Approval)** — signed message from guardians
- **Relayer** — delivers VAAs to destination chains (automatic or manual)

### SDK Usage

```typescript
import { wormhole } from "@wormhole-foundation/sdk";
import evm from "@wormhole-foundation/sdk/evm";
import solana from "@wormhole-foundation/sdk/solana";

const wh = await wormhole("Mainnet", [evm, solana]);

// Token transfer
const xfer = await wh.tokenTransfer(
  "native",                              // or token address
  1_000_000n,                            // amount
  { chain: "Ethereum", address: sender },
  { chain: "Solana", address: recipient },
  false,                                 // automatic relay
);

// Manual: get VAA and complete on destination
const [attestation] = await xfer.fetchAttestation();
await xfer.completeTransfer(destSigner);
```

### Use Cases

- Token bridges (Portal/Wormhole NTT)
- Cross-chain governance
- Cross-chain NFT transfers
- General message passing

---

## LayerZero v2

Omnichain interoperability protocol with modular security.

### Key Concepts

- **OApp (Omnichain Application)** — base contract for cross-chain messaging
- **OFT (Omnichain Fungible Token)** — token standard that natively moves cross-chain
- **DVN (Decentralized Verifier Network)** — modular message verification
- **Executor** — delivers and executes messages on destination

### OApp Pattern

```solidity
import {OApp, MessagingFee, Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

contract MyOApp is OApp {
    constructor(address _endpoint, address _delegate) OApp(_endpoint, _delegate) {}

    // Send cross-chain message
    function send(
        uint32 _dstEid,        // destination endpoint ID
        string memory _message,
        bytes calldata _options
    ) external payable {
        bytes memory payload = abi.encode(_message);
        _lzSend(_dstEid, payload, _options, MessagingFee(msg.value, 0), payable(msg.sender));
    }

    // Receive cross-chain message
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) internal override {
        string memory message = abi.decode(_message, (string));
        // Process message
    }
}
```

### OFT Pattern (Cross-Chain Token)

```solidity
import {OFT} from "@layerzerolabs/oft-evm/contracts/OFT.sol";

contract MyToken is OFT {
    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _delegate
    ) OFT(_name, _symbol, _lzEndpoint, _delegate) {
        _mint(msg.sender, 1_000_000 * 10**decimals());
    }
}
```

```typescript
// Send tokens cross-chain
const sendParam = {
  dstEid: 30184,                 // Base endpoint ID
  to: ethers.zeroPadValue(recipientAddress, 32),
  amountLD: ethers.parseEther("100"),
  minAmountLD: ethers.parseEther("99"),  // 1% slippage
  extraOptions: "0x",
  composeMsg: "0x",
  oftCmd: "0x",
};
const [fee] = await oft.quoteSend(sendParam, false);
await oft.send(sendParam, fee, sender, { value: fee.nativeFee });
```

---

## Axelar — General Message Passing (GMP)

### Pattern

```solidity
import {AxelarExecutable} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol";

contract MyReceiver is AxelarExecutable {
    constructor(address gateway_) AxelarExecutable(gateway_) {}

    function _execute(
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) internal override {
        // Process cross-chain message
    }
}
```

---

## Bridging Strategies

### Canonical vs Liquidity-Based

| Approach | Pros | Cons | Examples |
|----------|------|------|---------|
| **Canonical (lock/mint)** | Trustless, protocol-native | Slow (finality wait), locked liquidity | CCTP, Wormhole NTT |
| **Liquidity-based** | Fast, instant finality | Requires LPs, slippage on large amounts | Across, Stargate |
| **Intent-based** | Best UX, competitive pricing | Solver dependency, complex infra | Across v3, UniswapX |

### Multi-Chain Deployment Patterns

1. **Hub-and-spoke** — One canonical chain, bridge to others
2. **Native multi-chain** — Deploy independently on each chain with cross-chain sync
3. **OFT/NTT** — Single token supply across all chains (burn/mint)

### Best Practices

- Always verify bridge contract addresses from official documentation
- Set appropriate slippage tolerances for liquidity bridges
- Monitor bridge health and TVL before large transfers
- Use canonical bridges for large amounts; liquidity bridges for speed
- Implement retry/fallback logic for attestation polling
- Test on testnets first (Sepolia, Fuji, Base Sepolia)
