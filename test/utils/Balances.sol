// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {TestERC20} from "./TestERC20.sol";

struct BalanceMap {
    string identifier;
}

using BalanceMapper for BalanceMap global;

library BalanceMapper {
    function init(
        string memory _identifier
    ) internal pure returns (BalanceMap memory map) {
        return BalanceMap({identifier: _identifier});
    }

    function computeSlot(
        string memory identifier,
        IERC20 token
    ) internal pure returns (bytes32) {
        // Use identifier to avoid slot collisions between other maps
        return keccak256(abi.encodePacked(identifier, token));
    }

    function add(BalanceMap memory map, IERC20 token, uint amount) internal {
        bytes32 slot = computeSlot(map.identifier, token);

        assembly {
            let currentBalance := tload(slot)
            tstore(slot, add(currentBalance, amount))
        }
    }

    function get(
        BalanceMap memory map,
        IERC20 token
    ) internal view returns (uint amount) {
        bytes32 slot = computeSlot(map.identifier, token);

        assembly {
            amount := tload(slot)
        }
    }
}

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
