//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  CygnusNebula.sol
//
//  Copyright (C) 2023 CygnusDAO
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.

/*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
    
           █████████                🛸         🛸                              🛸          .                    
     🛸   ███░░░░░███                                              📡                                     🌔   
         ███     ░░░  █████ ████  ███████ ████████   █████ ████  █████        ⠀
        ░███         ░░███ ░███  ███░░███░░███░░███ ░░███ ░███  ███░░      .     .⠀        🛰️   .             
        ░███          ░███ ░███ ░███ ░███ ░███ ░███  ░███ ░███ ░░█████       ⠀
        ░░███     ███ ░███ ░███ ░███ ░███ ░███ ░███  ░███ ░███  ░░░░███              .             .           
         ░░█████████  ░░███████ ░░███████ ████ █████ ░░████████ ██████       -----========*⠀
          ░░░░░░░░░    ░░░░░███  ░░░░░███░░░░ ░░░░░   ░░░░░░░░ ░░░░░░            .                            .
                       ███ ░███  ███ ░███                .                 .         🛸           ⠀             
         .    🛸*     ░░██████  ░░██████   .    🛸                     🛰️            -----=========*                 
                       ░░░░░░    ░░░░░░                                               🛸  ⠀
           .                            .       .             🛰️         .                          
    
        CYGNUS LP ORACLE (Balancer Composable Stable Pools) - https://cygnusdao.finance                                                          .                     .
    ═══════════════════════════════════════════════════════════════════════════════════════════════════════════ */
pragma solidity >=0.8.17;

// Dependencies
import {ICygnusNebula} from "./interfaces/ICygnusNebula.sol";

// Libraries
import {PRBMath, PRBMathUD60x18} from "./libraries/PRBMathUD60x18.sol";
import {SafeCastLib} from "./libraries/SafeCastLib.sol";

// Interfaces
import {IERC20} from "./interfaces/IERC20.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";

// Balancer
import {IVault} from "./interfaces/Balancer/IVault.sol";
import {IComposableStablePool} from "./interfaces/Balancer/IComposableStablePool.sol";

/**
 *  @title  CygnusNebula
 *  @author CygnusDAO
 *  @notice Oracle used by Cygnus that returns the price of 1 LP Token in the denomination token. In case need
 *          different implementation just update the denomination variable `denominationAggregator`
 *          and `denominationToken` with token. We used AGGREGATOR_DECIMALS as a constant for chainlink prices
 *          which are denominated in USD as all aggregators return prices in 8 decimals and saves us gas when
 *          getting the LP token price.
 *  @notice Implementation of fair lp token pricing using Chainlink price feeds
 *          https://github.com/makerdao/univ3-lp-oracle/blob/master/src/GUniLPOracle.sol
 */
