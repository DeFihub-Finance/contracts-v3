// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {TestERC20} from "./TestERC20.sol";

contract TestWETH9 is TestERC20 {
    constructor() TestERC20(18) {}

    function deposit() external payable {
        depositTo(msg.sender);
    }

    function withdraw(uint256 amount) external {
        withdrawTo(msg.sender, amount);
    }

    function depositTo(address account) public payable {
        _mint(account, msg.value);
    }

    function withdrawTo(address account, uint256 amount) public {
        _burn(msg.sender, amount);
        (bool success, ) = account.call{ value: amount }("");
        require(success, "FAIL_TRANSFER");
    }

    receive() external payable {
        depositTo(msg.sender);
    }
}
