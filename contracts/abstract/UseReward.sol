// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract UseReward {
    using SafeERC20 for IERC20;

    /// @notice user => token => rewards
    mapping(address => mapping(IERC20 => uint)) public rewards;

    event RewardClaimed(address claimer, address owner, IERC20 token, uint amount);

    function claimRewards(IERC20[] calldata _tokens, address _owner) external {
        for (uint i; i < _tokens.length; ++i) {
            IERC20 token = _tokens[i];
            uint amount = rewards[_owner][token];

            if (amount == 0)
                continue;

            rewards[_owner][token] = 0;
            token.safeTransfer(_owner, amount);

            emit RewardClaimed(msg.sender, _owner, token, amount);
        }
    }
}