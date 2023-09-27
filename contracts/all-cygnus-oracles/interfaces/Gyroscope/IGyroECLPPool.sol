// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.17;

/// @title Gyroscope ECLPPool
interface IGyroECLPPool {
    // Note that all t values (not tp or tpp) could consist of uint's, as could all Params. But it's complicated to
    // convert all the time, so we make them all signed. We also store all intermediate values signed. An exception are
    // the functions that are used by the contract b/c there the values are stored unsigned.
    struct Params {
        // Price bounds (lower and upper). 0 < alpha < beta
        int256 alpha;
        int256 beta;
        // phi in (-90 degrees, 0] is the implicit rotation vector. It's stored as a point:
        int256 c; // c = cos(-phi) >= 0. rounded to 18 decimals
        int256 s; //  s = sin(-phi) >= 0. rounded to 18 decimals
        // Stretching factor:
        int256 lambda; // lambda >= 1 where lambda == 1 is the circle.
    }

    // terms in this struct are stored in extra precision (38 decimals) with final decimal rounded down
    struct DerivedParams {
        Vector2 tauAlpha;
        Vector2 tauBeta;
        int256 u; // from (A chi)_y = lambda * u + v
        int256 v; // from (A chi)_y = lambda * u + v
        int256 w; // from (A chi)_x = w / lambda + z
        int256 z; // from (A chi)_x = w / lambda + z
        int256 dSq; // error in c^2 + s^2 = dSq, used to correct errors in c, s, tau, u,v,w,z calculations
    }

    struct Vector2 {
        int256 x;
        int256 y;
    }

    /// @dev Balancer Pool ID
    function getPoolId() external view returns (bytes32);

    /// @dev Total supply of BPT
    function totalSupply() external view returns (uint256);

    /// @dev Last pool invariant
    function getLastInvariant() external view returns (uint256);

    /// @dev Get the Params and DerivedParams for this pool
    function getECLPParams() external view returns (Params memory params, DerivedParams memory d);
}
