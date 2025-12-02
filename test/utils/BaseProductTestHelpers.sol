// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Deployer} from "../utils/Deployer.sol";
import {Constants} from "../utils/Constants.sol";
import {TestERC20} from "../utils/tokens/TestERC20.sol";
import {SwapHelper} from "../utils/exchange/SwapHelper.sol";
import {PathUniswapV3} from "../utils/exchange/PathUniswapV3.sol";
import {HubRouter} from "../../contracts/libraries/HubRouter.sol";

abstract contract BaseProductTestHelpers is Deployer {
    /// Maximum number of investments in a position for fuzz testing
    uint8 internal constant MAX_INVESTMENTS = 20;

    /// @dev Helper to get a HubRouter swap
    /// @param _amount Amount to be swapped
    /// @param _inputToken Input token of the swap
    /// @param _outputToken Output token of the swap
    /// @param _recipient Recipient of the swap
    /// @return A HubSwap struct data
    function _getSwap(
        uint _amount,
        TestERC20 _inputToken,
        TestERC20 _outputToken,
        address _recipient
    ) internal returns (HubRouter.HubSwap memory) {
        return SwapHelper.getHubSwapExactInput(
            SwapHelper.GetHubSwapParams({
                slippageBps: Constants.ONE_PERCENT_BPS,
                recipient: _recipient,
                amount: _amount,
                inputToken: _inputToken,
                outputToken: _outputToken,
                quoter: quoterUniV3,
                router: universalRouter,
                path: PathUniswapV3.init(_inputToken).addHop(Constants.FEE_MEDIUM, _outputToken)
            })
        );
    }
}
