// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {UsePosition} from "../abstract/UsePosition.sol";
import {HubRouter} from "../libraries/HubRouter.sol";

contract Buy is UsePosition("DeFihub Buy Position", "DHBP") {
    using SafeERC20 for IERC20;

    struct Investment {
        HubRouter.HubSwap swap;
        // TODO gasopt: test if cheaper extracting token from swap string instead of passing as argument
        IERC20 token;
        uint allocatedAmount;
    }

    struct InvestParams {
        IERC20 inputToken;
        uint inputAmount;
        Investment[] investments;
    }

    struct Position {
        IERC20 token;
        uint amount;
    }

    mapping(uint => Position[]) internal _tokenToPositions;
    mapping(uint => bool) internal _claimedPositions;

    event PositionCollected(address owner, address beneficiary, uint tokenId, uint[] withdrawnAmounts);
    event PositionClosed(address owner, address beneficiary, uint tokenId, uint[] withdrawnAmounts);

    error InvalidBasisPoints();

    function getPositions(uint _tokenId) external view returns (Position[] memory) {
        return _tokenToPositions[_tokenId];
    }

    function _createPosition(
        uint _tokenId,
        bytes memory _encodedInvestments
    ) internal override {
        InvestParams memory params = abi.decode(_encodedInvestments, (InvestParams));

        uint totalAmount = _pullToken(params.inputToken, params.inputAmount);
        uint totalAllocatedAmount;

        for (uint i; i < params.investments.length; ++i) {
            Investment memory investment = params.investments[i];

            totalAllocatedAmount += investment.allocatedAmount;

            _tokenToPositions[_tokenId].push(Position({
                token: investment.token,
                amount: HubRouter.execute(
                    investment.swap,
                    params.inputToken,
                    investment.token,
                    investment.allocatedAmount
                )
            }));
        }

        _validateAllocatedAmount(totalAllocatedAmount, totalAmount);
    }

    function _collectPosition(address _beneficiary, uint _tokenId, bytes memory) internal override {
        emit PositionCollected(msg.sender, _beneficiary, _tokenId, _claimTokens(_beneficiary, _tokenId));
    }

    function _closePosition(address _beneficiary, uint _tokenId, bytes memory) internal override {
        emit PositionClosed(msg.sender, _beneficiary, _tokenId, _claimTokens(_beneficiary, _tokenId));
    }

    function _claimTokens(address _beneficiary, uint _tokenId) internal returns(uint[] memory withdrawnAmounts) {
        if (_claimedPositions[_tokenId])
            return new uint[](0);

        Position[] memory positions = _tokenToPositions[_tokenId];
        withdrawnAmounts = new uint[](positions.length);

        _claimedPositions[_tokenId] = true;

        for (uint i; i < positions.length; ++i) {
            Position memory position = positions[i];
            withdrawnAmounts[i] = position.amount;
            position.token.safeTransfer(_beneficiary, position.amount);
        }
    }
}
