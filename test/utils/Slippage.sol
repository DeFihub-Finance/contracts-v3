// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

library Slippage {
    function deductSlippage(
        uint amount,
        uint16 slippageBps
    ) internal pure returns (uint) {
        return amount - (amount * slippageBps) / 1e4;
    }
}
