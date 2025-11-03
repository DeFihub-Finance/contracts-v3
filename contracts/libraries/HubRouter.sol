// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniversalRouter} from "../interfaces/external/IUniversalRouter.sol";

library HubRouter {
    using SafeERC20 for IERC20;

    struct HubSwap {
        IUniversalRouter router;
        bytes commands;
        bytes[] inputs;
    }

    /**
     * @notice Performs a zap operation using the specified protocol call data.
     * @param _swap - Data passed to the universal router.
     * @param _inputToken - The ERC20 token to be sold.
     * @param _outputToken - The ERC20 token to be bought.
     * @param _amount - Amount of input tokens to be sold
     * @return outputAmount - The amount of output tokens bought. If no zap is needed, returns the input token amount.
     */
    function execute(
        HubSwap memory _swap,
        IERC20 _inputToken,
        IERC20 _outputToken,
        uint _amount
    ) internal returns (uint outputAmount) {
        if (_inputToken == _outputToken || _amount == 0)
            return _amount;

        uint initialOutputBalance = _outputToken.balanceOf(address(this));

        _inputToken.safeTransfer(address(_swap.router), _amount);

        _swap.router.execute(_swap.commands, _swap.inputs);

        return _outputToken.balanceOf(address(this)) - initialOutputBalance;
    }

    /**
     * @notice Performs a zap operation using the specified protocol call data.
     * @param _swap - Data passed to the universal router.
     * @param _outputToken - The ERC20 token to be bought.
     * @return outputAmount - The amount of output tokens bought.
     */
    function executeNative(
        HubSwap memory _swap,
        IERC20 _outputToken
    ) internal returns (uint outputAmount) {
        uint initialOutputBalance = _outputToken.balanceOf(address(this));

        _swap.router.execute{value: msg.value}(_swap.commands, _swap.inputs);

        return _outputToken.balanceOf(address(this)) - initialOutputBalance;
    }
}
