// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {Constants} from "../utils/Constants.sol";
import {UniswapV3Helper} from "../utils/UniswapV3Helper.sol";
import {CreatePositionTestSetup} from "../shared/CreatePositionTestSetup.sol";

contract CreatePositionTest is Test, CreatePositionTestSetup {
    function setUp() public {
        initLiquidityPools();
    }

    /// @notice Creates a new strategy position
    function test_CreateStrategyPosition() public {
        uint balance = positionManagerUniV3.balanceOf(owner);
        assertEq(balance, 2);

        // StrategyPositionModule.Investment[] memory investments = new StrategyPositionModule.Investment[](1);
        // investments[0] = StrategyPositionModule.Investment({
        //     allocationBP: 1000,
        //     module: address(liquidityPositionModule),
        //     encodedParams: abi.encode()
        // });

        // StrategyPositionModule.InvestParams memory params = StrategyPositionModule.InvestParams({
        //     strategyId: 1,
        //     strategist: msg.sender,
        //     referrer: msg.sender,
        //     inputToken: address(this),
        //     inputAmount: 1000,
        //     investments: investments
        // });

        // vm.startPrank(account0);

        // strategyPositionModule.invest(abi.encode(params));

        // vm.stopPrank();
    }
}