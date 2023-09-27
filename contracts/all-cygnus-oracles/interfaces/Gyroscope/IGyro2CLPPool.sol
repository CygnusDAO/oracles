// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.17;

/// @title Gyroscope 2CPL
interface IGyro2CLPPool {
    /// @dev Balancer Pool ID
    function getPoolId() external view returns (bytes32);

    /// @dev Total supply of BPT
    function totalSupply() external view returns (uint256);

    /// @dev Last pool invariant
    function getLastInvariant() external view returns (uint256);

    /// @dev Returns sqrtAlpha and sqrtBeta (square roots of lower and upper price bounds of p_x respectively)
    function getSqrtParameters() external view returns (uint256[2] memory);
}
