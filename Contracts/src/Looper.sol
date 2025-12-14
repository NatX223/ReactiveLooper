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

/**
 * @title Looper
 * @dev Automated leverage looping contract that implements recursive supply-borrow-swap cycles
 * @notice This contract enables users to create leveraged positions by automatically:
 *         1. Supplying collateral to Aave
 *         2. Borrowing against the collateral
 *         3. Swapping borrowed tokens back to collateral
 *         4. Repeating the cycle to achieve desired leverage
 */
contract Looper is AbstractCallback, Ownable {
    /** @dev Address of the reactive system service contract */
    address public constant SERVICE = 0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA;

    /** @dev Address of the token used as collateral in the leverage loop */
    address public collateralToken;
    
    /** @dev Address of the token that will be borrowed against the collateral */
    address public borrowToken;

    /** @dev Aave V3 pool addresses provider contract interface */
    IPoolAddressesProvider public immutable ADDRESS_PROVIDER;
    
    /** @dev Aave V3 pool contract interface for lending operations */
    IPool public immutable Pool;
    
    /** @dev Aave V3 price oracle interface for asset pricing */
    IPriceOracle public immutable priceOracle;

    /** @dev Swapper contract interface for token exchanges */
    ISwapper public immutable Swapper;

    /** @dev Safety factor percentage to accomodate borrow cap (35% = 3500/10000) */
    uint256 private constant SAFETY_FACTOR_PERCENT = 3500;
    
    /** @dev Denominator for percentage calculations */
    uint256 private constant DENOMINATOR = 10000;

    /** @dev Aave V3 Base Currency (e.g., USD) uses 8 decimals for pricing */
    uint8 private constant BASE_CURRENCY_DECIMALS = 8;

    /** @dev USDC uses 6 decimals */
    uint8 private constant BORROW_TOKEN_DECIMALS = 6;

    /** @dev Target Leverage user wants */
    uint256 private leverage;

    event leverageAttained(address indexed looper);

    /**
     * @dev Initializes the Looper contract with required addresses and interfaces
     * @param _collateralToken Address of the token to be used as collateral
     * @param _borrowToken Address of the token to be borrowed
     * @param _poolAddressProvider Address of Aave V3 pool addresses provider
     * @param _priceOracle Address of Aave V3 price oracle
     * @param _swapper Address of the swapper contract for token exchanges
     */
    constructor(
        address _collateralToken,
        address _borrowToken,
        address _poolAddressProvider,
        address _priceOracle,
        address _swapper,
        uint256 _leverage
    ) payable AbstractCallback(SERVICE) Ownable(msg.sender) {
        collateralToken = _collateralToken;
        borrowToken = _borrowToken;
        leverage = _leverage;

        priceOracle = IPriceOracle(_priceOracle);
        ADDRESS_PROVIDER = IPoolAddressesProvider(_poolAddressProvider);
        Pool = IPool(ADDRESS_PROVIDER.getPool());
        Swapper = ISwapper(_swapper);
    }

    /**
     * @dev Calculates the safe amount that can be borrowed without risking liquidation
     * @notice Applies a safety factor to prevent the position from being too close to liquidation threshold
     * @return borrowAmount The maximum safe amount that can be borrowed in borrow token units
     */
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

    /**
     * @dev Callback function executed by reactive contracts to perform leverage loop operations
     * @param sender Address of the reactive contract calling this function
     * @param operation Operation type to execute:
     *                  0 = Supply collateral to Aave
     *                  1 = Borrow against supplied collateral
     *                  2 = Swap borrowed tokens back to collateral
     * @notice This function implements the core leverage looping logic through three sequential operations
     */
    function callback(
        address sender,
        uint256 operation
    ) external authorizedSenderOnly rvmIdOnly(sender) {
        if (operation == 0) {
            /** @dev Operation 0: Supply all available collateral tokens to Aave pool */
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
            /** @dev Operation 1: Borrow maximum safe amount against supplied collateral */
            (, , , , uint256 ltv, ) = Pool.getUserAccountData(
                address(this)
            );
            if (ltv == leverage) {
                emit leverageAttained(address(this));
            } else {
            uint256 borrowAmount = calculateSafeBorrowAmount();
            require(borrowAmount > 0, "Borrow amount is zero");

            Pool.borrow(borrowToken, borrowAmount, 2, 0, address(this));
            }
        } 
        
        else if (operation == 2) {
            /** @dev Operation 2: Swap all borrowed tokens back to collateral tokens */
            uint256 borrowTokenBalance = IERC20(borrowToken).balanceOf(address(this));
            require(borrowTokenBalance > 0, "Borrow token balance is zero");
            TransferHelper.safeApprove(borrowToken, address(Swapper), borrowTokenBalance);

            Swapper.swapAsset(borrowToken, collateralToken, borrowTokenBalance);
        }
    }
}
