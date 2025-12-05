// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Tick} from "@uniswap/v3-core-0.8/contracts/libraries/Tick.sol";
import {TickMath} from "@uniswap/v3-core-0.8/contracts/libraries/TickMath.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery-0.8/contracts/libraries/LiquidityAmounts.sol";

import {Slippage} from "../utils/Slippage.sol";
import {Constants} from "../utils/Constants.sol";
import {Deployer} from "../utils/Deployer.sol";
import {BalanceMapper, BalanceMap} from "../utils/Balances.sol";
import {TestERC20} from "../utils/tokens/TestERC20.sol";
import {SwapHelper} from "../utils/exchange/SwapHelper.sol";
import {PathUniswapV3} from "../utils/exchange/PathUniswapV3.sol";
import {UniswapV3Helper} from "../utils/exchange/UniswapV3Helper.sol";
import {BaseProductTestHelpers} from "../utils/BaseProductTestHelpers.sol";
import {HubRouter} from "../../contracts/libraries/HubRouter.sol";
import {UsePosition} from "../../contracts/abstract/UsePosition.sol";
import {Liquidity} from "../../contracts/products/Liquidity.sol";
import {INonfungiblePositionManager} from "../../external/interfaces/INonfungiblePositionManager.sol";

struct CreateInvestmentParams {
    int24 tickLower;
    int24 tickUpper;
    uint128 liquidityDeltaMax;
    uint allocatedAmount;
}

struct RewardSplitMap {
    BalanceMap user;
    BalanceMap treasury;
    BalanceMap strategist;
}

