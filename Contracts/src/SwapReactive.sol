// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/reactive-lib/src/interfaces/ISystemContract.sol";
import "../lib/reactive-lib/src/abstract-base/AbstractPausableReactive.sol";
import "../lib/reactive-lib/src/interfaces/IReactive.sol";

contract SwapReactive is IReactive, AbstractPausableReactive {
    /* Maximum gas limit allocated for callback execution to prevent out-of-gas errors */
    uint64 private constant GAS_LIMIT = 1000000;
    
    /* Address of the reactive system service contract that manages event subscriptions */
    address public constant SERVICE = 0x0000000000000000000000000000000000fffFfF;

    uint256 private chainId = 11155111;

    /* Event topic hash used to subscribe to borrow initiated event from the looper contract */
    uint256 private eventTopic0 = 0x783bd8472ba2d01baf38569a5cdfaaa209e19da07cfaa1008df9cd1597910389;

    /* Address of the Looper contract that will receive callback notifications */
    address public looper;

    address public swapper;

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

    /*
     * Handles incoming Ether payments to the contract.
     * Emits a Received event to log transaction details for monitoring purposes.
     */
    receive() external payable override(AbstractPayer, IPayer) {
        emit Received(tx.origin, msg.sender, msg.value);
    }
}
