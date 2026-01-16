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
        uint amountUsd = token.amountToUsd(amount);

        if (amountUsd < 1 ether)
            // 10% slippage for amounts < $1
            return Slippage.deductSlippage(amount, Constants.TEN_PERCENT_BPS);

        if (amountUsd < 10_000 ether)
            // 1% slippage for amounts < $10k
            return Slippage.deductSlippage(amount, Constants.ONE_PERCENT_BPS);

        if (amountUsd < 100_000 ether)
            // 3% slippage for amounts >= $10k and < $100k
            return Slippage.deductSlippage(amount, Constants.THREE_PERCENT_BPS);

        // 5% slippage for amounts >= $100k
        return Slippage.deductSlippage(amount, Constants.FIVE_PERCENT_BPS);
    }
}
