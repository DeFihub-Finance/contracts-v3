// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.30;

contract TokenPrices {
    mapping(address => uint) internal _prices;

    function setPrice(address token, uint price) public  {
        _prices[token] = price;
    }

    function getPrice(address token) public view returns (uint) {
        return _prices[token];
    }
}
