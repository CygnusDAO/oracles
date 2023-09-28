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
    
        CYGNUS LP ORACLE (Hypervisor Gamma LP) - https://cygnusdao.finance                                                          .                     .
    ═══════════════════════════════════════════════════════════════════════════════════════════════════════════ */
pragma solidity >=0.8.17;

// Dependencies
import {ICygnusNebula} from "./interfaces/ICygnusNebula.sol";

// Libraries
import {TickMath} from "./libraries/Gamma/TickMath.sol";
import {LiquidityAmounts} from "./libraries/Gamma/LiquidityAmounts.sol";
import {PRBMath, PRBMathUD60x18} from "./libraries/PRBMathUD60x18.sol";
import {SafeCastLib} from "./libraries/SafeCastLib.sol";

// Interfaces
import {IERC20} from "./interfaces/IERC20.sol";
import {IHypervisor} from "./interfaces/Gamma/IHypervisor.sol";
import {IUniswapV3Pool} from "./interfaces/Gamma/IUniswapV3Pool.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";

/**
 *  @title  CygnusNebula
 *  @author CygnusDAO
 *  @notice Oracle used by Cygnus that returns the price of 1 LP Token in the denomination token. In case need
 *          different implementation just update the denomination variable `denominationAggregator`
 *          and `denominationToken` with token. We used AGGREGATOR_DECIMALS as a constant for chainlink prices
 *          which are denominated in USD as all aggregators return prices in 8 decimals and saves us gas when
 *          getting the LP token price.
 *  @notice Implementation of fair lp token pricing using Chainlink price feeds for UniswapV3 Pools
 *          https://github.com/makerdao/univ3-lp-oracle/blob/master/src/GUniLPOracle.sol
 */
