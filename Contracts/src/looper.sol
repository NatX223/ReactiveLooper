// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/reactive-lib/src/interfaces/ISystemContract.sol";
import "../lib/reactive-lib/src/abstract-base/AbstractPausableReactive.sol";
import "../lib/reactive-lib/src/interfaces/IReactive.sol";

contract AggReactive is IReactive, AbstractPausableReactive {
    /* Maximum gas limit allocated for callback execution to prevent out-of-gas errors */
    uint64 private constant GAS_LIMIT = 1000000;
    
    /* Address of the reactive system service contract that manages event subscriptions */
    address public chainService;

    /* Blockchain network identifier where the price feed aggregator is deployed */
    uint256 private chainId;

    /* Event topic hash used to filter and subscribe to specific aggregator events */
    uint256 private eventTopic0;

    /* Address of the FeedReader contract that will receive callback notifications */
    address public feedReader;

    /* Address of the price feed aggregator contract to monitor for price update events */
    address public priceFeedAggregator;

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

    /*
     * Initializes the AggReactive contract and sets up event subscription to monitor price feed updates.
     * Subscribes to events from the specified price feed aggregator contract.
     * @param _feedReader Address of the FeedReader contract to notify via callbacks
     * @param _priceFeedAggregator Address of the price feed aggregator to monitor
     * @param _eventTopic0 Event topic hash to subscribe to (typically AnswerUpdated)
     * @param _chainId Blockchain network ID where the aggregator is deployed
     * @param _service Address of the reactive system service contract
     */
    constructor(
        address _feedReader,
        address _priceFeedAggregator,
        uint256 _eventTopic0,
        uint256 _chainId,
        address _service
    ) payable {
        feedReader = _feedReader;
        priceFeedAggregator = _priceFeedAggregator;
        chainService = _service;
        eventTopic0 = _eventTopic0;
        chainId = _chainId;
        service = ISystemContract(payable(_service));
        if (!vm) {
            service.subscribe(
                _chainId,
                _priceFeedAggregator,
                _eventTopic0,
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
            address(chainService),
            eventTopic0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        return result;
    }

    /*
     * Processes incoming log events from the subscribed price feed aggregator.
     * Triggers a callback to the FeedReader contract when price updates are detected.
     * @param log The log record containing event data from the price feed aggregator
     */
    function react(LogRecord calldata log) external vmOnly {
        // address recipient = address(uint160(log.topic_1));

        bytes memory payload = abi.encodeWithSignature(
            "callback(address)",
            address(0)
        );

        emit Callback(chainId, feedReader, GAS_LIMIT, payload);
    }

    /*
     * Handles incoming Ether payments to the contract.
     * Emits a Received event to log transaction details for monitoring purposes.
     */
    receive() external payable override(AbstractPayer, IPayer) {
        emit Received(tx.origin, msg.sender, msg.value);
    }
}
