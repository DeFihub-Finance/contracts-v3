// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import "forge-std/Test.sol";

import {Balances, BalanceMap} from "../utils/Balances.sol";
import {BuyModuleTestHelpers} from "./BuyModuleTestHelpers.sol";
import {BuyPositionModule} from "../../contracts/modules/BuyPositionModule.sol";
import {BasePositionModule} from "../../contracts/abstract/BasePositionModule.sol";

contract CollectPosition is Test, BuyModuleTestHelpers {
    function setUp() public {
        deployBaseContracts();
    }

    function test_fuzz_collectPosition(uint[] memory allocatedAmounts) public {
        uint tokenId = _createFuzzyBuyPosition(usdc, allocatedAmounts);

        BalanceMap memory buyAmountsByToken = _getPositionAmountsByToken(tokenId);
        uint[] memory userBalancesBefore = Balances.getAccountBalances(account0, availableTokens);
        uint[] memory buyModuleBalancesBefore = Balances.getAccountBalances(address(buyPositionModule), availableTokens);

        vm.startPrank(account0);

        _expectEmitPositionCollected(tokenId, _getBuyWithdrawalAmounts(tokenId));
        buyPositionModule.collectPosition(account0, tokenId, new bytes(0));

        vm.stopPrank();

        uint[] memory userBalancesAfter = Balances.getAccountBalances(account0, availableTokens);
        uint[] memory buyModuleBalancesAfter = Balances.getAccountBalances(address(buyPositionModule), availableTokens);

        for (uint i; i < availableTokens.length; ++i) {
            uint userBalanceDelta = userBalancesAfter[i] - userBalancesBefore[i];

            // Assert user received exact amount from all positions with same token
            assertEq(userBalanceDelta, buyAmountsByToken.get(availableTokens[i]));

            // Assert buy module sent all position amounts to user
            assertEq(buyModuleBalancesBefore[i] - buyModuleBalancesAfter[i], userBalanceDelta);
        }
    }

    function test_collectPositionAlreadyCollected() public {
        uint inputAmount = 100 ether;
        uint[] memory allocatedAmounts = new uint[](1);

        allocatedAmounts[0] = inputAmount;

        (, BuyPositionModule.Investment[] memory investments) = _createBuyInvestments(usdc, allocatedAmounts);
        uint tokenId = _createBuyPosition(inputAmount, usdc, investments);

        vm.startPrank(account0);

        _expectEmitPositionCollected(tokenId, _getBuyWithdrawalAmounts(tokenId));
        buyPositionModule.collectPosition(account0, tokenId, new bytes(0));

        // Get user balances before collecting again
        uint[] memory userBalancesBefore = Balances.getAccountBalances(account0, availableTokens);

        _expectEmitPositionCollected(
            tokenId,
            new uint[](0) // No token to withdraw since already collected
        );
        buyPositionModule.collectPosition(account0, tokenId, new bytes(0));

        uint[] memory userBalancesAfter = Balances.getAccountBalances(account0, availableTokens);

        vm.stopPrank();

        for (uint i; i < availableTokens.length; ++i)
            // Assert user balances did not change
            assertEq(userBalancesBefore[i], userBalancesAfter[i]);
    }

    function test_collectPosition_reverts_notOwner() public {
        uint tokenId = _createBuyPosition(0, usdc, new BuyPositionModule.Investment[](0));

        tokenId += 1; // Ensure tokenId is not owned by account0

        vm.startPrank(account0);

        vm.expectRevert(BasePositionModule.Unauthorized.selector);
        buyPositionModule.collectPosition(account0, tokenId, new bytes(0));
    }

    function _expectEmitPositionCollected(
        uint tokenId,
        uint[] memory withdrawalAmounts
    ) internal {
        // We dont care about topics 1, 2 and 3, only the data
        vm.expectEmit(false, false, false, true, address(buyPositionModule));
        emit BuyPositionModule.PositionCollected(
            account0,
            account0,
            tokenId,
            withdrawalAmounts
        );
    }
}
