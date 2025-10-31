// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

struct Plan {
    bytes actions;
    bytes[] params;
    address universalRouter;
}

using RoutePlanner for Plan global;

library RoutePlanner {
    function init(address _universalRouter) internal pure returns (Plan memory plan) {
        return
            Plan({
                actions: bytes(""),
                params: new bytes[](0),
                universalRouter: _universalRouter
            });
    }

    function addCommand(
        Plan memory plan,
        uint action,
        bytes memory param
    ) internal pure returns (Plan memory) {
        bytes memory actions = new bytes(plan.params.length + 1);
        bytes[] memory params = new bytes[](plan.params.length + 1);

        for (uint i; i < params.length - 1; i++) {
            // Copy from plan.
            params[i] = plan.params[i];
            actions[i] = plan.actions[i];
        }

        // Add param and action at the end.
        params[params.length - 1] = param;
        actions[params.length - 1] = bytes1(uint8(action));

        plan.actions = actions;
        plan.params = params;

        return plan;
    }

    function encode(Plan memory plan) internal pure returns (bytes memory) {
        return abi.encode(plan.universalRouter, plan.actions, plan.params);
    }
}
