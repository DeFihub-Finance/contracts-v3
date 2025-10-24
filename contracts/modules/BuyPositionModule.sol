// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BasePositionModule} from "../abstract/BasePositionModule.sol";
import {HubRouter} from "../libraries/HubRouter.sol";

contract BuyPositionModule is BasePositionModule("DeFihub Buy Position", "DHBP") {
    using SafeERC20 for IERC20;

    struct Investment {
        bytes swap;
        // TODO gasopt: test if cheaper extracting token from swap string instead of passing as argument
        IERC20 token;
        uint allocatedAmount;
    }

    struct InvestParams {
        IERC20 inputToken;
        uint inputAmount;
        Investment[] investments;
        StrategyIdentifier strategy;
    }

    struct Position {
        IERC20 token;
        uint amount;
    }

    mapping(uint => Position[]) internal _positions;
    mapping(uint => bool) internal _closedPositions;

    event PositionClosed(address owner, address beneficiary, uint positionId, uint[] withdrawnAmounts);

    error InvalidBasisPoints();

    function getPositions(uint _positionId) external view returns (Position[] memory) {
        return _positions[_positionId];
    }

    function _createPosition(
        uint _positionId,
        bytes memory _encodedInvestments
    ) internal override {
        InvestParams memory params = abi.decode(_encodedInvestments, (InvestParams));

        uint totalAmount = _pullToken(params.inputToken, params.inputAmount);
        uint totalAllocatedAmount;

        for (uint i; i < params.investments.length; ++i) {
            Investment memory investment = params.investments[i];

            totalAllocatedAmount += investment.allocatedAmount;

            _positions[_positionId][i] = Position({
                token: investment.token,
                amount: HubRouter.execute(
                    investment.swap,
                    params.inputToken,
                    investment.token,
                    investment.allocatedAmount
                )
            });
        }

        _validateAllocatedAmount(totalAllocatedAmount, totalAmount);
    }

    function _collectPosition(address _beneficiary, uint _positionId, bytes memory) internal override {
        _claimTokens(_beneficiary, _positionId);
    }

    function _closePosition(address _beneficiary, uint _positionId, bytes memory) internal override {
        _claimTokens(_beneficiary, _positionId);
    }

    function _claimTokens(address _beneficiary, uint _positionId) internal {
        if (_closedPositions[_positionId])
            return;

        _closedPositions[_positionId] = true;

        Position[] memory positions = _positions[_positionId];
        uint[] memory withdrawnAmounts = new uint[](positions.length);

        for (uint i; i < positions.length; ++i) {
            Position memory position = positions[i];
            withdrawnAmounts[i] = position.amount;
            position.token.safeTransfer(_beneficiary, position.amount);
        }

        emit PositionClosed(msg.sender, _beneficiary, _positionId, withdrawnAmounts);
    }
}
