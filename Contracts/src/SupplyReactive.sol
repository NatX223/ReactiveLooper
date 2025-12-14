// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/reactive-lib/src/interfaces/ISystemContract.sol";
import "../lib/reactive-lib/src/abstract-base/AbstractPausableReactive.sol";
import "../lib/reactive-lib/src/interfaces/IReactive.sol";

/**
 * @title SupplyReactive
 * @dev Reactive contract that monitors supply events and triggers borrowing in leverage loop
 * @notice This contract listens for supply events from Aave pool and automatically triggers
 *         the borrow operation in the Looper contract to continue the leverage cycle
 */
contract SupplyReactive is IReactive, AbstractPausableReactive {
    /** @dev Maximum gas limit allocated for callback execution to prevent out-of-gas errors */
    uint64 private constant GAS_LIMIT = 1000000;
    
    /** @dev Address of the reactive system service contract that manages event subscriptions */
    address public constant SERVICE = 0x0000000000000000000000000000000000fffFfF;

    /** @dev Chain ID for Ethereum Sepolia testnet */
    uint256 private chainId = 11155111;

    /** @dev Event topic hash used to subscribe to supply events from the pool contract */
    uint256 private eventTopic0 = 0x2b627736bca15cd5381dcf80b0bf11fd197d01a037c52b927a881a10fb73ba61;

    /** @dev Address of the Looper contract that will receive callback notifications */
    address public looper;

    /** @dev Address of the Aave pool contract to monitor for supply events */
    address public pool;

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
     * @dev Initializes the SupplyReactive contract and sets up event subscription
     * @param _looper Address of the Looper contract to send callbacks to
     * @param _pool Address of the Aave pool contract to monitor for supply events
     * @notice Automatically subscribes to supply events from the specified pool
     */
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
     * @dev Reacts to supply events and triggers the borrow operation in Looper
     * @param log The log record containing the supply event data
     * @notice When the Looper contract supplies collateral, this function automatically
     *         triggers operation 1 (borrow) to borrow against the supplied collateral
     */
    function react(LogRecord calldata log) external vmOnly {
        /** @dev Extract supplier address from the log topic */
        address supplier = address(uint160(log.topic_2));

        if (supplier == looper) {
            /** @dev Encode callback payload for borrow operation (operation 1) */
            bytes memory payload = abi.encodeWithSignature(
                "callback(address,uint256)",
                address(0),
                1
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
