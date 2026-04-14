---
name: evm-development
description: EVM smart contract development with Foundry, Solidity, and major DeFi protocols.
version: 1.0.0
tags: [evm, solidity, foundry, hardhat, uniswap, aave, defi]
---

# EVM Development

Comprehensive skill for Ethereum Virtual Machine smart contract development, testing, and deployment across EVM-compatible chains.

## Frameworks

### Foundry (Preferred)

Fast, Rust-based Solidity development toolkit.

**Project Structure:**

```
my_project/
├── foundry.toml           # Configuration
├── src/
│   └── MyContract.sol     # Source contracts
├── test/
│   └── MyContract.t.sol   # Tests (unit, fuzz, invariant)
├── script/
│   └── Deploy.s.sol       # Deployment scripts
└── lib/                   # Dependencies (git submodules)
```

**foundry.toml:**

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
optimizer = true
optimizer_runs = 200
solc_version = "0.8.24"
evm_version = "cancun"

[profile.default.fuzz]
runs = 256
max_test_rejects = 65536

[profile.default.invariant]
runs = 256
depth = 50

[rpc_endpoints]
mainnet = "${ETH_RPC_URL}"
base = "${BASE_RPC_URL}"
arbitrum = "${ARB_RPC_URL}"

[etherscan]
mainnet = { key = "${ETHERSCAN_API_KEY}" }
base = { key = "${BASESCAN_API_KEY}", url = "https://api.basescan.org/api" }
```

**Installation:**

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup

# New project
forge init my_project
cd my_project

# Install dependencies
forge install OpenZeppelin/openzeppelin-contracts
forge install Uniswap/v3-core
```

---

## Testing Patterns

### Unit Tests

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {MyToken} from "../src/MyToken.sol";

contract MyTokenTest is Test {
    MyToken token;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        token = new MyToken("Test", "TST", 18);
        token.mint(alice, 1000e18);
    }

    function test_Transfer() public {
        vm.prank(alice);
        token.transfer(bob, 100e18);
        assertEq(token.balanceOf(bob), 100e18);
        assertEq(token.balanceOf(alice), 900e18);
    }

    function test_RevertWhen_InsufficientBalance() public {
        vm.prank(alice);
        vm.expectRevert("ERC20: insufficient balance");
        token.transfer(bob, 2000e18);
    }

    function test_EmitsTransferEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit Transfer(alice, bob, 100e18);
        token.transfer(bob, 100e18);
    }
}
```

### Fuzz Tests

```solidity
function testFuzz_Transfer(uint256 amount) public {
    amount = bound(amount, 0, token.balanceOf(alice));
    vm.prank(alice);
    token.transfer(bob, amount);
    assertEq(token.balanceOf(bob), amount);
}
```

### Invariant Tests

```solidity
contract MyTokenInvariant is Test {
    MyToken token;
    Handler handler;

    function setUp() public {
        token = new MyToken("Test", "TST", 18);
        handler = new Handler(token);
        targetContract(address(handler));
    }

    function invariant_TotalSupplyEqualsSum() public view {
        uint256 sum = token.balanceOf(address(handler)) + token.balanceOf(address(this));
        assertEq(token.totalSupply(), sum);
    }
}
```

### Fork Tests

```solidity
function test_SwapOnMainnet() public {
    uint256 forkId = vm.createFork("mainnet", 19_000_000);
    vm.selectFork(forkId);

    // Test against real mainnet state at block 19M
    IERC20 usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    assertGt(usdc.totalSupply(), 0);
}
```

---

## Cast Commands (On-Chain Interaction)

```bash
# Read contract
cast call <CONTRACT> "balanceOf(address)(uint256)" <ADDRESS> --rpc-url $RPC

# Send transaction (⚠️ signs with private key)
cast send <CONTRACT> "transfer(address,uint256)" <TO> <AMOUNT> \
  --private-key $PRIVATE_KEY --rpc-url $RPC

# Decode calldata
cast 4byte-decode 0xa9059cbb000000...

# Get storage slot
cast storage <CONTRACT> <SLOT> --rpc-url $RPC

# ABI encode
cast abi-encode "transfer(address,uint256)" 0x... 1000000

