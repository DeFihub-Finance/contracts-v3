// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import "forge-std/Test.sol";

import {TestERC20} from "../utils/tokens/TestERC20.sol";
import {SwapHelper} from "../utils/exchange/SwapHelper.sol";
import {BalanceMap, BalanceMapper} from "../utils/Balances.sol";
import {DCATestHelpers, CreateInvestmentParams, PoolInfo} from "./DCATestHelpers.sol";
import {UsePosition} from "../../contracts/abstract/UsePosition.sol";
import {DollarCostAverage as DCA} from "../../contracts/products/DollarCostAverage.sol";

contract Swap is Test, DCATestHelpers {
    function setUp() public {
        deployBaseContracts();

        // Since tests are run in block.timestamp = 1, we need to skip 1 day to
        // make sure its greater than `pool.lastSwapTimestamp + SWAP_INTERVAL`,
        // which is expected by the DCA contract in order to swap.
        skip(1 days);
    }

    function test_fuzz_swap(
        uint rand,
        CreateInvestmentParams[] memory params
    ) public {
        uint tokenId = _createFuzzyDCAPosition(_getTokenFromNumber(rand), params);

        PoolInfo[] memory poolsInfoBefore = _getAllDCAPoolsInfo();

        uint[] memory swapFees = _getDCASwapFees(poolsInfoBefore);
        uint[] memory endingPositionDeductions = _getEndingPositionDeductions(dca.getPositions(tokenId));

        DCA.SwapParams[] memory swapParams = _getDCASwapParams(swapFees, poolsInfoBefore);

        vm.startPrank(swapper);

        // Check if events are emitted
        _expectEmitFeeAndSwapEvents(swapFees, poolsInfoBefore);
        dca.swap(swapParams);

        vm.stopPrank();

        for (uint i; i < poolsInfoBefore.length; ++i) {
            PoolInfo memory poolInfoBefore = poolsInfoBefore[i];

            // We dont care about pools that dont have anything to swap
            if (poolInfoBefore.nextSwapAmount == 0) continue;

            PoolInfo memory poolInfoAfter = _getDCAPoolInfo(poolInfoBefore.id);

            // Check if pool updates
            assertEq(poolInfoAfter.performedSwaps, poolInfoBefore.performedSwaps + 1);
            assertGt(poolInfoAfter.lastSwapTimestamp, poolInfoBefore.lastSwapTimestamp);
            assertEq(poolInfoAfter.nextSwapAmount, poolInfoBefore.nextSwapAmount - endingPositionDeductions[i]);
        }
    }

    function test_revert_callerIsNotSwapper() public {
        vm.startPrank(account0);

        vm.expectRevert(DCA.CallerIsNotSwapper.selector);
        dca.swap(new DCA.SwapParams[](0));
    }

    function test_revert_tooEarlyToSwap() public {
        CreateInvestmentParams[] memory params = new CreateInvestmentParams[](1);
        params[0] = CreateInvestmentParams({
            swaps: 2, // Must be greater than 1, otherwise it will revert
            allocatedAmount: usdc.usdToAmount(100 ether) // $100 in USDC
        });

        uint tokenId = _createPositionAndSwap(params);
        DCA.Position[] memory positions = dca.getPositions(tokenId);
        DCA.SwapParams[] memory swapParams = new DCA.SwapParams[](positions.length);

        for (uint i; i < positions.length; ++i) {
            swapParams[i] = DCA.SwapParams({
                poolId: positions[i].poolId,
                swap: _getSwap(0, usdc, usdc, address(dca)) // Swap doesnt matter
            });
        }

        vm.startPrank(swapper);

        vm.expectRevert(DCA.TooEarlyToSwap.selector);
        dca.swap(swapParams);
    }

    function test_revert_noTokensToSwap() public {
        DCA.SwapParams[] memory swapParams = new DCA.SwapParams[](1);

        swapParams[0] = DCA.SwapParams({
            poolId: _getDCAPoolFromNumber(0),
            swap: _getSwap(0, usdc, usdc, address(dca)) // Swap doesnt matter
        });

        vm.startPrank(swapper);

        vm.expectRevert(DCA.NoTokensToSwap.selector);
        dca.swap(swapParams);
    }

    // Can stay here
    function _getEndingPositionDeductions(
        DCA.Position[] memory positions
    ) internal view returns (uint[] memory endingPositionDeductions) {
        endingPositionDeductions = new uint[](availableTokens.length);

        for (uint i; i < positions.length; ++i) {
            DCA.Position memory position = positions[i];

            if (position.swaps == 1)
                // Calculate deductions from positions that have one swap
                endingPositionDeductions[i % availableTokens.length] += position.amountPerSwap;
        }
    }

    function _expectEmitFeeAndSwapEvents(
        uint[] memory swapFees,
        PoolInfo[] memory poolsInfo
    ) internal {
        uint[] memory quotes = _getDCASwapQuotes(swapFees, poolsInfo);

        for (uint i; i < poolsInfo.length; ++i) {
            PoolInfo memory poolInfo = poolsInfo[i];

            if (poolInfo.nextSwapAmount > 0) {
                uint swapFee = swapFees[i];

                vm.expectEmit(false, false, false, true, address(dca));
                emit DCA.FeeDistributed(poolInfo.id, swapFee);

                vm.expectEmit(false, false, false, true, address(dca));
                emit DCA.Swap(poolInfo.id, poolInfo.nextSwapAmount - swapFee, quotes[i]);
            }
        }
    }

    function _getDCASwapQuotes(
        uint[] memory swapFees,
        PoolInfo[] memory poolsInfo
    ) internal returns (uint[] memory quotes) {
        quotes = new uint[](poolsInfo.length);

        for (uint i; i < poolsInfo.length; ++i) {
            PoolInfo memory poolInfo = poolsInfo[i];

            if (poolInfo.nextSwapAmount > 0) {
                quotes[i] = SwapHelper.quoteInput(
                    poolInfo.nextSwapAmount - swapFees[i], 
                    poolInfo.id.inputToken, 
                    poolInfo.id.outputToken,
                    quoterUniV3
                );
            }
        }
    }
}
