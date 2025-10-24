// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";

import {Deployers} from "../utils/Deployers.sol";
import {Constants} from "../utils/Constants.sol";

contract CreatePositionTestSetup is Test, Deployers {
    // TODO create liquidity pools and dca pools
    // TODO mint tokens to accounts
    function createLiquidityPools() internal {
        address createdPoolAddress = factoryUniV3.createPool(address(wbtc), address(weth), Constants.FEE_MEDIUM);
    }
}