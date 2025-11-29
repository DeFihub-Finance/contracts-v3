// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {SafeCast as _SafeCast} from "@uniswap/v3-core/contracts/libraries/SafeCast.sol";

/// @title Safe casting with extended methods
/// @notice Contains methods for safely casting between types
library SafeCast {
    /// @notice Cast a int256 to a uint128, revert on overflow
    /// @param y The int256 to be downcasted
    /// @return z The downcasted integer, now type uint128
    function toUint128(int256 y) internal pure returns (uint128 z) {
        int128 x = _SafeCast.toInt128(y);

        require(x >= 0);
        z = uint128(x);
    }

    function toUint160(uint256 y) internal pure returns (uint160 z) {
        return _SafeCast.toUint160(y);
    }

    function toInt128(int256 y) internal pure returns (int128 z) {
        return _SafeCast.toInt128(y);
    }

    function toInt256(uint256 y) internal pure returns (int256 z) {
        return _SafeCast.toInt256(y);
    }
}
