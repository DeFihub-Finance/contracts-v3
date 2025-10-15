// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

abstract contract BasePositionModule is ERC721 {
    using SafeERC20 for IERC20;

    struct TokenAllocation {
        address token;
        uint16 percentageBps;
    }

    uint internal _nextPositionId;

    constructor(string memory _name, string memory _symbol) ERC721(_name, _symbol) {}

    function invest(bytes memory _encodedInvestments) external returns (uint positionId) {
        positionId = _mintPositionNFT();

        _invest(positionId, _encodedInvestments);

        return positionId;
    }

    /// @param 0: positionId
    /// @param 1: encodedInvestments
    function _invest(uint, bytes memory) internal virtual;

    // todo add close function that burns the nft and withdraws funds

    function _mintPositionNFT() internal returns (uint positionId) {
        positionId = _nextPositionId;

        _nextPositionId += 1;

        _safeMint(msg.sender, positionId);
    }

    function _pullToken(
        IERC20 _token,
        uint _inputAmount
    ) internal returns (uint receivedAmount) {
        uint initialBalance = _token.balanceOf(address(this));

        _token.safeTransferFrom(msg.sender, address(this), _inputAmount);

        return IERC20(_token).balanceOf(address(this)) - initialBalance;
    }
}
