// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "../lib/reactive-lib/src/abstract-base/AbstractCallback.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../lib/aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";
import "../lib/aave-v3-core/contracts/interfaces/IPool.sol";
import "../lib/aave-v3-core/contracts/interfaces/IPriceOracle.sol";
import "./ISwapper.sol";
import "./library/TransferHelper.sol";

contract Looper is AbstractCallback, Ownable {
    address public constant SERVICE = 0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA;

    address public collateralToken;
    address public borrowToken;

    IPoolAddressesProvider public immutable ADDRESS_PROVIDER;
    IPool public immutable Pool;
    IPriceOracle public immutable priceOracle;

    ISwapper public immutable Swapper;

    uint256 private constant SAFETY_FACTOR_PERCENT = 3500;
    uint256 private constant DENOMINATOR = 10000;

    // Aave V3 Base Currency (e.g., USD) uses 8 decimals for pricing.
    uint8 private constant BASE_CURRENCY_DECIMALS = 8;

    // USDC uses 6 decimals.
    uint8 private constant BORROW_TOKEN_DECIMALS = 6;

    constructor(
        address _collateralToken,
        address _borrowToken,
        address _poolAddressProvider,
        address _priceOracle,
        address _swapper
    ) payable AbstractCallback(SERVICE) Ownable(msg.sender) {
        collateralToken = _collateralToken;
        borrowToken = _borrowToken;

        priceOracle = IPriceOracle(_priceOracle);
        ADDRESS_PROVIDER = IPoolAddressesProvider(_poolAddressProvider);
        Pool = IPool(ADDRESS_PROVIDER.getPool());
        Swapper = ISwapper(_swapper);
    }

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
        
        else if (operation == 1) {
            uint256 borrowAmount = calculateSafeBorrowAmount();
            require(borrowAmount > 0, "Borrow amount is zero");

            Pool.borrow(borrowToken, borrowAmount, 2, 0, address(this));
        } 
        
        else if (operation == 2) {
            uint256 borrowTokenBalance = IERC20(borrowToken).balanceOf(address(this));
            require(borrowTokenBalance > 0, "Borrow token balance is zero");
            TransferHelper.safeApprove(borrowToken, address(Swapper), borrowTokenBalance);

            Swapper.swapAsset(borrowToken, collateralToken, borrowTokenBalance);
        }
    }
}
