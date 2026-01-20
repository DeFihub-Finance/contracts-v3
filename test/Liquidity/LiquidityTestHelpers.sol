// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Tick} from "@uniswap/v3-core-0.8/contracts/libraries/Tick.sol";
import {TickMath} from "@uniswap/v3-core-0.8/contracts/libraries/TickMath.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery-0.8/contracts/libraries/LiquidityAmounts.sol";

import {Slippage} from "../utils/Slippage.sol";
import {TestERC20} from "../utils/tokens/TestERC20.sol";
import {BalanceMapper, BalanceMap} from "../utils/Balances.sol";
import {UniswapV3Helper} from "../utils/exchange/UniswapV3Helper.sol";
import {BaseProductTestHelpers} from "../utils/BaseProductTestHelpers.sol";
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
    uint8 internal constant MAX_LIQUIDITY_INVESTMENTS = 10;

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
            _encodeLiquidityInvestParams(account0, inputToken, inputAmount, investments)
        );

        vm.stopPrank();
    }

    /// @dev Helper to encode liquidity product invest params
    /// @param _dustBeneficiary Address to receive dust tokens
    /// @param _inputAmount Input amount of the liquidity position
    /// @param _inputToken Input token of the liquidity position
    /// @param _investments Investments of the liquidity position
    /// @return Bytes of the encoded invest params
    function _encodeLiquidityInvestParams(
        address _dustBeneficiary,
        TestERC20 _inputToken,
        uint _inputAmount,
        Liquidity.Investment[] memory _investments
    ) internal view returns (bytes memory) {
        return abi.encode(
            Liquidity.InvestParams({
                dustBeneficiary: _dustBeneficiary,
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
            minAmount0: Slippage.deductSlippageDynamic(amount0, _token0),
            minAmount1: Slippage.deductSlippageDynamic(amount1, _token1)
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
        vm.assume(investmentParams.length > 0);
        _boundInvestmentParamsLength(investmentParams);

        // Safe to cast since investments length is capped
        uint8 maxPositionsPerPool = uint8(Math.ceilDiv(investmentParams.length, availablePools.length));

        for (uint i; i < investmentParams.length; ++i) {
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
                sqrtPriceX96,
                maxPositionsPerPool
            );

            vm.assume(params.liquidityDeltaMax > 0);

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

        // Cap upper bound of allocation amount at $500K
        maxLiquidityUsd = maxLiquidityUsd > 5e5 ether ? 5e5 ether : maxLiquidityUsd;

        uint minAllocationUsd = inputToken.usdToAmount(0.1 ether); // $0.1 in input token amount
        uint maxAllocationUsd = inputToken.usdToAmount(maxLiquidityUsd);

        vm.assume(maxAllocationUsd > minAllocationUsd);

        return bound(params.allocatedAmount, minAllocationUsd, maxAllocationUsd);
    }

    /// @dev Helper to compute the max liquidity delta from a specific range
    /// @param tickLower Lower tick
    /// @param tickUpper Upper tick
    /// @param tickSpacing Tick spacing of the pool
    /// @param sqrtPriceX96 Current sqrtPrice of the pool
    /// @param maxPositions Max positions per pool, useful if multiple positions 
    // are initialized in the same pool, with potential tick overlap
    function _getMaxLiquidityFromRange(
        int24 tickLower,
        int24 tickUpper,
        int24 tickSpacing,
        uint160 sqrtPriceX96,
        uint8 maxPositions
    ) internal pure returns (uint128) {
        uint160 sqrtRatioLower = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioUpper = TickMath.getSqrtRatioAtTick(tickUpper);

        // Get max amount0 and amount1 that can be deposited at this range.
        (uint maxAmount0, uint maxAmount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            sqrtRatioLower,
            sqrtRatioUpper,
            type(uint128).max
        );

        uint128 liquidityMaxByAmounts = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            sqrtRatioLower,
            sqrtRatioUpper,
            maxAmount0,
            maxAmount1
        );

        // Positions initialized in the same pool can overlap ticks, so we need 
        // to make sure that all of them can be created.
        uint128 liquidityMaxByTickSpacing = 
            Tick.tickSpacingToMaxLiquidityPerTick(tickSpacing) / maxPositions;

        // Return either the liquidity by amounts or the liquidity by tick spacing
        return liquidityMaxByAmounts > liquidityMaxByTickSpacing
            ? liquidityMaxByTickSpacing
            : liquidityMaxByAmounts;
    }

    function _getMaxLiquidityFromRange(
        int24 tickLower,
        int24 tickUpper,
        int24 tickSpacing,
        uint160 sqrtPriceX96
    ) internal pure returns (uint128) {
        return _getMaxLiquidityFromRange(tickLower, tickUpper, tickSpacing, sqrtPriceX96, 1);
    }

    /// @dev Helper to fees from all dex positions
    /// @param dexPositions Array of dex positions
    /// @return feeAmounts Array of PairAmounts struct containing the fee amounts
    function _getAllPositionFees(
        Liquidity.DexPosition[] memory dexPositions
    ) internal returns (Liquidity.PairAmounts[] memory feeAmounts) {
        feeAmounts = new Liquidity.PairAmounts[](dexPositions.length);

        vm.startPrank(address(liquidity));

        // Take a snapshot and revert the state after checking fee amounts, in
        // this way we can "simulate" a staticcall for a function that cannot be
        // called with staticcall since it modifies state.
        uint snapshotId = vm.snapshotState();

        for (uint i; i < dexPositions.length; ++i) {
            Liquidity.DexPosition memory dexPosition = dexPositions[i];

            (uint _fee0, uint _fee1) = dexPosition.positionManager.collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: dexPosition.lpTokenId,
                    recipient: address(0),
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                })
            );

            feeAmounts[i] = Liquidity.PairAmounts({amount0: _fee0, amount1: _fee1});
        }

        vm.revertToStateAndDelete(snapshotId);
        vm.stopPrank();
    }

    /// @dev Helper to compute user's liquidity withdrawal amounts
    /// @param performanceFee Performance fee in bps of the position
    /// @param feeAmounts Array of PairAmounts struct containing the fee amounts
    /// @return withdrawalAmounts Array of PairAmounts struct with deducted fees
    function _getLiquidityWithdrawalAmounts(
        uint16 performanceFee,
        Liquidity.PairAmounts[] memory feeAmounts
    ) internal pure returns (Liquidity.PairAmounts[] memory withdrawalAmounts) {
        withdrawalAmounts = new Liquidity.PairAmounts[](feeAmounts.length);

        for (uint i; i < feeAmounts.length; ++i) {
            Liquidity.PairAmounts memory fees = feeAmounts[i];

            withdrawalAmounts[i] = Liquidity.PairAmounts({
                amount0: _calculateRewardSplit(fees.amount0, performanceFee).userAmount,
                amount1: _calculateRewardSplit(fees.amount1, performanceFee).userAmount
            });
        }
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
        uint treasuryAmount = (_amount * protocolFeeBps) / 1e4;

        return Liquidity.RewardSplit({
            userAmount: _amount - strategistAmount - treasuryAmount,
            strategistAmount: strategistAmount,
            treasuryAmount: treasuryAmount
        });
    }

    /// @dev Helper to get reward splits map grouped by token for a position
    /// @param position Liquidity position to get the reward splits from
    /// @param feeAmounts PairAmounts struct containing the fee amounts
    /// @return rewardSplitMap Reward splits map grouped by token
    function _getRewardSplitMap(
        Liquidity.Position memory position,
        Liquidity.PairAmounts[] memory feeAmounts
    ) internal returns (RewardSplitMap memory rewardSplitMap) {
        rewardSplitMap = RewardSplitMap({
            user: BalanceMapper.init("userSplitMap"),
            treasury: BalanceMapper.init("treasurySplitMap"),
            strategist: BalanceMapper.init("strategistSplitMap")
        });

        uint16 performanceFee = position.strategistPerformanceFeeBps;
        Liquidity.DexPosition[] memory dexPositions = position.dexPositions;

        for (uint i; i < dexPositions.length; ++i) {
            IERC20 token0 = dexPositions[i].token0;
            IERC20 token1 = dexPositions[i].token1;
            Liquidity.PairAmounts memory fees = feeAmounts[i];

            Liquidity.RewardSplit memory split0 = _calculateRewardSplit(fees.amount0, performanceFee);
            Liquidity.RewardSplit memory split1 = _calculateRewardSplit(fees.amount1, performanceFee);

            rewardSplitMap.user.add(token0, split0.userAmount);
            rewardSplitMap.user.add(token1, split1.userAmount);

            rewardSplitMap.treasury.add(token0, split0.treasuryAmount);
            rewardSplitMap.treasury.add(token1, split1.treasuryAmount);

            rewardSplitMap.strategist.add(token0, split0.strategistAmount);
            rewardSplitMap.strategist.add(token1, split1.strategistAmount);
        }
    }

    /// @dev Helper to bound investment params array length to max allowed
    /// @param investmentParams Array of CreateInvestmentParams struct
    function _boundInvestmentParamsLength(
        CreateInvestmentParams[] memory investmentParams
    ) internal pure {
        if (investmentParams.length > MAX_LIQUIDITY_INVESTMENTS)
            assembly {
                mstore(investmentParams, MAX_LIQUIDITY_INVESTMENTS)
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
