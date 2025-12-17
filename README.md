# ReactiveLooper
DeFi lending looper - leverage optimizer powered by Reactive network

---

## Live Link - https://reactive-looper-72o3qd61q-natxs-projects.vercel.app/

## Demo - https://www.loom.com/share/407ac34f351c4b08a5e7173f1ce75c8d

## Table of Contents

1. [Overview](#overview)
2. [Problem Statement](#problem-statement)
3. [Solution](#solution)
4. [How It Works](#how-it-works)
5. [Transactions](#transactions)
6. [Setup and Deployment](#setup-and-deployment)
7. [Bounty Requirements](#bounty-requirements)
8. [Future Improvements](#future-improvements)
9. [Acknowledgments](#acknowledgments)

## Overview

This project implements an automated, highly-leveraged strategy by integrating the Aave V3 lending protocol with Uniswap V3 for atomic asset swapping and consolidation. The primary mechanism involves a recursive supply-borrow-swap loop that executes multiple times to efficiently maximize the position's leverage until a pre-defined target ratio is achieved. To safely manage this complex structure, the system utilizes the ERC-2612 Permit standard for gas optimization and includes a comprehensive safeUnwind function to atomically liquidate the entire position and settle all outstanding debts.

## Problem Statement

Achieving optimal leverage in decentralized finance typically involves complex, multi-step transaction sequences which are vulnerable to high gas costs and critical exposure to price risk between operations.

## Solution

The project introduces a custom smart contract architecture that utilizes Reactive network's smart contract automation to orchestrate the multi-step execution. This automation enables the seamless operation of the recursive supply-borrow-swap loop within a single, atomic transaction, saving critical time and eliminating the exposure window to asset volatility, which is a major risk when transactions must be submitted individually.

## How It Works

ReactiveLooper utilizes the Reactive and Callback functionality from Reactive network to monitor and react accordingly to supply and borrow events from the Aave V3 pool contract.
It also monitors the swapper contract (specifically created for this project to swap between the collateral and borrow assets). All steps in the loop are contained in one call
back contract.

### Architecture

Below is an Imgae depicting the architecture of the ReactiveLooper project.
           
           ┌────────────────────────┐        ┌──────────────────┐         ┌─────────────────┐
           │  WETH Transfer Event   │◄───────┤  TransferReactive│         │                 │
           │  (User Opt-in)         │        │  (Event Monitor) │         │                 │
           └────────────────────────┘        └──────────────────┘         │                 │
                    │                              │                      │                 │
                    │ Transfer                     │ Callback             │                 │
                    ▼                              ▼                      │                 │
           ┌─────────────────┐            ┌──────────────────┐            │  ┌─────────────┐│
           │   Looper        │◄───────────┤ Supply Event     │───────────►│  │ Aave Pool   ││
           │ (Supply)        │            │ (SupplyReactive) │            │  │(Collateral) ││
           └─────────────────┘            └──────────────────┘            │  └─────────────┘│
                    │                              │                      └─────────────────┘
                    │ Supply Event                 │ Callback                      │
                    ▼                              ▼                               │
           ┌─────────────────┐            ┌──────────────────┐                     │
           │   Looper        │◄───────────┤ Borrow Event     │                     │
           │ (Borrow)        │            │ (BorrowReactive) │                     │
           └─────────────────┘            └──────────────────┘                     │
                    │                              │                               │
                    │ Borrow Event                 │ Callback                      │
                    ▼                              ▼                               │
           ┌─────────────────┐            ┌──────────────────┐                     │
           │   Swapper       │◄───────────┤ Swap Event       │                     │
           │ (USDC→WETH)     │            │ (SwapReactive)   │                     │
           └─────────────────┘            └──────────────────┘                     │
                    │                              │                               │
                    │ Swap Event                   │ Callback                      │
                    ▼                              ▼                               │
           ┌─────────────────┐            ┌──────────────────┐                     │
           │   Looper        │◄───────────┤ Loop Back        │◄────────────────────┘
           │ (Re-supply)     │            │ (Callback)       │
           └─────────────────┘            └──────────────────┘

### Program Flow

The following steps describe the program flow

#### 1. User Opt-in

The user transfers a set amount of the collateral token in our case WETH (chosen token), 
The `TransferReactive` contract subscribes to `Transfer` events from Collateral token on Sepolia and reacts to it by calling the callback on the Looper contract for the `Supply` function to be called from the looper.

Subscribing

```solidity
constructor(
    address _looper,
    address _collateralToken
) payable {
    looper = _looper;
    collateralToken = _collateralToken;
    initiator = msg.sender;
    service = ISystemContract(payable(SERVICE));
    if (!vm) {
        service.subscribe(
            chainId,
            _collateralToken,
            eventTopic0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }
}
```

Reacting

```solidity
function react(LogRecord calldata log) external vmOnly {
    address sender = address(uint160(log.topic_1));
    address receiver = address(uint160(log.topic_2));

    if (sender == initiator && receiver == looper) {
        bytes memory payload = abi.encodeWithSignature(
            "callback(address,uint256)",
            address(0),
            0
        );

        emit Callback(chainId, looper, GAS_LIMIT, payload);
    }
}
```

The full code can be found [here](https://github.com/NatX223/ReactiveLooper/blob/main/Contracts/src/TransferReactive.sol)

#### 2. Supplying Collateral

When the collateral tokens have been to sent to the `Looper` contract and it has been notified, the next step is to supply the received tokens to the Aave Pool as collateral.


```solidity
    function callback(
        address sender,
        uint256 operation
    ) external authorizedSenderOnly rvmIdOnly(sender) {
        if (operation == 0) {
            uint256 balance = IERC20(collateralToken).balanceOf(address(this));
            require(balance > 0, "Collateral balance is zero");
            TransferHelper.safeApprove(collateralToken, address(Pool), balance);

            Pool.supply(
                collateralToken,
                IERC20(collateralToken).balanceOf(address(this)),
                address(this),
                0
            );
        }
        ...
    }
```

The full code can be found [here](https://github.com/NatX223/ReactiveLooper/blob/main/Contracts/src/Looper.sol)

#### 3. Borrowing Tokens

After the supply function has been called the `SupplyReactive` contract picks it up and reacts to it by calling the same callback fnction on the Looper contract but this time to borrow tokens (in our case USDC).

Subscribing to Supply event

```solidity
    constructor(
        address _looper,
        address _pool
    ) payable {
        looper = _looper;
        pool = _pool;
        service = ISystemContract(payable(SERVICE));
        if (!vm) {
            service.subscribe(
                chainId,
                _pool,
                eventTopic0,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
        }
    }
```
Reacting - calling callback on Looper function

```solidity
    function react(LogRecord calldata log) external vmOnly {
        address supplier = address(uint160(log.topic_2));

        if (supplier == looper) {
            bytes memory payload = abi.encodeWithSignature(
                "callback(address,uint256)",
                address(0),
                1
            );

            emit Callback(chainId, looper, GAS_LIMIT, payload);
        }
    }
```

The full code can be found [here](https://github.com/NatX223/ReactiveLooper/blob/main/Contracts/src/SupplyReactive.sol)

Calling the Borrow function

```solidity
    function callback(
        address sender,
        uint256 operation
    ) external authorizedSenderOnly rvmIdOnly(sender) {
        ...
        
        else if (operation == 1) {
            uint256 borrowAmount = calculateSafeBorrowAmount();
            require(borrowAmount > 0, "Borrow amount is zero");

            Pool.borrow(borrowToken, borrowAmount, 2, 0, address(this));
        } 
        
        ...
    }
```

Borrowing cap was handled by the `calculateSafeBorrowAmount` function which is a simple calculation to ensure that the borrow amount is not greater than the available collateral amount.

```solidity
    function calculateSafeBorrowAmount()
        public
        view
        returns (uint256 borrowAmount)
    {
        (, , uint256 availableBorrowsBase, , , ) = Pool.getUserAccountData(
            address(this)
        );

        if (availableBorrowsBase == 0) {
            return 0;
        }

        uint256 safeBorrowsBase = (availableBorrowsBase * SAFETY_FACTOR_PERCENT) / DENOMINATOR;

        uint256 borrowTokenPriceBase = priceOracle.getAssetPrice(borrowToken);

        // Ensure price is not zero before division
        require(borrowTokenPriceBase > 0, "Price feed unavailable");

        uint256 conversionFactor = 10 ** (BASE_CURRENCY_DECIMALS - BORROW_TOKEN_DECIMALS); // 100

        // Result in 8-decimal equivalent units (e.g., 95 * 1e8 for USDC)
        uint256 tokenAmount8Decimals = (safeBorrowsBase * 10 ** BASE_CURRENCY_DECIMALS) / borrowTokenPriceBase;

        // Scale down from 8 decimals to 6 decimals (USDC standard)
        // Divides by 10^(8-6) = 100
        borrowAmount = tokenAmount8Decimals / conversionFactor;

        return borrowAmount;
    }
```

The numerator was 3500 i.e 35% of what can be borrowed to allow for safe calling of the borrow function and keeping the health factor up.

```solidity
    uint256 private constant SAFETY_FACTOR_PERCENT = 3500;
    uint256 private constant DENOMINATOR = 10000;
```

The full code can be found [here](https://github.com/NatX223/ReactiveLooper/blob/main/Contracts/src/Looper.sol)

#### 4. Swapping back to Collateral token

After the borrow function has been called - the `BorrowReactive` function tracks the borrow event and then reacts to this by calling the callback to swap the tokens bacl to the collateral tokens.

Reacting to borrow event

```solidity
    constructor(
        address _looper,
        address _pool
    ) payable {
        looper = _looper;
        pool = _pool;
        service = ISystemContract(payable(SERVICE));
        if (!vm) {
            service.subscribe(
                chainId,
                _pool,
                eventTopic0,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
        }
    }
```

Reacting - calling the callback function

```solidity
    function react(LogRecord calldata log) external vmOnly {
        address borrower = address(uint160(log.topic_2));

        if (borrower == looper) {
            bytes memory payload = abi.encodeWithSignature(
                "callback(address,uint256)",
                address(0),
                2
            );

            emit Callback(chainId, looper, GAS_LIMIT, payload);
        }
    }
```

The full code can be found [here](https://github.com/NatX223/ReactiveLooper/blob/main/Contracts/src/BorrowReactive.sol)

This calls the callback to swap the tokens back to the collateral token.
A swapper contract was developed and deployed for this project and the slippage was handled by setting the amountOutMinimum to 0.

Swapping tokens

```solidity
    function swapAsset(
        address inToken,
        address outToken,
        uint256 amount
    ) public returns (uint256 amountOut) {
        TransferHelper.safeTransferFrom(inToken, msg.sender, address(this), amount);
        TransferHelper.safeApprove(inToken, address(swapRouter), amount);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: inToken,
                tokenOut: outToken,
                fee: poolFee,
                recipient: msg.sender,
                amountIn: amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        amountOut = swapRouter.exactInputSingle(params);

        emit swapEvent(outToken, msg.sender);
    }
```

The full code can be found [here](https://github.com/NatX223/ReactiveLooper/blob/main/Contracts/src/Swapper.sol)

The Looper contract calls this swapAsset function to get the assets swapped so the collateral can be resupplied

```solidity
    function callback(
        address sender,
        uint256 operation
    ) external authorizedSenderOnly rvmIdOnly(sender) {
        ...
        
        else if (operation == 2) {
            uint256 borrowTokenBalance = IERC20(borrowToken).balanceOf(address(this));
            require(borrowTokenBalance > 0, "Borrow token balance is zero");
            TransferHelper.safeApprove(borrowToken, address(Swapper), borrowTokenBalance);

            Swapper.swapAsset(borrowToken, collateralToken, borrowTokenBalance);
        }
    }
```

The full code can be found [here](https://github.com/NatX223/ReactiveLooper/blob/main/Contracts/src/Swapper.sol)

#### 5. Resupplying Collateral

After the collateral tokens have been swapped back, the swapper contract emits an event that the `SwapReactive` contract picks up and reacts by calling the Looper callback function to supply the collateral token this completing the final step in the loop.

Subscribing

```solidity
    constructor(
        address _looper,
        address _swapper
    ) payable {
        looper = _looper;
        swapper = _swapper;
        service = ISystemContract(payable(SERVICE));
        if (!vm) {
            service.subscribe(
                chainId,
                _swapper,
                eventTopic0,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
        }
    }
```

Reacting

```solidity
    function react(LogRecord calldata log) external vmOnly {
        address swapper_ = address(uint160(log.topic_2));

        if (swapper_ == looper) {
            bytes memory payload = abi.encodeWithSignature(
                "callback(address,uint256)",
                address(0),
                0
            );

            emit Callback(chainId, looper, GAS_LIMIT, payload);
        }
    }
```

### Contracts

| Contract                                      | Address                                      | Chain   |
| --------------------------------------------- | -------------------------------------------- | ------- |
| **Aave v3 Pool**                              | [0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951](https://sepolia.etherscan.io/address/0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951) | sepolia |
| **Collateral Token (WETH)**                   | [0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c](https://sepolia.etherscan.io/address/0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c) | sepolia |
| **Borrow Token (USDC)**                       | [0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8](https://sepolia.etherscan.io/address/0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8) | sepolia |
| **Looper**                                    | [0x534028e697fbAF4D61854A27E6B6DBDc63Edde8c](https://sepolia.etherscan.io/address/0x534028e697fbAF4D61854A27E6B6DBDc63Edde8c) | sepolia |
| **Swapper**                                   | [0x8D9E25C7b0439781c7755e01A924BbF532EDf24d](https://sepolia.etherscan.io/address/0x8D9E25C7b0439781c7755e01A924BbF532EDf24d) | sepolia |
| **TransferReactive**                          | [0xA6b51C26dfe550dCBDcac2eb2931962612c508B9](https://lasna.reactscan.net/address/0x58e95d9300254fbba4a6b0b8abc5e94bf9dc4c52/contract/0xa6b51c26dfe550dcbdcac2eb2931962612c508b9) | lasna   |
| **SupplyReactive**                            | [0xF2cD21975a70B9DA83e4f902Dd854B433d7F3B5E](https://lasna.reactscan.net/address/0x58e95d9300254fbba4a6b0b8abc5e94bf9dc4c52/contract/0xF2cD21975a70B9DA83e4f902Dd854B433d7F3B5E) | lasna   |
| **BorrowReactive**                            | [0xf6D2E24127FE52b254bB34FaB4a934FfA305A3a7](https://lasna.reactscan.net/address/0x58e95d9300254fbba4a6b0b8abc5e94bf9dc4c52/contract/0xf6D2E24127FE52b254bB34FaB4a934FfA305A3a7) | lasna   |
| **SwapReactive**                              | [0x548E710cEBD460FcD18189766F7826D5BDB554bb](https://lasna.reactscan.net/address/0x58e95d9300254fbba4a6b0b8abc5e94bf9dc4c52/contract/0x548E710cEBD460FcD18189766F7826D5BDB554bb) | lasna   |

### Transactions

| Function                                                                            | Transaction hash                                                     | Chain   |
| ----------------------------------------------------------------------------------- | -------------------------------------------------------------------- | ------- |
| **User Opt-in**                  | [0xd3c22173e519704a49392b45ff2e23afa666a788194b3b0bdc98030416d1f898](https://sepolia.etherscan.io/tx/0xd3c22173e519704a49392b45ff2e23afa666a788194b3b0bdc98030416d1f898) | sepolia |
| **Reacting to Transfer event**   | [0xb83c64620b5b535c09883123b594206457e2ed1b209dede9396f91331e01d9a7](https://lasna.reactscan.net/address/0x58e95d9300254fbba4a6b0b8abc5e94bf9dc4c52/4112) | lasna   |
| **Callback - Supply Collateral** | [0xdac83b780d302ef780569fa664f286f16875875b8db02dfaf9c69a8701c8f0c0](https://sepolia.etherscan.io/tx/0xdac83b780d302ef780569fa664f286f16875875b8db02dfaf9c69a8701c8f0c0) | sepolia |
| **Reacting to Supply event**     | [0x3f19641b3f4f625c24bb7db3c444b6c5f96c25a5af78da9f37d555aa89aa0232](https://lasna.reactscan.net/address/0x58e95d9300254fbba4a6b0b8abc5e94bf9dc4c52/4116) | lasna   |
| **Callback - Borrow USDC**       | [0x0177077a97289f8df3bad84fbb20cb85d331c55f78392bb8fb395c1264ba38a5](https://sepolia.etherscan.io/tx/0x0177077a97289f8df3bad84fbb20cb85d331c55f78392bb8fb395c1264ba38a5) | sepolia   |
| **Reacting to Borrow event**     | [0x8173fcf3451bfa1f4c44a995a25f293c523ae056597624166ae03a643baceaf5](https://lasna.reactscan.net/address/0x58e95d9300254fbba4a6b0b8abc5e94bf9dc4c52/4120) | lasna   |
| **Callback - Swapping tokens**   | [0x1cbfa8faea94eb5fe259376b8210d3e4c5e93b00bc96809b593782592fc3ec07](https://sepolia.etherscan.io/tx/0x1cbfa8faea94eb5fe259376b8210d3e4c5e93b00bc96809b593782592fc3ec07) | sepolia   |

## Setup and Deployment

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) installed
- Node.js 16+ for additional tooling
- Testnet/mainnet RPC endpoints
- Private key with testnet/Mainnet React and ETH

### Installation

```bash
# Clone the repository
git clone https://github.com/NatX223/ReactiveLooperV3
cd ReactiveLooperV3/Contracts

# Install dependencies
forge install

# Compile contracts
forge compile
```

### Configuration

1. Copy the environment template:

```bash
cp Contracts/.env.example Contracts/.env
```

2. Configure your deployment settings:

```env
PRIVATE_KEY=your_private_key
LASNA_RPC_URL=https://lasna-rpc.rnk.dev/ or mainnet
LASNA_SERVICE_ADDRESS=0x0000000000000000000000000000000000fffFfF
LASNA_CHAIN_ID=5318007
SEPOLIA_RPC_URL=https://ethereum-sepolia-rpc.publicnode.com or any chainlink supported chain rpc url
SEPOLIA_SERVICE_ADDRESS=0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA
SEPOLIA_CHAIN_ID=11155111 or any Aave & Uniswap supported chain id
AAVE_V3_POOL_ADDRESS=0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951 or Aave pool address on chosen chain
AAVE_V3_POOL_PROVIDER_ADDRESS=0x012bAC54348C0E635dCAc9D5FB99f06F24136C9A or Aave pool provider address on chosen chain
AAVE_V3_ORACLE_ADDRESS=0x2da88497588bf89281816106C7259e31AF45a663 or Aave orcale address on chosen chain
WETH_ADDRESS=0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c or any WETH address on chosen chain
USDC_ADDRESS=0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8 or any WETH address on chosen chain
```

### Deployment

#### Testnet Deployment

Deploy the Swapper to sepolia

```bash
forge create --broadcast --rpc-url sepoliaRPC --private-key $PRIVATE_KEY src/Swapper.sol:Swapper
```

Deploy the Looper to sepolia

```bash
forge create --broadcast --rpc-url sepoliaRPC --private-key $PRIVATE_KEY src/Looper.sol:Looper --value 0.02ether --constructor-args 0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8 0x012bAC54348C0E635dCAc9D5FB99f06F24136C9A 0x2da88497588bf89281816106C7259e31AF45a663 swapper_address
```

Deploy the TransferReactive contract to lasna

```bash
forge create --broadcast --rpc-url lasnaRPC --private-key $PRIVATE_KEY src/TransferReactive.sol:TransferReactive --value 1.5ether --constructor-args looper_address 0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c
```

Deploy the SupplyReactive contract to lasna

```bash
forge create --broadcast --rpc-url lasnaRPC --private-key $PRIVATE_KEY src/SupplyReactive.sol:SupplyReactive --value 1ether --constructor-args looper_address 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951
```

Deploy the BorrowReactive contract to lasna

```bash
forge create --broadcast --rpc-url lasnaRPC --private-key $PRIVATE_KEY src/BorrowReactive.sol:BorrowReactive --value 1ether --constructor-args looper_address 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951
```

Deploy the SwapReactive contract to lasna

```bash
forge create --broadcast --rpc-url lasnaRPC --private-key $PRIVATE_KEY src/SwapReactive.sol:SwapReactive --value 1ether --constructor-args looper_address swapper_address
```

Opting in

Obtaining WETH
```bash
cast send --rpc-url sepoliaRPC --private-key $PRIVATE_KEY 0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c --value amount_ether "deposit(uint256)" amount_ether
```

sending WETH to looper contract
```bash
cast send --rpc-url sepoliaRPC --private-key $PRIVATE_KEY 0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c "transfer(address,uint256)" looper_address amount
```

Running dapp locally
```bash
cd app

npm run dev
```

## 🧪 Testing

### Run Tests

```bash
# Run all tests
forge test -vv

# Run specific test contracts
forge test --match-contract LooperTest -vv
forge test --match-contract IntegrationTest -vv

# Run with gas reporting
forge test --gas-report -vv

# Run specific test functions
forge test --match-test testFullLeverageLoop -vv
```

## Bounty Requirements

- Slippage on swaps - This was handled by the Swapper contract using mininum amount out to 0 thus setting the maximum slipage.

```solidity
    function swapAsset(
        address inToken,
        address outToken,
        uint256 amount
    ) public returns (uint256 amountOut) {
        /** @dev Transfer input tokens from caller to this contract */
        TransferHelper.safeTransferFrom(inToken, msg.sender, address(this), amount);
        
        /** @dev Approve SwapRouter to spend input tokens */
        TransferHelper.safeApprove(inToken, address(swapRouter), amount);

        /** @dev Configure swap parameters for exact input single-hop swap */
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: inToken,
                tokenOut: outToken,
                fee: poolFee,
                recipient: msg.sender,
                amountIn: amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        /** @dev Execute the swap and get output amount */
        amountOut = swapRouter.exactInputSingle(params);

        emit swapEvent(outToken, msg.sender);
    }
```
- Borrow Cap - This was handled by the getting the maximum borrow amount and then borrowing only 35% of it, thus lowering the borrow cap.

```solidity
    function calculateSafeBorrowAmount()
        public
        view
        returns (uint256 borrowAmount)
    {
        (, , uint256 availableBorrowsBase, , , ) = Pool.getUserAccountData(
            address(this)
        );

        if (availableBorrowsBase == 0) {
            return 0;
        }

        /** @dev Apply safety factor to available borrows to prevent liquidation */
        uint256 safeBorrowsBase = (availableBorrowsBase * SAFETY_FACTOR_PERCENT) / DENOMINATOR;

        /** @dev Get current price of borrow token from oracle */
        uint256 borrowTokenPriceBase = priceOracle.getAssetPrice(borrowToken);

        // Ensure price is not zero before division
        require(borrowTokenPriceBase > 0, "Price feed unavailable");

        /** @dev Conversion factor to adjust for decimal differences between base currency and borrow token */
        uint256 conversionFactor = 10 ** (BASE_CURRENCY_DECIMALS - BORROW_TOKEN_DECIMALS); // 100

        /** @dev Convert base currency amount to token amount (8-decimal equivalent units) */
        uint256 tokenAmount8Decimals = (safeBorrowsBase * 10 ** BASE_CURRENCY_DECIMALS) / borrowTokenPriceBase;

        /** @dev Scale down from 8 decimals to borrow token decimals (e.g., USDC 6 decimals) */
        borrowAmount = tokenAmount8Decimals / conversionFactor;

        return borrowAmount;
    }
```

## Future improvements

We will be working on the safe unwind functionality as the future improvent to the project, this will aim to pay back all debts while returning the initial collateral to the user

## 🤝 Contributing

We welcome contributions! Please follow these steps:

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit your changes: `git commit -m 'Add amazing feature'`
4. Push to the branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

### Development Guidelines

- Follow Solidity style guide
- Add comprehensive tests for new features
- Update documentation for API changes
- Ensure all tests pass before submitting

- **Documentation**: [Project README](https://github.com/NatX223/ReactiveLooper/blob/main/README.md/)

## Acknowledgments

- [Reactive Network](https://reactive.network/) for cross-chain infrastructure
- [Aave](https://aave.com/docs/aave-v3/smart-contracts/pool) for the lending protocol
- [Uniswap](https://docs.uniswap.org/contracts/v3/overview) for the swapping protocol
- [Foundry](https://book.getfoundry.sh/) for development tooling

---

**Built with Reactive**
