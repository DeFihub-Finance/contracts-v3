// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import "forge-std/Test.sol";

import {Slippage} from "../utils/Slippage.sol";
import {Constants} from "../utils/Constants.sol";
import {TestERC20} from "../utils/tokens/TestERC20.sol";
import {Balances, BalanceMap} from "../utils/Balances.sol";
import {UniswapV3Helper} from "../utils/exchange/UniswapV3Helper.sol";
import {LiquidityTestHelpers, CreateInvestmentParams, RewardSplitMap} from "./LiquidityTestHelpers.sol";
import {Liquidity} from "../../contracts/products/Liquidity.sol";
import {UsePosition} from "../../contracts/abstract/UsePosition.sol";
import {HubRouter} from "../../contracts/libraries/HubRouter.sol";

contract ClosePositionTest is Test, LiquidityTestHelpers {
    function setUp() public {
        deployBaseContracts();
    }

    function test_fuzz_closePosition(
        uint rand,
        CreateInvestmentParams[] memory params
    ) public {
        TestERC20 inputToken = _getTokenFromNumber(rand);
        uint tokenId = _createFuzzyLiquidityPosition(inputToken, params);

        // Make swaps to generate fees
        _makeSwaps(inputToken);

        Liquidity.Position memory position = liquidity.getPositions(tokenId);
        Liquidity.PairAmounts[] memory feeAmounts = _getAllPositionFees(position.dexPositions);
        BalanceMap memory positionAmountsByToken = _getPositionAmountsByToken(position.dexPositions);

        address strategist = position.strategy.strategist;
        RewardSplitMap memory rewardSplitMap = _getRewardSplitMap(position, feeAmounts);

        uint[] memory userBalancesBefore = Balances.getAccountBalances(account0, availableTokens);
        uint[] memory treasuryRewardsBefore = _getTreasuryRewards(liquidity);
        uint[] memory strategistRewardsBefore = _getAccountRewards(strategist, liquidity);

        bytes memory encodedMinOutputs = _getEncodedMinOutputs(position);

        _expectEmitFeeDistributedEvents(tokenId, position, feeAmounts);
        _expectEmitPositionClosed(tokenId, position, feeAmounts);

        vm.startPrank(account0);

        liquidity.closePosition(account0, tokenId, encodedMinOutputs);

        vm.stopPrank();

        uint[] memory userBalancesAfter = Balances.getAccountBalances(account0, availableTokens);
        uint[] memory treasuryRewardsAfter = _getTreasuryRewards(liquidity);
        uint[] memory strategistRewardsAfter = _getAccountRewards(strategist, liquidity);

        for (uint i; i < availableTokens.length; ++i) {
            TestERC20 token = availableTokens[i];

            // Assert user received exact amounts from all dex positions
            assertEq(
                userBalancesAfter[i] - userBalancesBefore[i],
                rewardSplitMap.user.get(token) + positionAmountsByToken.get(token)
            );

            // Assert treasury and strategist received rewards
            assertEq(treasuryRewardsAfter[i] - treasuryRewardsBefore[i], rewardSplitMap.treasury.get(token));
            assertEq(strategistRewardsAfter[i] - strategistRewardsBefore[i], rewardSplitMap.strategist.get(token));
        }
    }

    function test_closePositionAlreadyClosed_reverts_unauthorized() public {
        uint tokenId = _createLiquidityPosition(0, usdc, new Liquidity.Investment[](0));

        bytes memory encodedMinOutputs = _getEncodedMinOutputs(liquidity.getPositions(tokenId));

        vm.startPrank(account0);

        liquidity.closePosition(account0, tokenId, encodedMinOutputs);

        vm.expectRevert(UsePosition.Unauthorized.selector);
        liquidity.closePosition(account0, tokenId, encodedMinOutputs);
    }

    function test_closePosition_reverts_notOwner() public {
        uint tokenId = _createLiquidityPosition(0, usdc, new Liquidity.Investment[](0));

        tokenId += 1; // Ensure tokenId is not owned by account0

        vm.startPrank(account0);

        vm.expectRevert(UsePosition.Unauthorized.selector);
        liquidity.closePosition(account0, tokenId, new bytes(0));
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

    function _getEncodedMinOutputs(
        Liquidity.Position memory position
    ) internal view returns (bytes memory) {
        Liquidity.DexPosition[] memory dexPositions = position.dexPositions;
        Liquidity.PairAmounts[] memory minOutputs = new Liquidity.PairAmounts[](dexPositions.length);

        for (uint i; i < dexPositions.length; ++i) {
            Liquidity.DexPosition memory dexPosition = dexPositions[i];

            (uint amount0, uint amount1) = UniswapV3Helper.getPositionTokenAmounts(
                dexPosition.lpTokenId,
                dexPosition.positionManager
            );

            minOutputs[i] = Liquidity.PairAmounts({
                amount0: Slippage.deductSlippage(amount0, Constants.ONE_PERCENT_BPS),
                amount1: Slippage.deductSlippage(amount1, Constants.ONE_PERCENT_BPS)
            });
        }

        return abi.encode(minOutputs);
    }

    function _expectEmitPositionClosed(
        uint tokenId,
        Liquidity.Position memory position,
        Liquidity.PairAmounts[] memory feeAmounts
    ) internal {
        vm.expectEmit(false, false, false, true, address(liquidity));
        emit Liquidity.PositionClosed(
            account0,
            account0,
            tokenId,
            _getCloseWithdrawalAmounts(position, feeAmounts)
        );
    }
}
