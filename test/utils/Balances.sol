// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {TestERC20} from "./TestERC20.sol";

library Balances {
    function getAccountBalances(
        address account,
        TestERC20[] memory tokens
    ) public view returns (uint[] memory tokenBalances) {
        tokenBalances = new uint[](tokens.length);

        for (uint i; i < tokens.length; ++i) {
            tokenBalances[i] = tokens[i].balanceOf(account);
        }
    }
}
