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
        if (amount < token.usdToAmount(100_000 ether))
            // 1% slippage for amounts < $100k
            return Slippage.deductSlippage(amount, Constants.ONE_PERCENT_BPS);

        if (amount < token.usdToAmount(500_000 ether))
            // 3% slippage for amounts >= $100k and < $500k
            return Slippage.deductSlippage(amount, Constants.THREE_PERCENT_BPS);

        // 5% slippage for amounts >= $500k
        return Slippage.deductSlippage(amount, Constants.FIVE_PERCENT_BPS);
    }
}
