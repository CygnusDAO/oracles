// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.17;

/**
 *  @notice Balancer V2 Composable Stable Pools
 */
interface IComposableStablePool {
  function getPoolId() external view returns (bytes32);
  function getActualSupply() external view returns (uint256);
  function getTokenRate(address token) external view returns (uint256);
  function getRate() external view returns (uint256);
  function getLastJoinExitData() external view returns (uint256, uint256);
}
