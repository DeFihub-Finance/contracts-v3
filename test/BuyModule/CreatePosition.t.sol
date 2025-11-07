// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import "forge-std/Test.sol";

import {BuyModuleTestHelpers} from "../shared/BuyModuleTestHelpers.sol";
import {BuyPositionModule} from "../../contracts/modules/BuyPositionModule.sol";
import {BasePositionModule} from "../../contracts/abstract/BasePositionModule.sol";

contract CreatePosition is Test, BuyModuleTestHelpers {
    uint8 internal immutable MAX_INVESTMENTS = 20;

    function setUp() public {
        deployBaseContracts();
    }

    function test_fuzz_createPosition(uint[] memory allocatedAmounts) public {
        vm.assume(allocatedAmounts.length > 0 && allocatedAmounts.length <= MAX_INVESTMENTS);

        (
            uint totalAmount,
            BuyPositionModule.Investment[] memory investments
        ) = _createBuyInvestments(usdt, _boundAllocatedAmounts(allocatedAmounts));

        uint tokenId = _createBuyPosition(totalAmount, usdt, investments);
        
        BuyPositionModule.Position[] memory positions = buyPositionModule.getPositions(tokenId);

        assertEq(tokenId, 0);
        assertEq(positions.length, investments.length);
        assertEq(buyPositionModule.ownerOf(tokenId), account0);

        for (uint i; i < positions.length; ++i) {
            assertEq(address(positions[i].token), address(investments[i].token));
            // TODO compare amounts in USD?
            // assertApproxEqRel(positions[i].amount, investments[i].allocatedAmount, 0.01e18);
        }
    }

    function test_createPosition_emptyInvestments() public {
        uint tokenId = _createBuyPosition(0, usdt, new BuyPositionModule.Investment[](0));

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
        ) = _createBuyInvestments(usdt, allocationAmounts);

        totalAmount -= 1; // Subtract to make it less than total allocations

        _mintAndApproveBuyModule(totalAmount, usdt, account0);

        vm.startPrank(account0);

        vm.expectRevert(BasePositionModule.InvalidAllocatedAmount.selector);
        buyPositionModule.createPosition(_getEncodedBuyInvestParams(totalAmount, usdt, investments));
    }

    function test_createPosition_reverts_totalAllocationsLessThanTolerance() public {
        uint inputAmount = 9999 ether; // Significantly larger than total allocations
        uint allocationPerInvestment = 1 ether;
        uint[] memory allocationAmounts = new uint[](availableTokens.length);

        for (uint i; i < availableTokens.length; ++i) {
            allocationAmounts[i] = allocationPerInvestment;
        }
        
        (, BuyPositionModule.Investment[] memory investments) = _createBuyInvestments(
            usdt,
            allocationAmounts
        );

        _mintAndApproveBuyModule(inputAmount, usdt, account0);

        vm.startPrank(account0);

        vm.expectRevert(BasePositionModule.InvalidAllocatedAmount.selector);
        buyPositionModule.createPosition(_getEncodedBuyInvestParams(inputAmount, usdt, investments));
    }
}
