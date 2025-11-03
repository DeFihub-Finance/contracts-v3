// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import {Constants} from "../utils/Constants.sol";
import {TestERC20} from "../../contracts/test/TestERC20.sol";
import {INonfungiblePositionManager} from "../../contracts/interfaces/external/INonfungiblePositionManager.sol";

library UniswapV3Helper {
    function mintAndAddLiquidity(
        IUniswapV3Factory factory,
        INonfungiblePositionManager positionManager,
        TestERC20 tokenA,
        TestERC20 tokenB,
        uint amountA,
        uint amountB,
        uint24 priceA,
        uint24 priceB,
        address to
    ) internal returns (address poolAddress) {
        (TestERC20 token0, TestERC20 token1) = sortTokens(tokenA, tokenB);
        (address addr0, address addr1) = (address(token0), address(token1));

        (uint amount0, uint amount1, uint24 price0, uint24 price1) = token0 == tokenA
            ? (amountA, amountB, priceA, priceB)
            : (amountB, amountA, priceB, priceA);

        poolAddress = factory.getPool(addr0, addr1, Constants.FEE_MEDIUM);

        if (poolAddress == Constants.ZERO_ADDRESS) {
            poolAddress = positionManager.createAndInitializePoolIfNecessary(
                addr0,
                addr1,
                Constants.FEE_MEDIUM,
                encodeSqrtPriceX96(
                    price0,
                    price1,
                    token0.decimals(),
                    token1.decimals()
                )
            );
        }

        token0.mint(to, amount0);
        token1.mint(to, amount1);

        token0.approve(address(positionManager), amount0);
        token1.approve(address(positionManager), amount1);

        positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: addr0,
                token1: addr1,
                fee: Constants.FEE_MEDIUM,
                tickLower: -887220, // Must be aligned with fee tick spacing
                tickUpper: 887220, // Must be aligned with fee tick spacing
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
        uint24 price0,
        uint24 price1,
        uint8 decimals0,
        uint8 decimals1
    ) internal pure returns (uint160 sqrtPriceX96) {
        // Normalize to raw token amounts so price = (amount1 / amount0)
        uint numerator = price1 * 10 ** decimals1;
        uint denominator = price0 * 10 ** decimals0;

        // Compute ratio in Q192: ratioX192 = (amount1 << 192) / amount0
        // Use 512-bit mulDiv to avoid overflow and rounding.
        uint ratioX192 = Math.mulDiv(numerator, 1 << 192, denominator);

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
}
