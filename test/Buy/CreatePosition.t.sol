// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import "forge-std/Test.sol";

import {BuyHelpers} from "./BuyHelpers.t.sol";
import {Buy} from "../../contracts/products/Buy.sol";
import {UsePosition} from "../../contracts/abstract/UsePosition.sol";
import {TestERC20} from "../utils/TestERC20.sol";

contract CreatePosition is Test, BuyHelpers {
    function setUp() public {
        deployBaseContracts();
    }

    function test_fuzz_createPosition(uint[] memory allocatedAmounts) public {
        (
            uint totalAmount,
            Buy.Investment[] memory investments
        ) = _createBuyInvestments(usdc, _boundAllocatedAmounts(allocatedAmounts, usdc));

        uint tokenId = _createBuyPosition(totalAmount, usdc, investments);
        Buy.Position[] memory positions = buy.getPositions(tokenId);

        assertEq(tokenId, 0);
        assertEq(positions.length, investments.length);
        assertEq(buy.ownerOf(tokenId), account0);

        for (uint i; i < positions.length; ++i) {
            Buy.Position memory position = positions[i];
            address outputTokenAddress = address(position.token);

            assertGt(position.amount, 0);
            assertEq(outputTokenAddress, address(investments[i].token));

            // Compare price impact values in USD, normalized with 18 decimals
            assertApproxEqRel(
                TestERC20(outputTokenAddress).amountToUsd(position.amount),
                usdc.amountToUsd(investments[i].allocatedAmount),
                0.05 ether // 5% price impact tolerance
            );
        }
    }

    function test_createPosition_emptyInvestments() public {
        uint tokenId = _createBuyPosition(0, usdc, new Buy.Investment[](0));

        Buy.Position[] memory positions = buy.getPositions(tokenId);

        assertEq(tokenId, 0);
        assertEq(positions.length, 0);
        assertEq(buy.ownerOf(tokenId), account0);
    }

    function test_createPosition_reverts_inputAmountLessThanTotalAllocations() public {
        uint allocationPerInvestment = 100 ether;
        uint[] memory allocationAmounts = new uint[](availableTokens.length);

        for (uint i; i < availableTokens.length; ++i)
            allocationAmounts[i] = allocationPerInvestment;

        (
            uint totalAmount,
            Buy.Investment[] memory investments
        ) = _createBuyInvestments(usdc, allocationAmounts);

        totalAmount -= 1; // Subtract to make it less than total allocations

        _mintAndApprove(totalAmount, usdc, account0, address(buy));

        vm.startPrank(account0);

        vm.expectRevert(UsePosition.InvalidAllocatedAmount.selector);
        buy.createPosition(_encodeBuyInvestParams(totalAmount, usdc, investments));
    }

    function test_createPosition_reverts_totalAllocationsLessThanTolerance() public {
        uint[] memory allocationAmounts = new uint[](availableTokens.length);

        for (uint i; i < availableTokens.length; ++i)
            allocationAmounts[i] = 1 ether; // 1 ether per buy investment

        (
            uint totalAmount,
            Buy.Investment[] memory investments
        ) = _createBuyInvestments(usdc, allocationAmounts);

        totalAmount += 9999 ether; // Significantly larger than total allocations

        _mintAndApprove(totalAmount, usdc, account0, address(buy));

        vm.startPrank(account0);

        vm.expectRevert(UsePosition.InvalidAllocatedAmount.selector);
        buy.createPosition(_encodeBuyInvestParams(totalAmount, usdc, investments));
    }
}
