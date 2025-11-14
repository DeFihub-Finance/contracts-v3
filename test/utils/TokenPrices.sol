// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.30;

import {TestERC20} from "./TestERC20.sol";

contract TokenPrices {
    mapping(address => uint) internal _prices;

    function setPrice(address token, uint price) public  {
        _prices[token] = price;
    }

    function getPrice(address token) public view returns (uint) {
        return _prices[token];
    }
}
