// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

abstract contract UseTreasury is Ownable {
    address private _treasury;

    event TreasuryUpdated(address treasury);

    error InvalidZeroAddress();

    constructor(address _owner, address _newTreasury) Ownable(_owner) {
        _setTreasury(_newTreasury);
    }

    function setTreasury(address _newTreasury) external onlyOwner {
        _setTreasury(_newTreasury);
    }

    function _setTreasury(address _newTreasury) internal {
        if (_treasury == address(0))
            revert InvalidZeroAddress();

        _treasury = _newTreasury;

        emit TreasuryUpdated(_newTreasury);
    }

    function _getTreasury() internal view returns (address) {
        return _treasury;
    }
}