contract BalancerComposableNebula is ICygnusNebula {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library PRBMathUD60x18 Library for advanced fixed-point math that works with uint256 numbers
     */
    using PRBMathUD60x18 for uint256;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Internal record of all initialized oracles
     */
    mapping(address => NebulaOracle) internal nebulaOracles;

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusNebula
     */
    address[] public override allNebulas;

    /**
     *  @inheritdoc ICygnusNebula
     */
    string public override name = "Cygnus: Balancer Composable Nebula";

    /**
     *  @inheritdoc ICygnusNebula
     */
    string public constant override version = "1.0.0";

    /**
     *  @inheritdoc ICygnusNebula
     */
    uint256 public constant override SECONDS_PER_YEAR = 31536000;

    /**
     *  @inheritdoc ICygnusNebula
     */
    uint256 public constant override AGGREGATOR_DECIMALS = 8;

    /**
     *  @inheritdoc ICygnusNebula
     */
    uint256 public constant override AGGREGATOR_SCALAR = 10 ** (18 - 8);

    /**
     *  @inheritdoc ICygnusNebula
     */
    uint256 public constant override GRACE_PERIOD = 2 hours;

    /**
     *  @inheritdoc ICygnusNebula
     */
    IERC20 public immutable override denominationToken;

    /**
     *  @inheritdoc ICygnusNebula
     */
    uint8 public immutable override decimals;

    /**
     *  @inheritdoc ICygnusNebula
     */
    AggregatorV3Interface public immutable override denominationAggregator;

    /**
     *  @inheritdoc ICygnusNebula
     */
    address public immutable override nebulaRegistry;

    // Strategy

    /**
     *  @inheritdoc ICygnusNebula
     */
    bytes4 public constant override S = IVault.manageUserBalance.selector;

    /**
     *  @notice Balancer Vault
     */
    address public constant VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Constructs a new Oracle instance.
     *  @param denomination The token address that the oracle denominates the price of the LP in. It is used to
     *         determine the decimals for the price returned by this oracle. For example, if the denomination
     *         token is USDC, the oracle will return prices with 6 decimals. If the denomination token is DAI,
     *         the oracle will return prices with 18 decimals.
     *  @param denominationPrice The price aggregator for the denomination token.
     */
    constructor(IERC20 denomination, AggregatorV3Interface denominationPrice, address _nebulaRegistry) {
        // Set the denomination token
        denominationToken = denomination;

        // Determine the number of decimals for the oracle based on the denomination token
        decimals = denomination.decimals();

        // Set the price aggregator for the denomination token
        denominationAggregator = AggregatorV3Interface(denominationPrice);

        // Registry
        nebulaRegistry = _nebulaRegistry;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. MODIFIERS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Ensure we are not in the Vault`s context when `lpTokenPriceUsd` function is called, by
     *       attempting a no-op internal balance operation. If we are already in an underlying transaction (ie a
     *       swap, join, or exit, etc), the underlying's reentrancy protection will cause the `lpTokenPriceUsd`
     *       function to revert, reverting any borrow or liquidation.
     *  @custom:modifier context Assert we are not in the underlying's context
     */
    modifier context(address contextContract) {
        // Perform the following payable call as a staticcall:
        //
        // IVault.UserBalanceOp[] memory noop = new IVault.UserBalanceOp[](0);
        // _vault.manageUserBalance(noop);
        //
        // This staticcall always reverts, but we need to make sure it doesn't fail due to a re-entrancy attack.
        (, bytes memory revertData) = contextContract.staticcall{gas: 10_000}(abi.encodeWithSelector(S, 0));
        /// @custom:error AlreadyInContext Avoid if we are already in the underlying's context
        if (revertData.length != 0) revert CygnusNebulaOracle__AlreadyInContext();
        _;
    }

    /**
     *  @custom:modifier onlyRegistry Oracles can only be initialized from the registry
     */
    modifier onlyRegistry() {
        // If msg.sender is not registry revert
        isNebulaRegistry();
        _;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Internal check for registry control only
     */
    function isNebulaRegistry() internal view {
        /// @custom:error MsgSenderNotRegistry Avoid if sender is not the registry
        if (msg.sender != nebulaRegistry) {
            revert CygnusNebulaOracle__MsgSenderNotRegistry({sender: msg.sender});
        }
    }

    /**
     *  @notice Gets the price of a chainlink aggregator
     *  @param priceFeed Chainlink aggregator price feed
     *  @return price The price of the token adjusted to 18 decimals
     */
    function getPriceInternal(AggregatorV3Interface priceFeed) internal view returns (uint256 price) {
        /// @solidity memory-safe-assembly
        assembly {
            // Store the function selector of `latestRoundData()`.
            mstore(0x0, 0xfeaf968c)
            // Get second slot from round data (`price`)
            price := mul(
                mul(
                    mload(0x20),
                    and(
                        // The arguments are evaluated from right to left
                        gt(returndatasize(), 0x1f), // At least 32 bytes returned
                        staticcall(gas(), priceFeed, 0x1c, 0x4, 0x0, 0x40) // Only get `latestPrice`
                    )
                ),
                // Adjust to 18 decimals
                AGGREGATOR_SCALAR
            )
        }
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusNebula
     */
    function getNebulaOracle(address lpTokenPair) public view override returns (NebulaOracle memory) {
        return nebulaOracles[lpTokenPair];
    }

    /**
     *  @inheritdoc ICygnusNebula
     */
    function nebulaSize() public view override returns (uint88) {
        // Return how many LP Tokens we are tracking
        return uint88(allNebulas.length);
    }

    /**
     *  @inheritdoc ICygnusNebula
     */
    function getAnnualizedBaseRate(
        uint256 exchangeRateLast,
        uint256 exchangeRateCurrent,
        uint256 timeElapsed
    ) public pure override returns (uint256) {
        // Get the natural logarithm of last exchange rate
        uint256 logRateLast = exchangeRateLast.ln();

        // Get the natural logarithm of current exchange rate
        uint256 logRateCurrent = exchangeRateCurrent.ln();

        // Get the log rate difference between the exchange rates
        uint256 logRateDiff = logRateCurrent - logRateLast;

        // The log APR is = (lorRateDif * 1 year) / time since last update
        uint256 logAprInYear = (logRateDiff * SECONDS_PER_YEAR) / timeElapsed;

        // Get the natural exponent of the log APR and substract 1
        uint256 annualizedApr = logAprInYear.exp() - 1e18;

        // Returns the annualized APR, taking into account time since last update
        return annualizedApr;
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusNebula
     */
    function denominationTokenPrice() external view override returns (uint256) {
        // Price of the denomination token in 18 decimals
        uint256 denomPrice = getPriceInternal(denominationAggregator);

        // Return in oracle decimals
        return denomPrice / (10 ** (18 - decimals));
    }

    /**
     *  @inheritdoc ICygnusNebula
     */
    function lpTokenPriceUsd(address lpTokenPair) external view override context(VAULT) returns (uint256 lpTokenPrice) {
        // 1. Load oracle to storage for gas savings since we are not doing storage writes
        NebulaOracle storage oracle = nebulaOracles[lpTokenPair];

        /// @custom:error PairNotInitialized Avoid getting price unless lpTokenPair's price is being tracked
        if (!oracle.initialized) revert CygnusNebulaOracle__PairNotInitialized(lpTokenPair);

        // 2. Get min price of assets
        uint256 minPrice = type(uint256).max;

        // Loop through each token in the LP and get the price
        for (uint256 i = 0; i < oracle.poolTokens.length; i++) {
            // Asset price in 18 decimals
            uint256 assetPrice = getPriceInternal(oracle.priceFeeds[i]);

            // Get the individual token rate of the token in the pool
            uint256 tokenRate = IComposableStablePool(lpTokenPair).getTokenRate(address(oracle.poolTokens[i]));

            // We adjust the price for each token rate. The base token always has a rate of exactly 1e18 so adjusting
            // the base asset has no effect here
            uint256 adjustedPrice = assetPrice.div(tokenRate);

            // Assign min price
            minPrice = minPrice < adjustedPrice ? minPrice : adjustedPrice;
        }

        // 3. Get the current rate via the BPT's `getRate`
        uint256 rate = IComposableStablePool(lpTokenPair).getRate();

        // 4. The price of the BPT in USD
        uint256 lpPriceUsd = minPrice.mul(rate);

        // 5. Get the price of the denom token (in our case USDC)
        uint256 denomPrice = getPriceInternal(denominationAggregator);

        // Return the price of the BPT Token expressed in the denomination token
        lpTokenPrice = lpPriceUsd.div(denomPrice * 10 ** (18 - decimals));
    }

    /**
     *  @inheritdoc ICygnusNebula
     */
    function lpTokenInfo(
        address lpTokenPair
    )
        external
        view
        override
        returns (
            IERC20[] memory tokens,
            uint256[] memory prices,
            uint256[] memory reserves,
            uint256[] memory tokenDecimals,
            uint256[] memory reservesUsd
        )
    {
        // Load to storage for gas savings
        NebulaOracle storage nebulaOracle = nebulaOracles[lpTokenPair];

        /// @custom:error PairNotInitialized Avoid getting price unless lpTokenPair's price is being tracked
        if (!nebulaOracle.initialized) {
            revert CygnusNebulaOracle__PairNotInitialized({lpTokenPair: lpTokenPair});
        }

        // tokens
        tokens = nebulaOracle.poolTokens;

        // Decimals
        tokenDecimals = nebulaOracle.poolTokensDecimals;

        // Prices, reserves and tvl in USD
        prices = new uint256[](nebulaOracle.poolTokens.length);
        reserves = new uint256[](nebulaOracle.poolTokens.length);
        reservesUsd = new uint256[](nebulaOracle.poolTokens.length);

        // Pool ID
        bytes32 poolId = IComposableStablePool(lpTokenPair).getPoolId();

        // Price of denom token
        uint256 denomPrice = getPriceInternal(denominationAggregator);

        // Loop through each token
        for (uint256 i = 0; i < nebulaOracle.poolTokens.length; i++) {
            // Get the price from chainlink from cached price feeds
            uint256 assetPrice = getPriceInternal(nebulaOracle.priceFeeds[i]);

            // Get the reserves of the token, do this to ignore the pre-minted BPT
            (reserves[i], , , ) = IVault(VAULT).getPoolTokenInfo(poolId, nebulaOracle.poolTokens[i]);

            // Express asset price in denom token
            prices[i] = assetPrice.div(denomPrice * 10 ** (18 - decimals));

            // Reserves
            reservesUsd[i] = ((prices[i] * 10 ** (18 - decimals)) * reserves[i]) / (10 ** nebulaOracle.poolTokensDecimals[i]);
        }
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusNebula
     *  @custom:security only-registry
     */
    function initializeNebulaOracle(address lpTokenPair, AggregatorV3Interface[] calldata aggregators) external override onlyRegistry {
        // Load the CygnusNebula instance for the LP Token pair into storage
        NebulaOracle storage nebulaOracle = nebulaOracles[lpTokenPair];

        // If the LP Token pair is already being tracked by an oracle and we are past grace period revert
        // We allow to modify oracle if the oracle has been created and we are within the grace period, constant of 1 hour.
        // We do this since chainlink only has registry on mainnet and we have to manually include aggregators, avoid human error
        if (nebulaOracle.initialized) {
            // Current timestamp
            uint256 currentTime = block.timestamp;

            // Time elapsed since we created
            uint256 timeElapsed = currentTime - nebulaOracle.createdAt;

            /// @custom:error PairAlreadyInitialized Avoid updating the oracle if it has already been initialized and we past grace period
            if (timeElapsed > GRACE_PERIOD) revert CygnusNebulaOracle__PairAlreadyInitialized({lpTokenPair: lpTokenPair});
        }
        // Not initialized, we initialize for the first time
        else {
            // Set the status of the new oracle to initialized
            nebulaOracle.initialized = true;

            // Assign an ID to the new oracle
            nebulaOracle.oracleId = nebulaSize();

            // Mark creation timestamp
            nebulaOracle.createdAt = block.timestamp;

            // Add the LP Token pair to the list of all tracked LP Token pairs
            allNebulas.push(lpTokenPair);
        }

        // Create a memory array of tokens with the same length as the number of price aggregators
        IERC20[] memory poolTokens = new IERC20[](aggregators.length);

        // Create a memory array for the decimals of each token
        uint256[] memory tokenDecimals = new uint256[](aggregators.length);

        // Create a memory array for the decimals of each price feed
        uint256[] memory priceDecimals = new uint256[](aggregators.length);

        // Pool ID
        bytes32 poolId = IComposableStablePool(lpTokenPair).getPoolId();

        // Get pool tokens
        (IERC20[] memory _poolTokens, , ) = IVault(VAULT).getPoolTokens(poolId);

        // Need to do this since the poolTokens from the bpt includes the pre-minted BPT
        uint256 tokenIndex = 0;

        // Loop through each token and exclude the pre-minted BPT
        for (uint256 i = 0; i < _poolTokens.length; i++) {
            // If the poolToken is different than the BPT
            if (_poolTokens[i] != IERC20(lpTokenPair)) {
                // Assign  the pool token to our array at the created index
                poolTokens[tokenIndex] = _poolTokens[i];

                // Increase created index
                tokenIndex++;
            }
        }

        // Loop through each one
        for (uint256 i = 0; i < aggregators.length; i++) {
            // Get the decimals for token `i`
            tokenDecimals[i] = poolTokens[i].decimals();

            // Chainlink price feed decimals
            priceDecimals[i] = aggregators[i].decimals();
        }

        // Assign an ID to the new oracle
        nebulaOracle.oracleId = nebulaSize();

        // Set the user-friendly name of the new oracle to the name of the LP Token pair
        nebulaOracle.name = IERC20(lpTokenPair).name();

        // Store the address of the LP Token pair
        nebulaOracle.underlying = lpTokenPair;

        // Store the addresses of the tokens in the LP Token pair
        nebulaOracle.poolTokens = poolTokens;

        // Store the number of decimals for each token in the LP Token pair
        nebulaOracle.poolTokensDecimals = tokenDecimals;

        // Store the price aggregator interfaces for the tokens in the LP Token pair
        nebulaOracle.priceFeeds = aggregators;

        // Store the decimals for each aggregator
        nebulaOracle.priceFeedsDecimals = priceDecimals;

        // Set the status of the new oracle to initialized
        nebulaOracle.initialized = true;

        // Add the LP Token pair to the list of all tracked LP Token pairs
        allNebulas.push(lpTokenPair);

        /// @custom:event InitializeNebulaOracle
        emit InitializeNebulaOracle(true, nebulaOracle.oracleId, lpTokenPair, poolTokens, tokenDecimals, aggregators, priceDecimals);
    }
}
