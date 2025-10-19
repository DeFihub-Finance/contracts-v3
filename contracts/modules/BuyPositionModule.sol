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
        uint16 allocationBps;
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

    mapping(uint => Position[]) public _positions;

    event PositionCollected(address owner, address beneficiary, uint positionId, uint[] withdrawnAmounts);
    event PositionClosed(address owner, address beneficiary, uint positionId, uint[] withdrawnAmounts);

    error InvalidBasisPoints();
    error SwapAmountExceedsBalance();

    function _createPosition(
        uint _positionId,
        bytes memory _encodedInvestments
    ) internal override {
        InvestParams memory params = abi.decode(_encodedInvestments, (InvestParams));

        uint totalAmount = _pullToken(params.inputToken, params.inputAmount);
        uint16 usedAllocationBps;

        for (uint i; i < params.investments.length; ++i) {
            Investment memory investment = params.investments[i];

            usedAllocationBps += investment.allocationBps;

            _positions[_positionId].push(
                Position(
                    investment.token,
                    HubRouter.execute(
                        investment.swap,
                        params.inputToken,
                        investment.token,
                        totalAmount * investment.allocationBps / 1e4
                    )
                )
            );
        }

        if (usedAllocationBps != 100)
            revert InvalidBasisPoints();
    }

    function _collectPosition(address _beneficiary, uint _positionId, bytes memory) internal override {

    }

    function _closePosition(address _beneficiary, uint _positionId, bytes memory _data) internal override {

    }
}
