// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TokenPrices} from "./TokenPrices.sol";

contract TestERC20 is ERC20 {
    uint8 private _decimals;
    TokenPrices private _tokenPrices;

    constructor(
        uint8 decimals_,
        TokenPrices tokenPrices_
    ) ERC20("ERC20", "ERC20") {
        _decimals = decimals_;
        _tokenPrices = tokenPrices_;
    }

    function mint(address _to, uint256 _amount) public {
        _mint(_to, _amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    /// @param usd value must be scaled by 1e18
    function usdToAmount(uint usd) public view returns (uint) {
        return usd * 10 ** _decimals / _tokenPrices.getPrice(address(this));
    }

    /// @return usd amount scaled by 1e18
    function amountToUsd(uint amount) public view returns (uint) {
        return amount * _tokenPrices.getPrice(address(this)) / 10 ** _decimals;
    }
}
