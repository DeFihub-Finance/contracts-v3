// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import "forge-std/Test.sol";

import {TestERC20} from "../utils/tokens/TestERC20.sol";
import {BalanceMap, BalanceMapper} from "../utils/Balances.sol";
import {DCATestHelpers, CreateInvestmentParams} from "./DCATestHelpers.sol";
import {UsePosition} from "../../contracts/abstract/UsePosition.sol";
import {DollarCostAverage as DCA} from "../../contracts/products/DollarCostAverage.sol";

contract CreatePosition is Test, DCATestHelpers {
    function setUp() public {
        deployBaseContracts();
    }

    function test_fuzz_createPosition(
        uint random,
        CreateInvestmentParams[] memory params
    ) public {
        TestERC20 inputToken = _getTokenFromNumber(random);

        (
            uint totalAmount,
            DCA.Investment[] memory investments
        ) = _createDCAInvestments(
            inputToken,
            _boundCreateInvestmentParams(inputToken, params)
        );

        uint tokenId = _createDCAPosition(totalAmount, inputToken, investments);
        DCA.Position[] memory positions = dca.getPositions(tokenId);

        assertEq(tokenId, 0);
        assertEq(positions.length, investments.length);
        assertEq(dca.ownerOf(tokenId), account0);

        BalanceMap memory swapAmountsByToken = BalanceMapper.init("swapAmountsByToken");

        for (uint i; i < positions.length; ++i) {
            DCA.Position memory position = positions[i];
            DCA.Investment memory investment = investments[i];

            assertEq(position.swaps, investment.swaps);
            assertEq(address(position.poolId.inputToken), address(investment.poolId.inputToken));
            assertEq(address(position.poolId.outputToken), address(investment.poolId.outputToken));

            assertApproxEqRel(
                TestERC20(address(position.poolId.inputToken)).amountToUsd(position.amountPerSwap),
                inputToken.amountToUsd(investment.inputAmount / investment.swaps),
                0.05 ether // 5% price impact tolerance
            );

            (uint32 performedSwaps,,uint lastSwapTimestamp) = _getPoolInfo(position.poolId);

            assertEq(lastSwapTimestamp, 0);
            assertEq(position.lastUpdateSwap, performedSwaps);
            assertEq(position.finalSwap, performedSwaps + investment.swaps);

            swapAmountsByToken.add(investment.poolId.inputToken, position.amountPerSwap);
        }

        for (uint i; i < availableTokens.length; ++i) {
            (,uint nextSwapAmount,) = _getPoolInfo(_getPoolFromNumber(i));

            // Assert the sum of amount per swap equals pool next swap amount
            assertEq(nextSwapAmount, swapAmountsByToken.get(availableTokens[i]));
        }
    }

    function test_createPosition_emptyInvestments() public {
        uint tokenId = _createDCAPosition(0, usdc, new DCA.Investment[](0));

        DCA.Position[] memory positions = dca.getPositions(tokenId);

        assertEq(tokenId, 0);
        assertEq(positions.length, 0);
        assertEq(dca.ownerOf(tokenId), account0);
    }

    function test_createPosition_reverts_inputAmountLessThanTotalAllocations() public {
        CreateInvestmentParams[] memory params = new CreateInvestmentParams[](1);

        params[0] = CreateInvestmentParams({swaps: 1, allocatedAmount: usdc.usdToAmount(1 ether)});

        (
            uint totalAmount,
            DCA.Investment[] memory investments
        ) = _createDCAInvestments(usdc, params);

        totalAmount -= 1; // Subtract to make it less than total allocations

        _mintAndApprove(totalAmount, usdc, account0, address(dca));

        vm.startPrank(account0);

        vm.expectRevert(UsePosition.InvalidAllocatedAmount.selector);
        dca.createPosition(_encodeDCAInvestParams(totalAmount, usdc, investments));
    }

    function test_createPosition_reverts_totalAllocationsLessThanTolerance() public {
        uint inputAmount = 1 ether;

        _mintAndApprove(inputAmount, usdc, account0, address(dca));

        vm.startPrank(account0);

        vm.expectRevert(UsePosition.InvalidAllocatedAmount.selector);

        dca.createPosition(
            _encodeDCAInvestParams(inputAmount, usdc, new DCA.Investment[](0))
        );
    }

    function test_reverts_invalidNumberOfSwaps() public {
        CreateInvestmentParams[] memory params = new CreateInvestmentParams[](1);

        params[0] = CreateInvestmentParams({swaps: 0, allocatedAmount: 0});

        (
            uint totalAmount,
            DCA.Investment[] memory investments
        ) = _createDCAInvestments(usdc, params);

        vm.startPrank(account0);

        vm.expectRevert(DCA.InvalidNumberOfSwaps.selector);
        dca.createPosition(_encodeDCAInvestParams(totalAmount, usdc, investments));
    }

    function test_reverts_invalidAmount() public {
        CreateInvestmentParams[] memory params = new CreateInvestmentParams[](1);

        params[0] = CreateInvestmentParams({swaps: 1, allocatedAmount: 0});

        (
            uint totalAmount,
            DCA.Investment[] memory investments
        ) = _createDCAInvestments(usdc, params);

        vm.startPrank(account0);

        vm.expectRevert(DCA.InvalidAmount.selector);
        dca.createPosition(_encodeDCAInvestParams(totalAmount, usdc, investments));
    }
}
