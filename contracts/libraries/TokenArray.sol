// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library TokenArray {
    error ArrayMustBeSortedAndUnique();

    // TODO test with arrays of length 0, 1, and more
    function validateUniqueAndSorted(IERC20[] memory _tokens) internal pure {
        if (_tokens.length < 2)
            return;

        IERC20 previousToken = _tokens[0];

        for (uint i = 1; i < _tokens.length; ++i) {
            IERC20 token = _tokens[i];

            if (token <= previousToken)
                revert ArrayMustBeSortedAndUnique();

            previousToken = token;
        }
    }
}
