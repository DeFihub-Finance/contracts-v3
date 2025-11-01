// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IQuoter} from "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";

import {Path} from "./PathUniswapV3.sol";
import {Constants} from "./Constants.sol";
import {RoutePlanner, Plan} from "./RoutePlanner.sol";

library SwapHelper {
    struct EncodeInputParams {
        address router;
        address recipient;
        uint16 slippageBps;
        uint amount;
        Path path;
        IERC20 inputToken;
        IERC20 outputToken;
        IQuoter quoter;
    }

    // Router commands
    uint constant WRAP_ETH = 0x0b;
    uint constant V3_SWAP_EXACT_IN = 0x00;

    function encodeExactInput(EncodeInputParams memory params) public returns (bytes memory) {
        if (params.inputToken == params.outputToken || params.amount == 0)
            return new bytes(0);

        uint minOutput = getMinOutput(
            params.amount,
            params.inputToken,
            params.outputToken,
            params.quoter,
            params.slippageBps
        );

        Plan memory routePlanner = RoutePlanner.init(params.router);

        routePlanner.addCommand(
            V3_SWAP_EXACT_IN,
            abi.encode(
                params.recipient,
                params.amount,
                minOutput,
                params.path.encode(),
                false
            )
        );

        return routePlanner.encode();
    }

    function encodeExactNativeInput(EncodeInputParams memory params) public returns (bytes memory) {
        if (params.inputToken == params.outputToken || params.amount == 0)
            return new bytes(0);

        uint minOutput = getMinOutput(
            params.amount,
            params.inputToken,
            params.outputToken,
            params.quoter,
            params.slippageBps
        );

        Plan memory routePlanner = RoutePlanner.init(params.router);

        routePlanner.addCommand(WRAP_ETH, abi.encode(params.router, params.amount));
        routePlanner.addCommand(
            V3_SWAP_EXACT_IN,
            abi.encode(
                params.recipient,
                params.amount,
                minOutput,
                params.path.encode(),
                false
            )
        );

        return routePlanner.encode();
    }

    function getMinOutput(
        uint amount,
        IERC20 inputToken,
        IERC20 outputToken,
        IQuoter quoter,
        uint16 slippageBps
    ) internal returns (uint) {
        uint output = quoter.quoteExactInput(
            abi.encodePacked(inputToken, Constants.FEE_MEDIUM, outputToken),
            amount
        );

        // Deduct slippage
        return (output * (10_000 - slippageBps)) / 10_000;
    }
}
