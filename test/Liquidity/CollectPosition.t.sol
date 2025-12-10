// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import "forge-std/Test.sol";

import {TestERC20} from "../utils/tokens/TestERC20.sol";
import {Balances, BalanceMap} from "../utils/Balances.sol";
import {UniswapV3Helper} from "../utils/exchange/UniswapV3Helper.sol";
import {LiquidityTestHelpers, CreateInvestmentParams, RewardSplitMap} from "./LiquidityTestHelpers.sol";
import {Liquidity} from "../../contracts/products/Liquidity.sol";
import {UsePosition} from "../../contracts/abstract/UsePosition.sol";
import {HubRouter} from "../../contracts/libraries/HubRouter.sol";

contract CollectPositionTest is Test, LiquidityTestHelpers {
    function setUp() public {
        deployBaseContracts();
    }

    function test_fuzz_collectPosition(
        uint rand,
        CreateInvestmentParams[] memory params
    ) public {
        TestERC20 inputToken = _getTokenFromNumber(rand);
        uint tokenId = _createFuzzyLiquidityPosition(inputToken, params);

        // Make swaps to generate fees
        _makeSwaps(inputToken);

        Liquidity.Position memory position = liquidity.getPositions(tokenId);
        Liquidity.PairAmounts[] memory feeAmounts = _getAllPositionFees(position.dexPositions);

        address strategist = position.strategy.strategist;
        RewardSplitMap memory rewardSplitMap = _getRewardSplitMap(position, feeAmounts);

        uint[] memory userBalancesBefore = Balances.getAccountBalances(account0, availableTokens);
        uint[] memory treasuryRewardsBefore = _getTreasuryRewards(liquidity);
        uint[] memory strategistRewardsBefore = _getAccountRewards(strategist, liquidity);

        vm.startPrank(account0);

        _expectEmitFeeDistributedEvents(tokenId, position, feeAmounts);
        _expectEmitPositionCollected(tokenId, position, feeAmounts);

        liquidity.collectPosition(account0, tokenId, new bytes(0));

        vm.stopPrank();

        uint[] memory userBalancesAfter = Balances.getAccountBalances(account0, availableTokens);
        uint[] memory treasuryRewardsAfter = _getTreasuryRewards(liquidity);
        uint[] memory strategistRewardsAfter = _getAccountRewards(strategist, liquidity);

        for (uint i; i < availableTokens.length; ++i) {
            TestERC20 token = availableTokens[i];

            // Assert user received exact amounts from all dex positions
            assertEq(userBalancesAfter[i] - userBalancesBefore[i], rewardSplitMap.user.get(token));

            // Assert treasury and strategist received rewards
            assertEq(treasuryRewardsAfter[i] - treasuryRewardsBefore[i], rewardSplitMap.treasury.get(token));
            assertEq(strategistRewardsAfter[i] - strategistRewardsBefore[i], rewardSplitMap.strategist.get(token));
        }
    }

    function test_collectPosition_reverts_notOwner() public {
        uint tokenId = _createLiquidityPosition(0, usdc, new Liquidity.Investment[](0));

        tokenId += 1; // Ensure tokenId is not owned by account0

        vm.startPrank(account0);

        vm.expectRevert(UsePosition.Unauthorized.selector);
        liquidity.collectPosition(account0, tokenId, new bytes(0));
    }

    function _makeSwaps(TestERC20 inputToken) internal {
        vm.startPrank(owner);

        // Swap amount for each token we want to swap
        uint swapAmount = inputToken.usdToAmount(100_000 ether); // $100,000

        inputToken.mint(owner, swapAmount * availableTokens.length);

        for (uint i; i < availableTokens.length; ++i) {
            TestERC20 outputToken = availableTokens[i];

            HubRouter.execute(
                _getSwap(swapAmount, inputToken, outputToken, owner),
                inputToken,
                outputToken,
                swapAmount
            );
        }

        vm.stopPrank();
    }

    function _expectEmitPositionCollected(
        uint tokenId,
        Liquidity.Position memory position,
        Liquidity.PairAmounts[] memory feeAmounts
    ) internal {
        vm.expectEmit(false, false, false, true, address(liquidity));
        emit Liquidity.PositionCollected(
            account0,
            account0,
            tokenId,
            _getLiquidityWithdrawalAmounts(position.strategistPerformanceFeeBps, feeAmounts)
        );
    }

    function _expectEmitFeeDistributedEvents(
        uint tokenId,
        Liquidity.Position memory position,
        Liquidity.PairAmounts[] memory feeAmounts
    ) internal {
        uint16 performanceFee = position.strategistPerformanceFeeBps;
        Liquidity.DexPosition[] memory dexPositions = position.dexPositions;

        for (uint i; i < feeAmounts.length; ++i) {
            Liquidity.PairAmounts memory fees = feeAmounts[i];
            Liquidity.DexPosition memory dexPosition = dexPositions[i];

            Liquidity.RewardSplit memory split0 = _calculateRewardSplit(fees.amount0, performanceFee);
            Liquidity.RewardSplit memory split1 = _calculateRewardSplit(fees.amount1, performanceFee);

            vm.expectEmit(false, false, false, true, address(liquidity));
            emit Liquidity.FeeDistributed(
                account0,
                position.strategy.strategist,
                tokenId,
                i,
                dexPosition.token0,
                dexPosition.token1,
                split0.strategistAmount,
                split1.strategistAmount,
                UsePosition.FeeReceiver.STRATEGIST
            );

            vm.expectEmit(false, false, false, true, address(liquidity));
            emit Liquidity.FeeDistributed(
                account0,
                treasury,
                tokenId,
                i,
                dexPosition.token0,
                dexPosition.token1,
                split0.treasuryAmount,
                split1.treasuryAmount,
                UsePosition.FeeReceiver.TREASURY
            );
        }
    }
}
