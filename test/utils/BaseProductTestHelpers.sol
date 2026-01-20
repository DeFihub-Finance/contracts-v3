// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Deployer} from "../utils/Deployer.sol";
import {Constants} from "../utils/Constants.sol";
import {TestERC20} from "../utils/tokens/TestERC20.sol";
import {SwapHelper} from "../utils/exchange/SwapHelper.sol";
import {PathUniswapV3} from "../utils/exchange/PathUniswapV3.sol";
import {UseReward} from "../../contracts/abstract/UseReward.sol";
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

    /// @dev Helper to get a token from a number
    /// The number is then mapped to a position in the `availableTokens` array.
    /// @param _number Number to get the token from
    /// @return A TestERC20 token
    function _getTokenFromNumber(uint _number) internal view returns (TestERC20) {
        return availableTokens[_number % availableTokens.length];
    }

    /// @dev Helper to get account rewards from a product
    /// @param account Account to get the rewards for
    /// @param product Contract to get the rewards from
    /// @return rewardBalances An array of reward amounts
    function _getAccountRewards(
        address account,
        UseReward product
    ) internal view returns (uint[] memory rewardBalances) {
        rewardBalances = new uint[](availableTokens.length);

        for (uint i; i < availableTokens.length; ++i)
            rewardBalances[i] = product.rewards(account, availableTokens[i]);
    }

    /// @dev Helper to get treasury rewards from a product
    /// @param product Contract to get the rewards from
    /// @return An array of reward amounts
    function _getTreasuryRewards(
        UseReward product
    ) internal view returns (uint[] memory) {
        return _getAccountRewards(treasury, product);
    }
}
