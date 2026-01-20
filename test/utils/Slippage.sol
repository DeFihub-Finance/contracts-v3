// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Constants} from "../utils/Constants.sol";
import {TestERC20} from "../utils/tokens/TestERC20.sol";

library Slippage {
    function deductSlippage(
        uint amount,
        uint16 slippageBps
    ) internal pure returns (uint) {
        return amount - (amount * slippageBps / 1e4);
    }

    /// @notice Deduct slippage dynamically based on token amount
    function deductSlippageDynamic(
        uint amount,
        TestERC20 token
    ) internal view returns (uint) {
        return token.amountToUsd(amount) < 1 ether
            ? Slippage.deductSlippage(amount, Constants.TEN_PERCENT_BPS) // 10% slippage for amounts < $1
            : Slippage.deductSlippage(amount, Constants.FIVE_PERCENT_BPS);
    }
}
