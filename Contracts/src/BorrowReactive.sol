// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/reactive-lib/src/interfaces/ISystemContract.sol";
import "../lib/reactive-lib/src/abstract-base/AbstractPausableReactive.sol";
import "../lib/reactive-lib/src/interfaces/IReactive.sol";

/**
 * @title BorrowReactive
 * @dev Reactive contract that monitors borrow events and triggers the next step in leverage loop
 * @notice This contract listens for borrow events from Aave pool and automatically triggers
 *         the swap operation in the Looper contract to complete the leverage cycle
 */
contract BorrowReactive is IReactive, AbstractPausableReactive {
    /** @dev Maximum gas limit allocated for callback execution to prevent out-of-gas errors */
    uint64 private constant GAS_LIMIT = 1000000;
    
    /** @dev Address of the reactive system service contract that manages event subscriptions */
    address public constant SERVICE = 0x0000000000000000000000000000000000fffFfF;

    /** @dev Chain ID for Ethereum Sepolia testnet */
    uint256 private chainId = 11155111;

    /** @dev Event topic hash used to filter and subscribe to borrow events from the pool contract */
    uint256 private eventTopic0 = 0xb3d084820fb1a9decffb176436bd02558d15fac9b0ddfed8c465bc7359d7dce0;

    /** @dev Address of the Looper contract that will receive callback notifications */
    address public looper;

    /** @dev Address of the Aave pool contract to monitor for borrow events */
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
     * @dev Initializes the BorrowReactive contract and sets up event subscription
     * @param _looper Address of the Looper contract to send callbacks to
     * @param _pool Address of the Aave pool contract to monitor for borrow events
     * @notice Automatically subscribes to borrow events from the specified pool
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
     * @dev Reacts to borrow events and triggers the swap operation in Looper
     * @param log The log record containing the borrow event data
     * @notice When the Looper contract borrows tokens, this function automatically
     *         triggers operation 2 (swap) to convert borrowed tokens back to collateral
     */
    function react(LogRecord calldata log) external vmOnly {
        /** @dev Extract borrower address from the log topic */
        address borrower = address(uint160(log.topic_2));

        if (borrower == looper) {
            /** @dev Encode callback payload for swap operation (operation 2) */
            bytes memory payload = abi.encodeWithSignature(
                "callback(address,uint256)",
                address(0),
                2
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
