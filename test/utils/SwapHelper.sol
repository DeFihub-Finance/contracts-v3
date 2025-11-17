// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IQuoter} from "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";

import {Path} from "./PathUniswapV3.sol";
import {Constants} from "./Constants.sol";
import {HubSwapPlanner} from "./HubSwapPlanner.sol";
import {HubRouter} from "../../contracts/libraries/HubRouter.sol";
import {IUniversalRouter} from "../../external/interfaces/IUniversalRouter.sol";

library SwapHelper {
    using HubSwapPlanner for HubRouter.HubSwap;

    struct GetHubSwapParams {
        uint16 slippageBps;
        address recipient;
        uint amount;
        Path path;
        IERC20 inputToken;
        IERC20 outputToken;
        IQuoter quoter;
        IUniversalRouter router;
    }

    // Router commands
    uint constant WRAP_ETH = 0x0b;
    uint constant V3_SWAP_EXACT_IN = 0x00;

    function getHubSwapExactInput(
        GetHubSwapParams memory params
    ) public returns (HubRouter.HubSwap memory swap) {
        swap = HubSwapPlanner.init(params.router);

        if (params.inputToken == params.outputToken || params.amount == 0)
            return swap;

        uint minOutput = getMinOutput(
            params.amount,
            params.inputToken,
            params.outputToken,
            params.quoter,
            params.slippageBps
        );

        swap.addCommand(
            V3_SWAP_EXACT_IN,
            abi.encode(
                params.recipient,
                params.amount,
                minOutput,
                params.path.encode(),
                false
            )
        );
    }

    function getHubSwapExactInputNative(
        GetHubSwapParams memory params
    ) public returns (HubRouter.HubSwap memory swap) {
        swap = HubSwapPlanner.init(params.router);

        if (params.inputToken == params.outputToken || params.amount == 0)
            return swap;

        uint minOutput = getMinOutput(
            params.amount,
            params.inputToken,
            params.outputToken,
            params.quoter,
            params.slippageBps
        );

        swap.addCommand(WRAP_ETH, abi.encode(params.router, params.amount));
        swap.addCommand(
            V3_SWAP_EXACT_IN,
            abi.encode(
                params.recipient,
                params.amount,
                minOutput,
                params.path.encode(),
                false
            )
        );
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
        return output - (output * slippageBps / 1e4);
    }
}