# Gas estimation
cast estimate <CONTRACT> "mint(uint256)" 5 --rpc-url $RPC
```

---

## Solidity Patterns

### Access Control

```solidity
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract MyVault is AccessControl {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
    }

    function deposit() external onlyRole(OPERATOR_ROLE) { /* ... */ }
    function emergencyPause() external onlyRole(GUARDIAN_ROLE) { /* ... */ }
}
```

### Upgradeable Contracts (UUPS)

```solidity
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract MyVaultV1 is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    uint256 public totalDeposits;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    function initialize(address owner_) external initializer {
        __Ownable_init(owner_);
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
```

### ERC Standards

| Standard | Purpose | Key Functions |
|----------|---------|---------------|
| **ERC-20** | Fungible token | `transfer`, `approve`, `transferFrom`, `balanceOf` |
| **ERC-721** | NFT | `ownerOf`, `transferFrom`, `safeTransferFrom`, `tokenURI` |
| **ERC-1155** | Multi-token | `balanceOf`, `safeTransferFrom`, `safeBatchTransferFrom` |
| **ERC-4626** | Tokenized vault | `deposit`, `withdraw`, `convertToShares`, `convertToAssets` |
| **ERC-2612** | Permit (gasless approve) | `permit` with EIP-712 signature |

---

## Major Protocol Integrations

### Uniswap v3

```solidity
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

function swapExactInput(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint24 fee
) external returns (uint256 amountOut) {
    IERC20(tokenIn).approve(address(swapRouter), amountIn);

    ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
        tokenIn: tokenIn,
        tokenOut: tokenOut,
        fee: fee,           // 500 (0.05%), 3000 (0.3%), 10000 (1%)
        recipient: msg.sender,
        deadline: block.timestamp + 300,
        amountIn: amountIn,
        amountOutMinimum: 0, // ⚠️ Set proper slippage in production
        sqrtPriceLimitX96: 0
    });
    amountOut = swapRouter.exactInputSingle(params);
}
```

### Aave v3

```solidity
import {IPool} from "@aave/v3-core/contracts/interfaces/IPool.sol";

// Supply
IERC20(asset).approve(address(pool), amount);
pool.supply(asset, amount, onBehalfOf, 0);

// Borrow
pool.borrow(asset, amount, 2, 0, onBehalfOf); // 2 = variable rate

// Repay
IERC20(asset).approve(address(pool), amount);
pool.repay(asset, amount, 2, onBehalfOf);
```

### Chainlink

```solidity
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

function getLatestPrice(address feed) public view returns (int256) {
    (, int256 price,, uint256 updatedAt,) = AggregatorV3Interface(feed).latestRoundData();
    require(block.timestamp - updatedAt < 3600, "Stale price");
    return price; // 8 decimals for USD pairs
}
```

---

## Gas Optimization

| Technique | Savings | Example |
|-----------|---------|---------|
| Pack storage variables | ~2100 gas/slot | Group `uint128` + `uint128` in one slot |
| Use `calldata` over `memory` | ~60 gas/arg | `function f(bytes calldata data)` |
| Cache storage reads | ~100 gas/read | `uint256 cached = storageVar;` |
| Use `unchecked` for safe math | ~20-80 gas/op | `unchecked { i++; }` in loops |
| Short-circuit requires | Variable | Put cheap checks first |
| Use custom errors | ~24 gas vs string | `error InsufficientBalance();` |
| Immutable/constant | ~2100 gas | `uint256 public immutable FEE;` |
| Use events for off-chain data | ~375 gas vs storage | Emit instead of store read-only data |

---

## Multi-Chain Deployment

### Supported Chains

| Chain | Chain ID | RPC | Block Explorer |
|-------|----------|-----|----------------|
| Ethereum | 1 | `https://eth.llamarpc.com` | etherscan.io |
| Base | 8453 | `https://mainnet.base.org` | basescan.org |
| Arbitrum One | 42161 | `https://arb1.arbitrum.io/rpc` | arbiscan.io |
| Optimism | 10 | `https://mainnet.optimism.io` | optimistic.etherscan.io |
| Polygon | 137 | `https://polygon-rpc.com` | polygonscan.com |

### Deployment Script

```solidity
// script/Deploy.s.sol
import {Script} from "forge-std/Script.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        MyContract c = new MyContract{salt: bytes32("v1")}(/* args */);
        console2.log("Deployed to:", address(c));

        vm.stopBroadcast();
    }
}
```

```bash
# Deploy to multiple chains
forge script script/Deploy.s.sol --rpc-url $BASE_RPC --broadcast --verify
forge script script/Deploy.s.sol --rpc-url $ARB_RPC --broadcast --verify
```

---

## Security Checklist

| Vulnerability | Mitigation |
|--------------|------------|
| **Reentrancy** | CEI pattern (checks-effects-interactions), `ReentrancyGuard` |
| **Flash loan attacks** | Time-weighted prices, multi-block confirmation |
| **Frontrunning** | Commit-reveal, private mempools, MEV protection |
| **Storage collision** | Use ERC-1967 proxy storage slots, never reorder storage vars |
| **Integer overflow** | Solidity 0.8+ has built-in checks; use `unchecked` only when safe |
| **Access control** | Role-based access, multi-sig for admin functions |
| **Oracle manipulation** | Use TWAP, multiple oracle sources, staleness checks |
| **Signature replay** | Include chain ID + nonce in EIP-712 domain |
| **Delegate call** | Never delegatecall to untrusted contracts |
| **Self-destruct** | Removed in Dencun; legacy contracts may still have it |

### Hardhat (Alternative)

```bash
npx hardhat init
npx hardhat compile
npx hardhat test
npx hardhat run scripts/deploy.ts --network base
```

Hardhat is JavaScript/TypeScript-based and has a larger plugin ecosystem. Use when:
- Team prefers JS/TS over Solidity for tests
- Need specific Hardhat plugins (hardhat-deploy, hardhat-gas-reporter)
- Existing project already uses Hardhat
