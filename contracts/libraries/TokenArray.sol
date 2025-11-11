// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library TokenArray {
    error ArrayMustBeSortedAndUnique();

    // TODO test with arrays of length 0, 1, and more
    function validateUniqueAndSorted(IERC20[] memory _tokens) internal pure {
        IERC20 previousToken = _tokens[0];

        // TODO gasopt:
        // opt 1: starting from position 1 and not having to check for i > 0, having a second loop to get balances
        // opt 2: starting from position 0 and checking for i > 0, get balances in same loop
        for (uint i = 1; i < _tokens.length; ++i) {
            IERC20 token = _tokens[i];

            if (token <= previousToken)
                revert ArrayMustBeSortedAndUnique();

            previousToken = token;
        }
    }
}