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
    
        CYGNUS LP ORACLE (Gyroscope Constant Ellipse Oracle) - https://cygnusdao.finance                                                          .                     .
    ═══════════════════════════════════════════════════════════════════════════════════════════════════════════ */
pragma solidity >=0.8.17;

// Dependencies
import {ICygnusNebula} from "./interfaces/ICygnusNebula.sol";

// Libraries
import {PRBMath, PRBMathUD60x18} from "./libraries/PRBMathUD60x18.sol";
import {PRBMathSD59x18} from "./libraries/PRBMathSD59x18.sol";
import {SafeCastLib} from "./libraries/SafeCastLib.sol";

// Interfaces
import {IERC20} from "./interfaces/IERC20.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";

// Balancer
import {IVault} from "./interfaces/Balancer/IVault.sol";
import {IGyroECLPPool} from "./interfaces/Gyroscope/IGyroECLPPool.sol";

/**
 *  @title  CygnusNebula
 *  @author CygnusDAO
 *  @notice Oracle used by Cygnus that returns the price of 1 LP Token in the denomination token. In case need
 *          different implementation just update the denomination variable `denominationAggregator`
 *          and `denominationToken` with token. We used AGGREGATOR_DECIMALS as a constant for chainlink prices
 *          which are denominated in USD as all aggregators return prices in 8 decimals and saves us gas when
 *          getting the LP token price.
 *
 *              When p_x/p_y < alpha: bptPrice = L/S * p_x ( e_x A^{-1} tau(beta) - e_x A^{-1} tau(alpha))
 *              When p_x/p_y > beta:  bptPrice = L/S * p_y (e_y A^{-1} tau(alpha) - e_y A^{-1} tau(beta))
 *              When alpha < p_x/p_y < beta:
 *                             L   / / e_x A^{-1} tau(beta) \     -1     / p_x \  \   / p_x \
 *                bptPrice =  --- | |                        | - A^  tau|  ---- |  | |       |
 *                             S   \ \ e_y A^{-1} tau(alpha) /           \ p_y  /  /  \ p_y  /
 *
 *  @notice Fair BPT pricing implementation of BalancerECLPPriceOracle:
 *          https://polygonscan.com/address/0xD622086d17A60563550F302E95515503652dc2C5
 */
