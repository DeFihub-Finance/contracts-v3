// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import "forge-std/Test.sol";

import {Balances} from "../utils/Balances.sol";
import {BuyModuleTestHelpers} from "./BuyModuleTestHelpers.sol";
import {BuyPositionModule} from "../../contracts/modules/BuyPositionModule.sol";
import {BasePositionModule} from "../../contracts/abstract/BasePositionModule.sol";

contract CollectPosition is Test, BuyModuleTestHelpers {
    function setUp() public {
        deployBaseContracts();
    }

    function test_fuzz_collectPosition(uint[] memory allocatedAmounts) public {
        uint tokenId = _createFuzzyBuyPosition(usdt, allocatedAmounts);

        uint[] memory userBalancesBefore = Balances.getAccountBalances(account0, availableTokens);
        uint[] memory buyModuleBalancesBefore = Balances.getAccountBalances(address(buyPositionModule), availableTokens);

        vm.startPrank(account0);

        _expectEmitBuyPositionClosedEvent(account0, account0, tokenId);
        buyPositionModule.collectPosition(account0, tokenId, new bytes(0));

        vm.stopPrank();

        uint[] memory userBalancesAfter = Balances.getAccountBalances(account0, availableTokens);

        for (uint i; i < availableTokens.length; ++i) {
            // Assert user received tokens
            assertEq(
                userBalancesAfter[i] - userBalancesBefore[i],
                buyModuleBalancesBefore[i]
            );
        }
    }

    function test_collectPosition_reverts_notOwner() public {
        uint tokenId = _createBuyPosition(0, usdt, new BuyPositionModule.Investment[](0));

        tokenId += 1; // Ensure tokenId is not owned by account0

        vm.startPrank(account0);

        vm.expectRevert(BasePositionModule.Unauthorized.selector);
        buyPositionModule.collectPosition(account0, tokenId, new bytes(0));
    }
}
