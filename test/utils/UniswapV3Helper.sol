// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import {Constants} from "../utils/Constants.sol";
import {TestERC20} from "../../contracts/test/TestERC20.sol";
import {INonfungiblePositionManager} from "../../contracts/interfaces/external/INonfungiblePositionManager.sol";

library UniswapV3Helper {
    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = -MIN_TICK;
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function mintAndAddLiquidity(
        IUniswapV3Factory factory,
        INonfungiblePositionManager positionManager,
        TestERC20 tokenA,
        TestERC20 tokenB,
        uint amountA,
        uint amountB,
        uint160 sqrtPriceX96,
        address to
    ) public {
        tokenA.mint(to, amountA);
        tokenB.mint(to, amountB);

        (TestERC20 token0, TestERC20 token1) = sortTokens(tokenA, tokenB);
        address address0 = address(token0);
        address address1 = address(token1);

        address poolAddress = factory.getPool(address0, address1, Constants.FEE_MEDIUM);

        if (poolAddress == Constants.ZERO_ADDRESS) {
            positionManager.createAndInitializePoolIfNecessary(
                address0,
                address1,
                Constants.FEE_MEDIUM,
                sqrtPriceX96
            );
        }

        vm.startPrank(to);
        
        tokenA.approve(address(positionManager), amountA);
        tokenB.approve(address(positionManager), amountB);

        positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: address0,
                token1: address1,
                fee: Constants.FEE_MEDIUM,
                tickLower: MIN_TICK,
                tickUpper: MAX_TICK,
                amount0Desired: amountA,
                amount1Desired: amountB,
                amount0Min: 0,
                amount1Min: 0,
                recipient: to,
                deadline: block.timestamp + 10000
            })
        );

        vm.stopPrank();
    }

    function sortTokens(
        TestERC20 tokenA,
        TestERC20 tokenB
    ) pure returns (TestERC20 token0, TestERC20 token1) {
        return address(tokenA) < address(tokenB) 
            ? (tokenA, tokenB) 
            : (tokenB, tokenA);
    }
}