// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {HubRouter} from "../../contracts/libraries/HubRouter.sol";
import {IUniversalRouter} from "../../contracts/interfaces/external/IUniversalRouter.sol";

library HubSwapPlanner {
    function init(
        IUniversalRouter _universalRouter
    ) internal pure returns (HubRouter.HubSwap memory swap) {
        return HubRouter.HubSwap({
            commands: bytes(""),
            inputs: new bytes[](0),
            router: _universalRouter
        });
    }

    function addCommand(
        HubRouter.HubSwap memory swap,
        uint command,
        bytes memory input
    ) internal pure returns (HubRouter.HubSwap memory) {
        bytes memory commands = new bytes(swap.commands.length + 1);
        bytes[] memory inputs = new bytes[](swap.inputs.length + 1);

        for (uint i; i < inputs.length - 1; ++i) {
            // Copy from swap.
            inputs[i] = swap.inputs[i];
            commands[i] = swap.commands[i];
        }

        // Add input and command at the end.
        inputs[inputs.length - 1] = input;
        commands[inputs.length - 1] = bytes1(uint8(command));

        swap.inputs = inputs;
        swap.commands = commands;

        return swap;
    }
}
