# ReactiveLooper
DeFi lending looper - leverage optimizer powered by Reactive network

---

## Live Link - 

## Demo - https://www.loom.com/share/407ac34f351c4b08a5e7173f1ce75c8d

## Table of Contents

1. [Overview](#overview)
2. [Problem Statement](#problem-statement)
3. [Solution](#solution)
4. [How It Works](#how-it-works)
5. [Transactions](#transactions)
6. [Setup and Deployment](#setup-and-deployment)
7. [Future Improvements](#future-improvements)
8. [Acknowledgments](#acknowledgments)

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

Below is an Imgae depicting the architecture of the ReactiveAggregator project.
           
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
git clone https://github.com/NatX223/ReactiveAggregatorV3Interface
cd ReactiveAggregatorV3Interface/Contracts

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
SEPOLIA_CHAIN_ID=11155111 or any chainlink supported chain id
PRICE_FEED_AGGREGATOR=0x17Dac87b07EAC97De4E182Fc51C925ebB7E723e2 or custom price feed aggregator address on chosen chain
AGGREGATOR_PROXY=0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43 or  custom aggregator proxy address on chosen chain
ANSWER_UPDATED_EVENT=0x0559884fd3a460db3073b7fc896cc77986f16e378210ded43186175bf646fc5f
FEED_READ_EVENT=0x211b0a6d1ea05edd12db159c3307872cdca106fc791b06a6baad5e124f39070e
```

### Deployment

#### Testnet Deployment

Deploy the feed reader to sepolia

```bash
forge create --broadcast --rpc-url sepoliaRPC --private-key $PRIVATE_KEY src/FeedReader.sol:FeedReader --value 0.005ether --constructor-args 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43 0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA
```

Deploy the AGGReactive contract to lasna

```bash
forge create --broadcast --rpc-url lasnaRPC --private-key $PRIVATE_KEY src/AGGReactive.sol:AGGReactive --value 1ether --constructor-args feed_reader_address 0x17Dac87b07EAC97De4E182Fc51C925ebB7E723e2 0x0559884fd3a460db3073b7fc896cc77986f16e378210ded43186175bf646fc5f 11155111 0x0000000000000000000000000000000000fffFfF
```

Deploy the feed proxy to lasna

```bash
forge create --broadcast --rpc-url lasnaRPC --private-key $PRIVATE_KEY src/FeedProxy.sol:FeedProxy --value 1ether --constructor-args 0x0000000000000000000000000000000000fffFfF
```

Deploy the reactive proxy contract to lasna

```bash
forge create --broadcast --rpc-url lasnaRPC --private-key $PRIVATE_KEY src/ReactiveProxy.sol:ReactiveProxy --value 1ether --constructor-args feed_proxy_address feed_reader_address  0x211b0a6d1ea05edd12db159c3307872cdca106fc791b06a6baad5e124f39070e 11155111 5318007 0x0000000000000000000000000000000000fffFfF
```

## 🧪 Testing

### Run Tests

```bash
# Run all tests
forge test

# Run with verbose output
forge test -vvv

# Run specific test
forge test --match-test test_ComparePriceFeedData -vvv
```

## 📊 Usage Examples

### Reading Price Data

```solidity
import "./src/FeedProxy.sol";

contract PriceConsumer {
    FeedProxy public priceFeed;

    constructor(address _feedProxy) {
        priceFeed = FeedProxy(_feedProxy);
    }

    function getLatestPrice() public view returns (int256) {
        (,int256 price,,,) = priceFeed.latestRoundData();
        return price;
    }

    function getPriceDecimals() public view returns (uint8) {
        return priceFeed.decimals();
    }
}
```

## 🛡️ Security Considerations

### Access Control

- All callback functions use `authorizedSenderOnly` modifier
- Reactive VM validation with `rvmIdOnly` checks
- Pausable subscriptions for emergency stops

### Data Integrity

- Tracking AnswerUpdated event for latest data and fee optimization
- Comprehensive event validation
- Timestamp verification for freshness
- Round ID tracking to prevent replay attacks

### Best Practices

- Always verify price data freshness
- Implement circuit breakers for extreme price movements
- Use multiple price sources when possible

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

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](https://github.com/NatX223/ReactiveAggregatorV3Interface?tab=GPL-3.0-1-ov-file#readme) file for details.

## 🆘 Support

- **Documentation**: [Project Wiki](https://github.com/NatX223/ReactiveAggregatorV3Interface/wiki)
- **Issues**: [GitHub Issues](https://github.com/NatX223/ReactiveAggregatorV3Interface/issues)
- **Discussions**: [GitHub Discussions](https://github.com/NatX223/ReactiveAggregatorV3Interface/discussions)

## 🙏 Acknowledgments

- [Reactive Network](https://reactive.network/) for cross-chain infrastructure
- [Chainlink](https://chain.link/) for the AggregatorV3Interface standard
- [Foundry](https://book.getfoundry.sh/) for development tooling

---

**Built with Reactive**
