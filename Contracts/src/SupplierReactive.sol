// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/reactive-lib/src/interfaces/ISystemContract.sol";
import "../lib/reactive-lib/src/abstract-base/AbstractPausableReactive.sol";
import "../lib/reactive-lib/src/interfaces/IReactive.sol";

contract SupplierReactive is IReactive, AbstractPausableReactive {
    /* Maximum gas limit allocated for callback execution to prevent out-of-gas errors */
    uint64 private constant GAS_LIMIT = 1000000;

    address public constant SERVICE = 0x0000000000000000000000000000000000fffFfF;
    uint256 private CHAIN_ID = 11155111;
    uint256 private EVENT_TOPIC_0 = ;

    address public borrowerCallback;

    constructor(address _borrower) payable {
        borrowerCallback = _borrower;
        service = ISystemContract(payable(SERVICE));
        if (!vm) {
            service.subscribe(CHAIN_ID, _borrower, EVENT_TOPIC_0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
        }
    }

    function getPausableSubscriptions() internal view override returns (Subscription[] memory) {
        Subscription[] memory result = new Subscription[](1);
        result[0] = Subscription(
            CHAIN_ID,
            address(SERVICE),
            EVENT_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        return result;
    }

    function react(LogRecord calldata log) external vmOnly {
        // address recipient = address(uint160(log.topic_1));

        bytes memory payload = abi.encodeWithSignature(
            "callback(address)",
            address(0)
        );

        emit Callback(chainId, borrowerCallback, GAS_LIMIT, payload);
    }
}