contract CygnusNebula is ICygnusNebula {
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
    string public override name = "Cygnus: Hypervisor Nebula";

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
    bytes4 public constant override S = IHypervisor.deposit.selector;

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
     *  @dev Ensure we are not in the Liquidity Token`s context when `lpTokenPriceUsd` function is called, by
     *       attempting a no-op internal balance operation. If we are already in an underlying transaction (ie a
     *       swap, join, or exit, etc), the underlying's reentrancy protection will cause the `lpTokenPriceUsd`
     *       function to revert, reverting any borrow or liquidation.
     *  @custom:modifier context Assert we are not in the underlying's context
     */
    modifier context(address lpTokenPair) {
        // Perform the following payable call as a staticcall:
        //
        // IHypervisor.deposit(uint, uint, address, address, uint[4])
        //
        // This staticcall always reverts, but we need to make sure it doesn't fail due to a re-entrancy attack.
        (, bytes memory revertData) = lpTokenPair.staticcall{gas: 10_000}(
            abi.encodeWithSelector(S, 0, 0, address(0), address(0), [uint256(0), 0, 0, 0])
        );
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

    /**
     *  @notice The decimals are always normalized to 18
     *  @notice returns the sqrt price given 2 asset prices.
     *  @notice sqrtPriceX96 = sqrt((p0 * 10^UNITS_1 * 2^96) / (p1 * 10^UNITS_0)) * 2^48
     */
    function getSqrtPriceX96Internal(uint256 priceA, uint256 decimalsA, uint256 priceB, uint256 decimalsB) internal pure returns (uint160) {
        // Return price given assets and decimals
        return SafeCastLib.toUint160(PRBMath.sqrt((priceA * (10 ** decimalsB) * (1 << 96)) / (priceB * (10 ** decimalsA))) << 48);
    }

    /**
     *  @notice Get the amounts of the given numbers of liquidity tokens
     *  @param tickLower The lower tick of the position
     *  @param tickUpper The upper tick of the position
     *  @param liquidity The amount of liquidity tokens
     *  @return Amount of token0 and token1
     */
    function getAmountsForLiquidity(
        uint160 sqrtRatioX96,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) internal pure returns (uint256, uint256) {
        return
            LiquidityAmounts.getAmountsForLiquidity(
                sqrtRatioX96,
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                liquidity
            );
    }

    /**
     *  @notice Get the info of the given position
     *  @param lpTokenPair The address of the Gamma Vault
     *  @param tickLower The lower tick of the position
     *  @param tickUpper The upper tick of the position
     *  @param pool The address of the UniswapV3 Pool for the Gamma Vault
     *  @return liquidity The amount of liquidity of the position
     *  @return tokensOwed0 Amount of token0 owed
     *  @return tokensOwed1 Amount of token1 owed
     */
    function uniswapV3Position(
        address lpTokenPair,
        int24 tickLower,
        int24 tickUpper,
        address pool
    ) internal view returns (uint128 liquidity, uint128 tokensOwed0, uint128 tokensOwed1) {
        bytes32 positionKey = keccak256(abi.encodePacked(lpTokenPair, tickLower, tickUpper));
        (liquidity, , , tokensOwed0, tokensOwed1) = IUniswapV3Pool(pool).positions(positionKey);
    }

    /**
     *  @notice Get the base position from the Gamma Vault with our sqrtPrice
     *  @param lpTokenPair The hypervisor contract address
     *  @param sqrtPriceX96 The square root price calculated using Chainlink oracles
     *  @return liquidity The amount of liquidity of the position
     *  @return amount0 Amount of token0 owed
     *  @return amount1 Amount of token1 owed
     */
    function getLimitPositionInternal(
        address lpTokenPair,
        uint160 sqrtPriceX96,
        address uniswapV3Pool
    ) internal view returns (uint256 liquidity, uint256 amount0, uint256 amount1) {
        // Limit lower tick
        int24 limitLower = IHypervisor(lpTokenPair).limitLower();

        // Limit upper tick
        int24 limitUpper = IHypervisor(lpTokenPair).limitUpper();

        // Get the position given the ranges
        (uint128 positionLiquidity, uint128 tokensOwed0, uint128 tokensOwed1) = uniswapV3Position(
            lpTokenPair,
            limitLower,
            limitUpper,
            uniswapV3Pool
        );

        // Compute amounts for liquidity based on our sqrtPrice
        (amount0, amount1) = getAmountsForLiquidity(sqrtPriceX96, limitLower, limitUpper, positionLiquidity);

        // Amount of token0 in limit position
        amount0 += tokensOwed0;

        // Amount of token1 in limit position
        amount1 += tokensOwed1;

        // Liquidity in limit position
        liquidity = positionLiquidity;
    }

    /**
     *  @notice Get the base position from the Gamma Vault with our sqrtPrice
     *  @param lpTokenPair The Hypervisor contract
     *  @param sqrtPriceX96 The square root price calculated using Chainlink oracles
     *  @return liquidity The amount of liquidity of the position
     *  @return amount0 Amount of token0 owed
     *  @return amount1 Amount of token1 owed
     */
    function getBasePositionInternal(
        address lpTokenPair,
        uint160 sqrtPriceX96,
        address uniswapV3Pool
    ) internal view returns (uint256 liquidity, uint256 amount0, uint256 amount1) {
        // Limit lower tick
        int24 baseLower = IHypervisor(lpTokenPair).baseLower();

        // Limit upper tick
        int24 baseUpper = IHypervisor(lpTokenPair).baseUpper();

        // Get the position given the ranges
        (uint128 positionLiquidity, uint128 tokensOwed0, uint128 tokensOwed1) = uniswapV3Position(
            lpTokenPair,
            baseLower,
            baseUpper,
            uniswapV3Pool
        );

        // Compute amounts for liquidity based on our sqrtPrice
        (amount0, amount1) = getAmountsForLiquidity(sqrtPriceX96, baseLower, baseUpper, positionLiquidity);

        // Amount of token0
        amount0 += tokensOwed0;

        // Amount of token1
        amount1 += tokensOwed1;

        // Liquidity tokens
        liquidity = positionLiquidity;
    }

    /**
     *  @notice Get total amounts given a stored pair and a price
     *  @param lpTokenPair The hypervisor contract address
     *  @param sqrtPriceX96 The pre-computed sqrtPriceX96
     *  @return total0 The total amount of token0 in the position
     *  @return total1 The total amount of token1 in the position
     */
    function getTotalAmountsInternal(address lpTokenPair, uint160 sqrtPriceX96) internal view returns (uint256 total0, uint256 total1) {
        // UniswapV3 pool
        address uniswapV3Pool = IHypervisor(lpTokenPair).pool();

        // Get base position
        (, uint256 base0, uint256 base1) = getBasePositionInternal(lpTokenPair, sqrtPriceX96, uniswapV3Pool);

        // Get limit position
        (, uint256 limit0, uint256 limit1) = getLimitPositionInternal(lpTokenPair, sqrtPriceX96, uniswapV3Pool);

        // Cannot realistically overflow
        // Total0 = base0 + limit0 + hypervisors balance of token0
        total0 = nebulaOracles[lpTokenPair].poolTokens[0].balanceOf(lpTokenPair) + base0 + limit0;

        // Total1 = base1 + limit1 + hypervisors balance of token1
        total1 = nebulaOracles[lpTokenPair].poolTokens[1].balanceOf(lpTokenPair) + base1 + limit1;
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
    function lpTokenPriceUsd(address lpTokenPair) external view override context(lpTokenPair) returns (uint256 lpTokenPrice) {
        // Load to storage for gas savings
        NebulaOracle storage oracle = nebulaOracles[lpTokenPair];

        /// custom:error PairNotInitialized Avoid getting price unless lpTokenPair is initialized
        if (!oracle.initialized) {
            revert CygnusNebulaOracle__PairNotInitialized(lpTokenPair);
        }

        // 1. Get token prices from chainlink and token decimals
        // Price token0 to 18 decimals
        uint256 price0 = getPriceInternal(oracle.priceFeeds[0]);

        // Price token1 to 18 decimals
        uint256 price1 = getPriceInternal(oracle.priceFeeds[1]);

        // Gas savings
        // Decimals token0
        uint256 decimals0 = oracle.poolTokensDecimals[0];

        // Decimals token1
        uint256 decimals1 = oracle.poolTokensDecimals[1];

        // 2. Get the sqrtPrice given asset prices and decimal of assets
        // sqrtPriceX96 = sqrt((p0 * 10^UNITS_1 * 2^96) / (p1 * 10^UNITS_0)) * 2^48
        uint160 sqrtPriceX96 = getSqrtPriceX96Internal(price0, decimals0, price1, decimals1);

        // 3. Get the fair reserves of token0 and token1 given our sqrtPricex96
        (uint256 reserves0, uint256 reserves1) = getTotalAmountsInternal(lpTokenPair, sqrtPriceX96);

        // The value in USD of token0 in the pool
        uint256 value0 = (price0 * reserves0) / (10 ** decimals0);

        // The value in USD of token1 in the pool
        uint256 value1 = (price1 * reserves1) / (10 ** decimals1);

        // 4. Get the total Supply of LP
        uint256 totalSupply = IHypervisor(lpTokenPair).totalSupply();

        // 5. Token Price = TVL / Token Supply = (r0 * p0 + r1 * p1) / totalSupply
        uint256 lpPriceUsd = (value0 + value1).div(totalSupply);

        // Get the price of the denomination token
        uint256 denomPrice = getPriceInternal(denominationAggregator);

        // 6. Return the price of the LP Token expressed in the denomination token
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

        // Reserves
        (reserves[0], reserves[1]) = IHypervisor(lpTokenPair).getTotalAmounts();

        // Price of denom token
        uint256 denomPrice = getPriceInternal(denominationAggregator);

        // Loop through each token
        for (uint256 i = 0; i < nebulaOracle.poolTokens.length; i++) {
            // Get the price from chainlink from cached price feeds
            uint256 assetPrice = getPriceInternal(nebulaOracle.priceFeeds[i]);

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

        // Get the first token in the LP Token pair and add it to the poolTokens array
        poolTokens[0] = IERC20(IHypervisor(lpTokenPair).token0());

        // Get the second token in the LP Token pair and add it to the poolTokens array
        poolTokens[1] = IERC20(IHypervisor(lpTokenPair).token1());

        // Loop through each one
        for (uint256 i = 0; i < aggregators.length; i++) {
            // Get the decimals for token `i`
            tokenDecimals[i] = poolTokens[i].decimals();

            // Chainlink price feed decimals
            priceDecimals[i] = aggregators[i].decimals();
        }

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

        /// @custom:event InitializeCygnusNebula
        emit InitializeNebulaOracle(true, nebulaOracle.oracleId, lpTokenPair, poolTokens, tokenDecimals, aggregators, priceDecimals);
    }
}
