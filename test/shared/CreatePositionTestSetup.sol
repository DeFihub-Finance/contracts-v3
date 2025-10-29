// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {Deployers} from "../utils/Deployers.sol";
import {Constants} from "../utils/Constants.sol";
import {UniswapV3Helper} from "../utils/UniswapV3Helper.sol";

contract CreatePositionTestSetup is Test, Deployers {
    IUniswapV3Pool public usdtWethPool;
    IUniswapV3Pool public usdtWbtcPool;
    IUniswapV3Pool public wethWbtcPool;

    function initLiquidityPools() public {
        vm.startPrank(owner);

        deployBaseContracts();

        usdtWethPool = IUniswapV3Pool(
            UniswapV3Helper.mintAndAddLiquidity(
                factoryUniV3,
                positionManagerUniV3,
                usdt,
                weth,
                Constants.ONE_MILLION_ETHER,
                Constants.ONE_MILLION_ETHER / Constants.WETH_PRICE,
                Constants.USD_PRICE,
                Constants.WETH_PRICE, 
                owner
            )
        );

        usdtWbtcPool = IUniswapV3Pool(
            UniswapV3Helper.mintAndAddLiquidity(
                factoryUniV3,
                positionManagerUniV3,
                usdt,
                wbtc,
                Constants.ONE_MILLION_ETHER,
                Constants.ONE_MILLION_ETHER / Constants.WBTC_PRICE,
                Constants.USD_PRICE,
                Constants.WBTC_PRICE, 
                owner
            )
        );

        wethWbtcPool = IUniswapV3Pool(
            UniswapV3Helper.mintAndAddLiquidity(
                factoryUniV3,
                positionManagerUniV3,
                weth,
                wbtc,
                Constants.ONE_MILLION_ETHER / Constants.WETH_PRICE,
                Constants.ONE_MILLION_ETHER / Constants.WBTC_PRICE,
                Constants.WETH_PRICE,
                Constants.WBTC_PRICE, 
                owner
            )
        );

        vm.stopPrank();
    }
}