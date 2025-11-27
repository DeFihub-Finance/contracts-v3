// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import "forge-std/Test.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {TickMath} from "@uniswap/v3-core-0.8/contracts/libraries/TickMath.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery-0.8/contracts/libraries/LiquidityAmounts.sol";

import {Constants} from "./Constants.sol";
import {TestERC20} from "./TestERC20.sol";
import {INonfungiblePositionManager} from "../../external/interfaces/INonfungiblePositionManager.sol";

library UniswapV3Helper {
    uint constant internal Q192 = 1 << 192;

    function mintAndAddLiquidity(
        IUniswapV3Factory factory,
        INonfungiblePositionManager positionManager,
        TestERC20 tokenA,
        TestERC20 tokenB,
        uint amountUsdPerToken,
        address to
    ) internal returns (address poolAddress) {
        (TestERC20 token0, TestERC20 token1) = sortTokens(tokenA, tokenB);
        (address addr0, address addr1) = (address(token0), address(token1));

        uint amount0 = token0.usdToAmount(amountUsdPerToken);
        uint amount1 = token1.usdToAmount(amountUsdPerToken);

        poolAddress = factory.getPool(addr0, addr1, Constants.FEE_MEDIUM);

        if (poolAddress == Constants.ZERO_ADDRESS) {
            poolAddress = positionManager.createAndInitializePoolIfNecessary(
                addr0,
                addr1,
                Constants.FEE_MEDIUM,
                encodeSqrtPriceX96(amount0, amount1)
            );
        }

        int24 tickSpacing = IUniswapV3Pool(poolAddress).tickSpacing();

        token0.mint(to, amount0);
        token1.mint(to, amount1);

        token0.approve(address(positionManager), amount0);
        token1.approve(address(positionManager), amount1);

        positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: addr0,
                token1: addr1,
                fee: Constants.FEE_MEDIUM,
                tickLower: UniswapV3Helper.minUsableTick(tickSpacing),
                tickUpper: UniswapV3Helper.maxUsableTick(tickSpacing),
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 0,
                amount1Min: 0,
                recipient: to,
                deadline: block.timestamp + 10_000
            })
        );
    }

    function encodeSqrtPriceX96(
        uint amount0,
        uint amount1
    ) internal pure returns (uint160 sqrtPriceX96) {
        // Compute ratio in Q192: ratioX192 = (amount1 << 192) / amount0
        // Use 512-bit mulDiv to avoid overflow and rounding.
        uint ratioX192 = Math.mulDiv(amount1, Q192, amount0);

        // sqrtPriceX96 = floor( sqrt(ratioX192) )
        sqrtPriceX96 = uint160(Math.sqrt(ratioX192));
    }

    function sortTokens(
        TestERC20 tokenA,
        TestERC20 tokenB
    ) internal pure returns (TestERC20 token0, TestERC20 token1) {
        return address(tokenA) < address(tokenB)
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
    }

    function maxUsableTick(int24 tickSpacing) internal pure returns (int24) {
        return (TickMath.MAX_TICK / tickSpacing) * tickSpacing;
    }

    function minUsableTick(int24 tickSpacing) internal pure returns (int24) {
        return (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
    }

    function getMintTokenAmounts(
        uint inputAmount,
        TestERC20 inputToken,
        IUniswapV3Pool pool,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidityDeltaMax
    ) internal view returns (uint amount0, uint amount1) {
        TestERC20 _token0 = TestERC20(pool.token0());
        TestERC20 _token1 = TestERC20(pool.token1());
        (uint160 sqrtPriceX96, int24 currentTick,,,,,) = pool.slot0();

        uint inputUsd = inputToken.amountToUsd(inputAmount);

        if (currentTick <= tickLower)
            // Price below range: all token0
            return (_token0.usdToAmount(inputUsd), 0);

        if (currentTick >= tickUpper)
            // Price above range: all token1
            return (0, _token1.usdToAmount(inputUsd));

        // Get max amount0 and amount1 that can be deposited
        (uint maxAmount0, uint maxAmount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            liquidityDeltaMax
        );

        // Compute ratio scaled by 1e18
        uint ratio = Math.mulDiv(_token1.amountToUsd(maxAmount1), 1e18, _token0.amountToUsd(maxAmount0));

        // amount0Usd = inputUsd / 1 + ratio (scaled by 1e18)
        uint amount0Usd = Math.mulDiv(inputUsd, 1e18, 1e18 + ratio);
        // amount1Usd = ratio * amount0Usd (scaled by 1e18)
        uint amount1Usd = Math.mulDiv(ratio, amount0Usd, 1e18);

        amount0 = _token0.usdToAmount(amount0Usd);
        amount1 = _token1.usdToAmount(amount1Usd);
    }

    function getPositionTokenAmounts(
        uint tokenId,
        IUniswapV3Factory factory,
        INonfungiblePositionManager positionManager
    ) internal view returns (uint amount0, uint amount1) {
        (
            ,,
            address token0, 
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            ,,,
        ) = positionManager.positions(tokenId);

        address poolAddress = factory.getPool(token0, token1, fee);
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(poolAddress).slot0();

        return LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            liquidity
        );
    }
}
