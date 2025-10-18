// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

abstract contract BasePositionModule is ERC721 {
    using SafeERC20 for IERC20;

    struct StrategyIdentifier {
        address strategist;
        uint externalRef;
    }

    enum FeeReceiver {
        STRATEGIST,
        REFERRER,
        TREASURY
    }

    uint internal _nextPositionId;

    error Unauthorized();

    constructor(string memory _name, string memory _symbol) ERC721(_name, _symbol) {}

    function createPosition(bytes memory _encodedInvestments) external returns (uint positionId) {
        positionId = _mintPositionNFT();

        _createPosition(positionId, _encodedInvestments);

        return positionId;
    }

    /// @param 0: positionId
    /// @param 1: encodedInvestments
    function _createPosition(uint, bytes memory) internal virtual;

    function collectPosition(address _beneficiary, uint _positionId, bytes memory _data) external {
        if (msg.sender != _ownerOf(_positionId))
            revert Unauthorized();

        _collectPosition(_beneficiary, _positionId, _data);
    }

    function _collectPosition(address, uint, bytes memory) internal virtual;

    // maybe call close position or burn
    function closePosition(address _beneficiary, uint _positionId, bytes memory _data) external {
        if (msg.sender != _ownerOf(_positionId))
            revert Unauthorized();

        _burn(_positionId);

        _closePosition(_beneficiary, _positionId, _data);
    }

    /// @param 0: beneficiary
    /// @param 1: positionId
    /// @param 2: encodedData
    function _closePosition(address, uint, bytes memory) internal virtual;

    function _mintPositionNFT() internal returns (uint positionId) {
        positionId = _nextPositionId;

        _nextPositionId++;

        _safeMint(msg.sender, positionId);
    }

    function _pullToken(
        IERC20 _token,
        uint _inputAmount
    ) internal returns (uint receivedAmount) {
        uint initialBalance = _token.balanceOf(address(this));

        _token.safeTransferFrom(msg.sender, address(this), _inputAmount);

        return _token.balanceOf(address(this)) - initialBalance;
    }
}
