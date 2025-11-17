// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import "forge-std/Test.sol";

import {BuyModuleTestHelpers} from "./BuyModuleTestHelpers.sol";
import {BuyPositionModule} from "../../contracts/modules/BuyPositionModule.sol";
import {BasePositionModule} from "../../contracts/abstract/BasePositionModule.sol";
import {TestERC20} from "../utils/TestERC20.sol";

contract CreatePosition is Test, BuyModuleTestHelpers {
    function setUp() public {
        deployBaseContracts();
    }

    function test_fuzz_createPosition(uint[] memory allocatedAmounts) public {
        (
            uint totalAmount,
            BuyPositionModule.Investment[] memory investments
        ) = _createBuyInvestments(usdc, _boundAllocatedAmounts(allocatedAmounts, usdc));

        uint tokenId = _createBuyPosition(totalAmount, usdc, investments);
        BuyPositionModule.Position[] memory positions = buyPositionModule.getPositions(tokenId);

        assertEq(tokenId, 0);
        assertEq(positions.length, investments.length);
        assertEq(buyPositionModule.ownerOf(tokenId), account0);

        for (uint i; i < positions.length; ++i) {
            BuyPositionModule.Position memory position = positions[i];
            address outputTokenAddress = address(position.token);

            assertGt(position.amount, 0);
            assertEq(outputTokenAddress, address(investments[i].token));

            // Compare price impact values in USD, normalized with 18 decimals
            assertApproxEqRel(
                TestERC20(outputTokenAddress).amountToUsd(position.amount),
                TestERC20(usdc).amountToUsd(investments[i].allocatedAmount),
                0.05 ether // 5% price impact tolerance
            );
        }
    }

    function test_createPosition_emptyInvestments() public {
        uint tokenId = _createBuyPosition(0, usdc, new BuyPositionModule.Investment[](0));

        BuyPositionModule.Position[] memory positions = buyPositionModule.getPositions(tokenId);

        assertEq(tokenId, 0);
        assertEq(positions.length, 0);
        assertEq(buyPositionModule.ownerOf(tokenId), account0);
    }

    function test_createPosition_reverts_inputAmountLessThanTotalAllocations() public {
        uint allocationPerInvestment = 100 ether;
        uint[] memory allocationAmounts = new uint[](availableTokens.length);

        for (uint i; i < availableTokens.length; ++i) {
            allocationAmounts[i] = allocationPerInvestment;
        }

        (
            uint totalAmount,
            BuyPositionModule.Investment[] memory investments
        ) = _createBuyInvestments(usdc, allocationAmounts);

        totalAmount -= 1; // Subtract to make it less than total allocations

        _mintAndApprove(totalAmount, usdc, account0, address(buyPositionModule));

        vm.startPrank(account0);

        vm.expectRevert(BasePositionModule.InvalidAllocatedAmount.selector);
        buyPositionModule.createPosition(_getEncodedBuyInvestParams(totalAmount, usdc, investments));
    }

    function test_createPosition_reverts_totalAllocationsLessThanTolerance() public {
        uint inputAmount = 9999 ether; // Significantly larger than total allocations
        uint allocationPerInvestment = 1 ether;
        uint[] memory allocationAmounts = new uint[](availableTokens.length);

        for (uint i; i < availableTokens.length; ++i) {
            allocationAmounts[i] = allocationPerInvestment;
        }

        (, BuyPositionModule.Investment[] memory investments) = _createBuyInvestments(
            usdc,
            allocationAmounts
        );

        _mintAndApprove(inputAmount, usdc, account0, address(buyPositionModule));

        vm.startPrank(account0);

        vm.expectRevert(BasePositionModule.InvalidAllocatedAmount.selector);
        buyPositionModule.createPosition(_getEncodedBuyInvestParams(inputAmount, usdc, investments));
    }
}
