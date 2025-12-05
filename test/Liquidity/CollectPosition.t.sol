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
        Liquidity.Position memory position = liquidity.getPositions(tokenId);

        // Make swaps to generate fees
        _makeSwaps(inputToken);

        address strategist = position.strategy.strategist;
        RewardSplitMap memory rewardSplitMap = _getRewardSplitMap(position);

        uint[] memory userBalancesBefore = Balances.getAccountBalances(account0, availableTokens);
        uint[] memory treasuryRewardsBefore = _getTreasuryRewards(liquidity);
        uint[] memory strategistRewardsBefore = _getAccountRewards(strategist, liquidity);

        // Must call _expectEmitFeeDistributedEvents before since it does an external call
        _expectEmitFeeDistributedEvents(tokenId, position);
        _expectEmitPositionCollected(tokenId);

        vm.startPrank(account0);

        liquidity.collectPosition(account0, tokenId, new bytes(0));

        vm.stopPrank();

        uint[] memory userBalancesAfter = Balances.getAccountBalances(account0, availableTokens);
        uint[] memory treasuryRewardsAfter = _getTreasuryRewards(liquidity);
        uint[] memory strategistRewardsAfter = _getAccountRewards(strategist, liquidity);

        for (uint i; i < availableTokens.length; ++i) {
            TestERC20 token = availableTokens[i];

            uint userBalanceDelta = userBalancesAfter[i] - userBalancesBefore[i];
            uint treasuryBalanceDelta = treasuryRewardsAfter[i] - treasuryRewardsBefore[i];
            uint strategistBalanceDelta = strategistRewardsAfter[i] - strategistRewardsBefore[i];

            assertEq(userBalanceDelta, rewardSplitMap.user.get(token));
            assertEq(treasuryBalanceDelta, rewardSplitMap.treasury.get(token));
            assertEq(strategistBalanceDelta, rewardSplitMap.strategist.get(token));
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

    function _expectEmitPositionCollected(uint tokenId) internal {
        vm.expectEmit(false, false, false, true, address(liquidity));
        emit Liquidity.PositionCollected(
            account0,
            account0,
            tokenId,
            _getLiquidityWithdrawalAmounts(tokenId)
        );
    }

    function _expectEmitFeeDistributedEvents(
        uint tokenId,
        Liquidity.Position memory position
    ) internal {
        uint16 performanceFee = position.strategistPerformanceFeeBps;

        Liquidity.DexPosition[] memory dexPositions = position.dexPositions;
        Liquidity.PairAmounts[] memory feeAmounts = new Liquidity.PairAmounts[](dexPositions.length);

        // We need to use a separate loop since fees are fetched from an
        // external call and we want to assert the events only on collect which
        // will be the next external call
        for (uint i; i < dexPositions.length; ++i) {
            Liquidity.DexPosition memory dexPosition = dexPositions[i];

            (uint fee0, uint fee1) = UniswapV3Helper.getPositionFees(
                dexPosition.lpTokenId,
                dexPosition.positionManager
            );

            feeAmounts[i] = Liquidity.PairAmounts({amount0: fee0, amount1: fee1});
        }

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