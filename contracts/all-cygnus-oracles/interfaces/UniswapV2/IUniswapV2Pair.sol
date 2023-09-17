// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.17;

interface IUniswapV2Pair {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function totalSupply() external view returns (uint256);

    function mint(address to) external returns (uint liquidity);

    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}
