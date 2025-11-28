// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import {Tick} from "@uniswap/v3-core-0.8/contracts/libraries/Tick.sol";
import {TickMath} from "@uniswap/v3-core-0.8/contracts/libraries/TickMath.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery-0.8/contracts/libraries/LiquidityAmounts.sol";

import {SafeCast} from "../utils/SafeCast.sol";
import {Constants} from "../utils/Constants.sol";
import {Deployers} from "../utils/Deployers.sol";
import {TestERC20} from "../utils/TestERC20.sol";
import {SwapHelper} from "../utils/SwapHelper.sol";
import {PathUniswapV3} from "../utils/PathUniswapV3.sol";
import {UniswapV3Helper} from "../utils/UniswapV3Helper.sol";
import {HubRouter} from "../../contracts/libraries/HubRouter.sol";
import {UsePosition} from "../../contracts/abstract/UsePosition.sol";
import {Liquidity} from "../../contracts/products/Liquidity.sol";
import {INonfungiblePositionManager} from "../../external/interfaces/INonfungiblePositionManager.sol";

struct CreateInvestmentParams {
    int24 tickLower;
    int24 tickUpper;
    int liquidityDeltaMax;
    uint allocatedAmount;
}

abstract contract LiquidityTestHelpers is Test, Deployers {
    using SafeCast for int;
    using SafeCast for uint;

    // Maximum number of investments in a liquidty position for fuzz testing
    uint8 internal constant MAX_INVESTMENTS = 20;

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

            investments[i] = _createLiquidityInvestment(
                inputToken,
                _getPoolFromNumber(i),
                _positionParams
            );

            totalAmount += _positionParams.allocatedAmount;
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
            params.liquidityDeltaMax.toUint128()
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
            swap0: _getSwap(_swapAmount0, inputToken, _token0),
            swap1: _getSwap(_swapAmount1, inputToken, _token1),
            swapAmount0: _swapAmount0,
            swapAmount1: _swapAmount1,
            // TODO create helper to deduct slippage
            minAmount0: amount0 - (amount0 * Constants.ONE_PERCENT_BPS / 1e4),
            minAmount1: amount1 - (amount1 * Constants.ONE_PERCENT_BPS / 1e4)
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
            params.liquidityDeltaMax.toUint128()
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
    ) internal pure returns (int) {
        // Get max amount0 and amount1 that can be deposited at this range.
        (uint maxAmount0, uint maxAmount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            uint128(type(int128).max)
        );

        // If the range allows a deposit of more then int128.max in any token,
        // then we cap it at int128.max to avoid overflows.
        uint limitAmount = uint(type(uint128).max / 2);

        maxAmount0 = maxAmount0 > limitAmount ? limitAmount : maxAmount0;
        maxAmount1 = maxAmount1 > limitAmount ? limitAmount : maxAmount1;

        int liquidityMaxByAmounts = uint(
            LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                maxAmount0,
                maxAmount1
            )
        ).toInt256();

        vm.assume(liquidityMaxByAmounts != 0);

        int liquidityMaxByTickSpacing = int(uint(Tick.tickSpacingToMaxLiquidityPerTick(tickSpacing)));

        // Return either the liquidity by amounts or the liquidity by tick spacing
        return liquidityMaxByAmounts > liquidityMaxByTickSpacing
            ? liquidityMaxByTickSpacing
            : liquidityMaxByAmounts;
    }

    /// @dev Helper to get a HubRouter swap
    /// @param _amount Amount to be swapped
    /// @param _inputToken Input token of the swap
    /// @param _outputToken Output token of the swap
    /// @return A HubSwap struct data
    function _getSwap(
        uint _amount,
        TestERC20 _inputToken,
        TestERC20 _outputToken
    ) internal returns (HubRouter.HubSwap memory) {
        return SwapHelper.getHubSwapExactInput(
            SwapHelper.GetHubSwapParams({
                slippageBps: Constants.ONE_PERCENT_BPS,
                recipient: address(liquidity),
                amount: _amount,
                inputToken: _inputToken,
                outputToken: _outputToken,
                quoter: quoterUniV3,
                router: universalRouter,
                path: PathUniswapV3.init(_inputToken).addHop(Constants.FEE_MEDIUM, _outputToken)
            })
        );
    }

    function _getPoolFromNumber(uint _number) internal view returns (IUniswapV3Pool) {
        return availablePools[_number % availablePools.length];
    }
}
