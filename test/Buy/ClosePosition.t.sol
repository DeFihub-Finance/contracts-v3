// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import "forge-std/Test.sol";

import {Balances, BalanceMap} from "../utils/Balances.sol";
import {BuyHelpers} from "./BuyHelpers.t.sol";
import {Buy} from "../../contracts/products/Buy.sol";
import {UsePosition} from "../../contracts/abstract/UsePosition.sol";

contract ClosePosition is Test, BuyHelpers {
    function setUp() public {
        deployBaseContracts();
    }

    function test_fuzz_closePosition(uint[] memory allocatedAmounts) public {
        uint tokenId = _createFuzzyBuyPosition(usdc, allocatedAmounts);

        BalanceMap memory buyAmountsByToken = _getPositionAmountsByToken(tokenId);
        uint[] memory userBalancesBefore = Balances.getAccountBalances(account0, availableTokens);
        uint[] memory buyModuleBalancesBefore = Balances.getAccountBalances(address(buy), availableTokens);

        vm.startPrank(account0);

        // We dont care about topics 1, 2 and 3, only the data
        vm.expectEmit(false, false, false, true, address(buy));
        emit Buy.PositionClosed(
            account0,
            account0,
            tokenId,
            _getBuyWithdrawalAmounts(tokenId)
        );

        buy.closePosition(account0, tokenId, new bytes(0));

        vm.stopPrank();

        uint[] memory userBalancesAfter = Balances.getAccountBalances(account0, availableTokens);
        uint[] memory buyModuleBalancesAfter = Balances.getAccountBalances(address(buy), availableTokens);

        for (uint i; i < availableTokens.length; ++i) {
            uint userBalanceDelta = userBalancesAfter[i] - userBalancesBefore[i];

            // Assert user received exact amount from all positions with same token
            assertEq(userBalanceDelta, buyAmountsByToken.get(availableTokens[i]));

            // Assert buy module sent all position amounts to user
            assertEq(buyModuleBalancesBefore[i] - buyModuleBalancesAfter[i], userBalanceDelta);
        }
    }

    function test_closePositionAlreadyClosed_reverts_unauthorized() public {
        uint tokenId = _createBuyPosition(0, usdc, new Buy.Investment[](0));

        vm.startPrank(account0);

        buy.closePosition(account0, tokenId, new bytes(0));

        vm.expectRevert(UsePosition.Unauthorized.selector);
        buy.closePosition(account0, tokenId, new bytes(0));
    }

    function test_closePosition_reverts_notOwner() public {
        uint tokenId = _createBuyPosition(0, usdc, new Buy.Investment[](0));

        tokenId += 1; // Ensure tokenId is not owned by account0

        vm.startPrank(account0);

        vm.expectRevert(UsePosition.Unauthorized.selector);
        buy.closePosition(account0, tokenId, new bytes(0));
    }
}
