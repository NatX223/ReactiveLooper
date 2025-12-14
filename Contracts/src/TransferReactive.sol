// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/reactive-lib/src/interfaces/ISystemContract.sol";
import "../lib/reactive-lib/src/abstract-base/AbstractPausableReactive.sol";
import "../lib/reactive-lib/src/interfaces/IReactive.sol";

/**
 * @title TransferReactive
 * @dev Reactive contract that monitors token transfers and initiates leverage loops
 * @notice This contract listens for ERC20 transfer events from initiator to looper
 *         and automatically triggers the initial supply operation to start the leverage cycle
 */
contract TransferReactive is IReactive, AbstractPausableReactive {
    /** @dev Maximum gas limit allocated for callback execution to prevent out-of-gas errors */
    uint64 private constant GAS_LIMIT = 1000000;
    
    /** @dev Address of the reactive system service contract that manages event subscriptions */
    address public constant SERVICE = 0x0000000000000000000000000000000000fffFfF;

    /** @dev Chain ID for Ethereum Sepolia testnet */
    uint256 private chainId = 11155111;

    /** @dev Event topic hash for ERC20 Transfer events (keccak256("Transfer(address,address,uint256)")) */
    uint256 private eventTopic0 = 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;

    /** @dev Address of the Looper contract that will receive callback notifications */
    address public looper;

    /** @dev Address of the collateral token contract to monitor for transfers */
    address public collateralToken;

    /** @dev Address of the user who initiated the leverage loop */
    address public initiator;

    /*
     * Event emitted when the contract receives Ether payments
     * @param origin The original transaction initiator (tx.origin)
     * @param sender The direct sender of the transaction (msg.sender)
     * @param value The amount of Ether received in wei
     */
    event Received(
        address indexed origin,
        address indexed sender,
        uint256 indexed value
    );

    /**
     * @dev Initializes the TransferReactive contract and sets up event subscription
     * @param _looper Address of the Looper contract to send callbacks to
     * @param _collateralToken Address of the collateral token to monitor for transfers
     * @notice Automatically subscribes to Transfer events from the specified collateral token
     *         and sets the deployer as the initiator who can trigger leverage loops
     */
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

    /*
     * Returns the list of event subscriptions that can be paused/unpaused.
     * Required implementation for AbstractPausableReactive functionality.
     * @return Array of Subscription structs containing subscription configuration details
     */
    function getPausableSubscriptions()
        internal
        view
        override
        returns (Subscription[] memory)
    {
        Subscription[] memory result = new Subscription[](1);
        result[0] = Subscription(
            chainId,
            address(SERVICE),
            eventTopic0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        return result;
    }

    /**
     * @dev Reacts to token transfer events and initiates the leverage loop
     * @param log The log record containing the transfer event data
     * @notice When the initiator transfers collateral tokens to the Looper contract,
     *         this function automatically triggers operation 0 (supply) to start the leverage cycle
     */
    function react(LogRecord calldata log) external vmOnly {
        /** @dev Extract sender and receiver addresses from the transfer event */
        address sender = address(uint160(log.topic_1));
        address receiver = address(uint160(log.topic_2));

        if (sender == initiator && receiver == looper) {
            /** @dev Encode callback payload for supply operation (operation 0) to start the loop */
            bytes memory payload = abi.encodeWithSignature(
                "callback(address,uint256)",
                address(0),
                0
            );

            emit Callback(chainId, looper, GAS_LIMIT, payload);
        }
    }

    /*
     * Handles incoming Ether payments to the contract.
     * Emits a Received event to log transaction details for monitoring purposes.
     */
    receive() external payable override(AbstractPayer, IPayer) {
        emit Received(tx.origin, msg.sender, msg.value);
    }
}