abstract contract LiquidityTestHelpers is Test, BaseProductTestHelpers {
    /// @dev Fuzz helper to create a liquidity position with bounded params
    /// @param inputToken Input token of the liquidity position
    /// @param params Array of CreateInvestmentParams struct
    /// @return tokenId The ID of the created liquidity position
    function _createFuzzyLiquidityPosition(
        TestERC20 inputToken,
        CreateInvestmentParams[] memory params
    ) internal returns (uint tokenId) {
        (
            uint totalAmount,
            Liquidity.Investment[] memory investments
        ) = _createLiquidityInvestments(
            inputToken,
            _boundCreateInvestmentParams(inputToken, params)
        );

        return _createLiquidityPosition(totalAmount, inputToken, investments);
    }

    /// @dev Helper to create a liquidity position
    /// @param inputAmount Input amount of the liquidity position
    /// @param inputToken Input token of the liquidity position
    /// @param investments Investments of the liquidity position
    /// @return tokenId The ID of the created liquidity position
    function _createLiquidityPosition(
        uint inputAmount,
        TestERC20 inputToken,
        Liquidity.Investment[] memory investments
    ) internal returns (uint tokenId) {
        _mintAndApprove(inputAmount, inputToken, account0, address(liquidity));

        vm.startPrank(account0);

        tokenId = liquidity.createPosition(
            _encodeLiquidityInvestParams(inputToken, inputAmount, investments)
        );

        vm.stopPrank();
    }

    /// @dev Helper to encode liquidity product invest params
    /// @param _inputAmount Input amount of the liquidity position
    /// @param _inputToken Input token of the liquidity position
    /// @param _investments Investments of the liquidity position
    /// @return Bytes of the encoded invest params
    function _encodeLiquidityInvestParams(
        TestERC20 _inputToken,
        uint _inputAmount,
        Liquidity.Investment[] memory _investments
    ) internal view returns (bytes memory) {
        return abi.encode(
            Liquidity.InvestParams({
                inputToken: _inputToken,
                inputAmount: _inputAmount,
                investments: _investments,
                strategistPerformanceFeeBps: 100, // 1%
                strategy: UsePosition.StrategyIdentifier({
                    strategist: owner,
                    externalRef: 1
                })
            })
        );
    }

    /// @dev Helper to create liquidity investments
    /// @param inputToken Input token of the liquidity position
    /// @param params Array of CreateInvestmentParams struct
    /// @return totalAmount Total input amount required for the liquidity position
    /// @return investments Investments of the liquidity position
    function _createLiquidityInvestments(
        TestERC20 inputToken,
        CreateInvestmentParams[] memory params
    ) internal returns (uint totalAmount, Liquidity.Investment[] memory investments) {
        investments = new Liquidity.Investment[](params.length);

        for (uint i; i < params.length; ++i) {
            CreateInvestmentParams memory _positionParams = params[i];

            Liquidity.Investment memory investment = _createLiquidityInvestment(
                inputToken,
                _getPoolFromNumber(i),
                _positionParams
            );

            investments[i] = investment;

            totalAmount += investment.swapAmount0 + investment.swapAmount1;
        }
    }

    /// @dev Helper to create a single liquidity investment
    /// @param inputToken Input token of the liquidity position
    /// @param pool Pool of the investment
    /// @param params CreateInvestmentParams struct
    /// @return investment Liquidity investment
    function _createLiquidityInvestment(
        TestERC20 inputToken,
        IUniswapV3Pool pool,
        CreateInvestmentParams memory params
    ) internal returns (Liquidity.Investment memory investment) {
        TestERC20 _token0 = TestERC20(pool.token0());
        TestERC20 _token1 = TestERC20(pool.token1());

        (uint amount0, uint amount1) = UniswapV3Helper.getMintTokenAmounts(
            params.allocatedAmount,
            inputToken,
            pool,
            params.tickLower,
            params.tickUpper,
            params.liquidityDeltaMax
        );

        uint _swapAmount0 = inputToken.usdToAmount(_token0.amountToUsd(amount0));
        uint _swapAmount1 = inputToken.usdToAmount(_token1.amountToUsd(amount1));

        return Liquidity.Investment({
            positionManager: positionManagerUniV3,
            token0: _token0,
            token1: _token1,
            fee: pool.fee(),
            tickLower: params.tickLower,
            tickUpper: params.tickUpper,
            swap0: _getSwap(_swapAmount0, inputToken, _token0, address(liquidity)),
            swap1: _getSwap(_swapAmount1, inputToken, _token1, address(liquidity)),
            swapAmount0: _swapAmount0,
            swapAmount1: _swapAmount1,
            minAmount0: Slippage.deductSlippage(amount0, Constants.ONE_PERCENT_BPS),
            minAmount1: Slippage.deductSlippage(amount1, Constants.ONE_PERCENT_BPS)
        });
    }

    /// @dev Helper to bound the CreateInvestmentParams struct
    /// @param inputToken Input token of the liquidity position
    /// @param investmentParams Array of CreateInvestmentParams struct to bound
    /// @return investmentParams Array of bounded CreateInvestmentParams struct
    function _boundCreateInvestmentParams(
        TestERC20 inputToken,
        CreateInvestmentParams[] memory investmentParams
    ) internal view returns (CreateInvestmentParams[] memory) {
        uint totalInvestments = investmentParams.length;

        vm.assume(totalInvestments > 0 && totalInvestments <= MAX_INVESTMENTS);

        for (uint i; i < totalInvestments; ++i) {
            CreateInvestmentParams memory params = investmentParams[i];

            IUniswapV3Pool pool = _getPoolFromNumber(i);
            int24 tickSpacing = pool.tickSpacing();
            (uint160 sqrtPriceX96,,,,,,) = pool.slot0();

            // Step 1 - bound ticks
            (params.tickLower, params.tickUpper) = _boundTicks(
                params.tickLower,
                params.tickUpper,
                tickSpacing
            );

            // Step 2 - compute max liquidity delta
            params.liquidityDeltaMax = _getMaxLiquidityFromRange(
                params.tickLower,
                params.tickUpper,
                tickSpacing,
                sqrtPriceX96
            );

            // Step 3 - bound allocationAmount
            params.allocatedAmount = _boundAllocationAmount(
                sqrtPriceX96,
                inputToken,
                TestERC20(pool.token0()),
                TestERC20(pool.token1()),
                params
            );
        }

        return investmentParams;
    }

    /// @dev Helper to bound the ticks
    /// @param tickLower Lower tick
    /// @param tickUpper Upper tick
    /// @param tickSpacing Tick spacing of the pool
    /// @return Bounded ticks
    function _boundTicks(
        int24 tickLower,
        int24 tickUpper,
        int24 tickSpacing
    ) internal pure returns (int24, int24) {
        int24 minUsableTick = UniswapV3Helper.minUsableTick(tickSpacing);
        int24 maxUsableTick = UniswapV3Helper.maxUsableTick(tickSpacing);

        // Must cast to int24 since bound() returns a int256
        tickLower = int24(bound(tickLower, minUsableTick, maxUsableTick));
        tickUpper = int24(bound(tickUpper, minUsableTick, maxUsableTick));

        tickLower = UniswapV3Helper.alignTick(tickLower, tickSpacing);
        tickUpper = UniswapV3Helper.alignTick(tickUpper, tickSpacing);

        // Swap ticks if lower > upper
        (tickLower, tickUpper) = tickLower < tickUpper ? (tickLower, tickUpper) : (tickUpper, tickLower);

        if (tickLower == tickUpper)
            tickLower != minUsableTick ? tickLower -= tickSpacing : tickUpper += tickSpacing;

        return (tickLower, tickUpper);
    }

    /// @dev Helper to bound the allocationAmount
    /// @param sqrtPriceX96 Current sqrtPrice of the pool
    /// @param inputToken Input token of the liquidity position
    /// @param token0 Token0 of the pool
    /// @param token1 Token1 of the pool
    /// @param params CreateInvestmentParams struct
    function _boundAllocationAmount(
        uint160 sqrtPriceX96,
        TestERC20 inputToken,
        TestERC20 token0,
        TestERC20 token1,
        CreateInvestmentParams memory params
    ) internal view returns (uint) {
        (uint amount0Max, uint amount1Max) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(params.tickLower),
            TickMath.getSqrtRatioAtTick(params.tickUpper),
            params.liquidityDeltaMax
        );

        uint maxLiquidityUsd = token0.amountToUsd(amount0Max) + token1.amountToUsd(amount1Max);

        // Cap upper bound of allocation amount at $1M
        maxLiquidityUsd = maxLiquidityUsd > 1e6 ether ? 1e6 ether : maxLiquidityUsd;

        return bound(
            params.allocatedAmount,
            inputToken.usdToAmount(0.01 ether), // $0.01 in input token amount
            inputToken.usdToAmount(maxLiquidityUsd)
        );
    }

    /// @dev Helper to compute the max liquidity delta from a specific range
    /// @param tickLower Lower tick
    /// @param tickUpper Upper tick
    /// @param tickSpacing Tick spacing of the pool
    /// @param sqrtPriceX96 Current sqrtPrice of the pool
    function _getMaxLiquidityFromRange(
        int24 tickLower,
        int24 tickUpper,
        int24 tickSpacing,
        uint160 sqrtPriceX96
    ) internal pure returns (uint128) {
        // Get max amount0 and amount1 that can be deposited at this range.
        (uint maxAmount0, uint maxAmount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            type(uint128).max
        );

        uint128 liquidityMaxByAmounts = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            maxAmount0,
            maxAmount1
        );

        vm.assume(liquidityMaxByAmounts != 0);

        uint128 liquidityMaxByTickSpacing = Tick.tickSpacingToMaxLiquidityPerTick(tickSpacing);

        // Return either the liquidity by amounts or the liquidity by tick spacing
        return liquidityMaxByAmounts > liquidityMaxByTickSpacing
            ? liquidityMaxByTickSpacing
            : liquidityMaxByAmounts;
    }


    /// @dev Helper to get the withdrawal amounts of a liquidity position.
    /// @param tokenId ID of the liquidity position
    /// @return withdrawalAmounts Array of withdrawal pair amounts
    function _getLiquidityWithdrawalAmounts(
        uint tokenId
    ) internal view returns (Liquidity.PairAmounts[] memory withdrawalAmounts) {
        Liquidity.Position memory position = liquidity.getPositions(tokenId);
        Liquidity.DexPosition[] memory dexPositions = position.dexPositions;

        withdrawalAmounts = new Liquidity.PairAmounts[](dexPositions.length);

        for (uint i; i < dexPositions.length; ++i) {
            (
                Liquidity.RewardSplit memory split0,
                Liquidity.RewardSplit memory split1
            ) = _getRewardSplits(position.strategistPerformanceFeeBps, dexPositions[i]);

            withdrawalAmounts[i] = Liquidity.PairAmounts({
                amount0: split0.userAmount,
                amount1: split1.userAmount
            });   
        }
    }

    /// @dev Helper to get reward splits for a dex position
    /// @param performanceFee Performance fee in bps of the position
    /// @param dexPosition Dex position to get the reward splits from
    /// @return split0 Reward split for token0
    /// @return split1 Reward split for token1
    function _getRewardSplits(
        uint16 performanceFee,
        Liquidity.DexPosition memory dexPosition
    ) internal view returns (Liquidity.RewardSplit memory split0, Liquidity.RewardSplit memory split1) {
        (uint fee0, uint fee1) = UniswapV3Helper.getPositionFees(
            dexPosition.lpTokenId,
            dexPosition.positionManager
        );

        split0 = _calculateRewardSplit(fee0, performanceFee);
        split1 = _calculateRewardSplit(fee1, performanceFee);
    }

    /// @dev Helper to calculate token reward split on collect/close position
    /// @param _amount Token amount
    /// @param _performanceFeeBps Performance fee in bps of the position
    /// @return A RewardSplit struct
    function _calculateRewardSplit(
        uint _amount,
        uint16 _performanceFeeBps
    ) internal pure returns (Liquidity.RewardSplit memory) {
        uint strategistAmount = (_amount * _performanceFeeBps) / 1e4;
        uint treasuryAmount = (_amount * strategistFeeBps) / 1e4;

        return Liquidity.RewardSplit({
            userAmount: _amount - strategistAmount - treasuryAmount,
            strategistAmount: strategistAmount,
            treasuryAmount: treasuryAmount
        });
    }

    /// @dev Helper to get reward splits map grouped by token for a liquidity position
    /// @param position Liquidity position to get the reward splits from
    /// @return rewardSplitMap Reward splits map grouped by token
    function _getRewardSplitMap(
        Liquidity.Position memory position
    ) internal returns (RewardSplitMap memory rewardSplitMap) {
        rewardSplitMap = RewardSplitMap({
            user: BalanceMapper.init("userSplitMap"),
            treasury: BalanceMapper.init("treasurySplitMap"),
            strategist: BalanceMapper.init("strategistSplitMap")
        });

        Liquidity.DexPosition[] memory dexPositions = position.dexPositions;

        for (uint i; i < dexPositions.length; ++i) {
            IERC20 token0 = dexPositions[i].token0;
            IERC20 token1 = dexPositions[i].token1;

            (
                Liquidity.RewardSplit memory split0,
                Liquidity.RewardSplit memory split1
            ) = _getRewardSplits(position.strategistPerformanceFeeBps, dexPositions[i]);

            rewardSplitMap.user.add(token0, split0.userAmount);
            rewardSplitMap.user.add(token1, split1.userAmount);

            rewardSplitMap.treasury.add(token0, split0.treasuryAmount);
            rewardSplitMap.treasury.add(token1, split1.treasuryAmount);

            rewardSplitMap.strategist.add(token0, split0.strategistAmount);
            rewardSplitMap.strategist.add(token1, split1.strategistAmount);
        }
    }

    /// @dev Helper to get a pool from a number
    /// The number is then mapped to a position in the `availablePools` array.
    /// @param _number Number to get the pool from
    /// @return A IUniswapV3Pool pool
    function _getPoolFromNumber(uint _number) internal view returns (IUniswapV3Pool) {
        return availablePools[_number % availablePools.length];
    }
}
