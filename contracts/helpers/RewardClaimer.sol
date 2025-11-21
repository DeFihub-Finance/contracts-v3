// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UseReward} from "../abstract/UseReward.sol";

contract RewardClaimer {
    struct ClaimParams {
        address module;
        IERC20[] tokens;
    }

    function claimMultipleRewards(ClaimParams[] memory _params, address _owner) external {
        for (uint i; i < _params.length; ++i)
            UseReward(_params[i].module).claimRewards(_params[i].tokens, _owner);
    }
}
