// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";

import {Deployers} from "../utils/Deployers.sol";
import {Constants} from "../utils/Constants.sol";

contract InvestTest is Test, Deployers {
    function setUp() public {
        deployTokens();
        deployModules();
        deployUniV3();
    }

    /// @notice Creates a new strategy position
    function test_CreateStrategyPosition() public {
        address createdPoolAddress = factoryUniV3.createPool(address(wbtc), address(weth), Constants.FEE_MEDIUM);
        address poolAddress = factoryUniV3.getPool(address(wbtc), address(weth), Constants.FEE_MEDIUM);
        assertEq(createdPoolAddress, poolAddress);

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