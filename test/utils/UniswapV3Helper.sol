// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import "forge-std/Test.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

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
}