contract GyroECLPNebula is ICygnusNebula {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library PRBMathUD60x18 Library for advanced fixed-point math that works with uint256 numbers
     */
    using PRBMathUD60x18 for uint256;

    /**
     *  @custom:library PRBMathSD59x18 Library for advanced fixed-point math that works with int256 numbers
     */
    using PRBMathSD59x18 for int256;

    /**
     *  @custom:library SafeCastLib Library for safe integer casting
     */
    using SafeCastLib for uint256;

    /**
     *  @custom:library SafeCastLib Library for safe integer casting
     */
    using SafeCastLib for int256;

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
    string public override name = "Cygnus: Gyroscope ECLP Nebula";

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
     *  @dev Ensure we are not in the Liquidity Token`s context when `lpTokenPriceUsd` function is called, by
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

    /** 
     *  @dev Calculate A^{-1}t. This is rotating and scaling the circle into the ellipse
     */
    function mulAinv(
        IGyroECLPPool.Params memory params,
        IGyroECLPPool.Vector2 memory t
    ) internal pure returns (IGyroECLPPool.Vector2 memory tp) {
        tp.x = t.x.mul(params.lambda).mul(params.c) + t.y.mul(params.s);
        tp.y = -t.x.mul(params.lambda).mul(params.s) + t.y.mul(params.c);
    }

    /** 
     *  @dev Calculates eta in more efficient way if the square root is known and input as second arg
     */
    function eta(int256 pxc, int256 z) internal pure returns (IGyroECLPPool.Vector2 memory tpp) {
        tpp.x = pxc.div(z);
        tpp.y = int256(1e18).div(z);
    }

    /** 
     *  @dev Given price on a circle, gives the normalized corresponding point on the circle centered at the origin
     *       pxc = price of asset x in terms of asset y (measured on the circle)
     *  @notice The function does not depend on Params
     */
    function eta(int256 pxc) internal pure returns (IGyroECLPPool.Vector2 memory tpp) {
        int256 z = (1e18 + (pxc.mul(pxc).toUint256())).sqrt().toInt256();
        tpp = eta(pxc, z);
    }

    /** 
     *  @dev Calculate A t where A is given in Section 2.2
     *  @notice This is reversing rotation and scaling of the ellipse (mapping back to circle) 
     */
    function mulA(
        IGyroECLPPool.Params memory params,
        IGyroECLPPool.Vector2 memory tp
    ) internal pure returns (IGyroECLPPool.Vector2 memory t) {
        t.x = params.c.mul(tp.x).div(params.lambda) - params.s.mul(tp.y).div(params.lambda);
        t.y = params.s.mul(tp.x) + params.c.mul(tp.y);
    }

    /** 
     *  @dev Given price px on the transformed ellipse, get the untransformed price pxc on the circle
     *       px = price of asset x in terms of asset y 
     */
    function zeta(IGyroECLPPool.Params memory params, int256 px) internal pure returns (int256 pxc) {
        IGyroECLPPool.Vector2 memory nd = mulA(params, IGyroECLPPool.Vector2(-int256(1e18), px));
        pxc = -nd.y.div(nd.x);
    }

    /** 
     *  @dev Given price px on the transformed ellipse, maps to the corresponding point on the untransformed normalized circle
     *  px = price of asset x in terms of asset y
     */
    function tau(IGyroECLPPool.Params memory params, int256 px) internal pure returns (IGyroECLPPool.Vector2 memory tpp) {
        tpp = eta(zeta(params, px));
    }

    /**
     *  @dev Scalar product of IECLP.Vector2 objects
     */
    function scalarProdDown(IGyroECLPPool.Vector2 memory t1, IGyroECLPPool.Vector2 memory t2) internal pure returns (int256 ret) {
        ret = t1.x.mul(t2.x) + t1.y.mul(t2.y);
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
        // Load to storage for gas savings
        NebulaOracle storage oracle = nebulaOracles[lpTokenPair];

        /// @custom:error PairNotInitialized Avoid getting price unless lpTokenPair's price is being tracked
        if (!oracle.initialized) revert CygnusNebulaOracle__PairNotInitialized(lpTokenPair);

        // Price of token0
        int256 priceToken0 = getPriceInternal(oracle.priceFeeds[0]).toInt256();

        // Price of token1
        int256 priceToken1 = getPriceInternal(oracle.priceFeeds[1]).toInt256();

        // Get pool params
        (IGyroECLPPool.Params memory params, IGyroECLPPool.DerivedParams memory derivedParams) = IGyroECLPPool(lpTokenPair).getECLPParams();

        // Latest pool invariant / BPT supply
        uint256 invariantDivSupply = IGyroECLPPool(lpTokenPair).getLastInvariant().div(IGyroECLPPool(lpTokenPair).totalSupply());

        // P0 / P1
        int256 pxIny = priceToken0.div(priceToken1);

        uint256 lpPrice;

        // Case 0: px/py < alpha
        if (pxIny < params.alpha) {
            // Calculate A^{-1}t
            int256 bP = mulAinv(params, derivedParams.tauBeta).x - mulAinv(params, derivedParams.tauAlpha).x;

            // bP * p0 * invariantDivSupply
            lpPrice = (bP.mul(priceToken0)).toUint256().mul(invariantDivSupply);
        }
        // Case 1: px/py > beta
        else if (pxIny > params.beta) {
            // Calculate A^{-1}t
            int256 bP = mulAinv(params, derivedParams.tauAlpha).y - mulAinv(params, derivedParams.tauBeta).y;

            // bP * p1 * invariantDivSupply
            lpPrice = (bP.mul(priceToken1)).toUint256().mul(invariantDivSupply);
        }
        // Case 2: alpha < px/py < beta
        else {
            // Get int vector params
            IGyroECLPPool.Vector2 memory vector = mulAinv(params, tau(params, pxIny));
            vector.x = mulAinv(params, derivedParams.tauBeta).x - vector.x;
            vector.y = mulAinv(params, derivedParams.tauAlpha).y - vector.y;

            // t1.x * t2.x + t1.y. * t2.y
            lpPrice = scalarProdDown(IGyroECLPPool.Vector2(priceToken0, priceToken1), vector).toUint256().mul(invariantDivSupply);
        }

        // Adjust to 18 decimals
        lpPrice /= 1e20;

        // Get the price of the denomination token
        uint256 denomPrice = getPriceInternal(denominationAggregator);

        // BPT Price in denom token (USDC) and adjust to denom token `decimals`
        lpTokenPrice = lpPrice.div(denomPrice * 10 ** (18 - decimals));
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
        bytes32 poolId = IGyroECLPPool(lpTokenPair).getPoolId();

        // Reserves
        (, reserves, ) = IVault(VAULT).getPoolTokens(poolId);

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

        // Pool ID
        bytes32 poolId = IGyroECLPPool(lpTokenPair).getPoolId();

        // Get pool tokens
        (poolTokens, , ) = IVault(VAULT).getPoolTokens(poolId);

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

        // Set the status of the new oracle to initialized
        nebulaOracle.initialized = true;

        // Add the LP Token pair to the list of all tracked LP Token pairs
        allNebulas.push(lpTokenPair);

        /// @custom:event InitializeNebulaOracle
        emit InitializeNebulaOracle(true, nebulaOracle.oracleId, lpTokenPair, poolTokens, tokenDecimals, aggregators, priceDecimals);
    }
}
