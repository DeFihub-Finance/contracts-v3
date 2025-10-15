// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BasePositionModule} from "./abstract/BasePositionModule.sol";

contract StrategyPositionModule is BasePositionModule("DeFihub Strategy Position", "DHSP") {
    using SafeERC20 for IERC20;

    struct Investment {
        uint16 percentageBps; // Percentage allocation in basis points, represents the portion of the deposited balance of this token to be used for a specific investment module.
        address module;
        bytes encodedParams; // Encoded data specific to the investment module
    }

    struct InvestParams {
        uint strategyId;
        address strategist;
        address referrer;

        IERC20 inputToken;
        uint inputAmount;

        Investment[] investments;
    }

    struct StrategyPosition {
        address moduleAddress;
        uint modulePositionId;
    }

    struct Referral {
        address referrer;
        uint deadline;
    }

    event ReferralLinked(address referredAccount, address referrerAccount, uint deadline);

    error InvalidTotalPercentage();

    /// @notice positionId => StrategyPosition[]
    mapping(uint => StrategyPosition[]) internal _positions;

    /// @notice referred account => referrer account
    mapping(address => Referral) internal _referrals;
    mapping(address => bool) internal _investedBefore;

    /// @notice user => token => rewards
    mapping(address => mapping(IERC20 => uint)) public rewards;

    // settings
    address public treasury;
    uint public totalFeeBp;
    uint public strategistPercentageBp;
    uint public referrerPercentageBp;
    uint public referralDuration;

    // TODO add invest with permit and invest native

    function _invest(
        uint _strategyPositionId,
        bytes memory _encodedInvestments
    ) internal override {
        InvestParams memory params = abi.decode(_encodedInvestments, (InvestParams));
        uint16 totalPercentage;

        _setReferrer(params.referrer);

        uint amount = _collectFees(
            params.inputToken,
            _pullToken(params.inputToken, params.inputAmount),
            params.strategist,
            _getReferrer(msg.sender)
        );

        for (uint i; i < params.investments.length; ++i) {
            Investment memory investment = params.investments[i];

            totalPercentage += investment.percentageBps;

            params.inputToken.safeIncreaseAllowance(
                investment.module,
                (amount * investment.percentageBps) / 1e4
            );

            uint modulePositionId = BasePositionModule(investment.module).invest(investment.encodedParams);

            _positions[_strategyPositionId][i] = StrategyPosition({
                moduleAddress: investment.module,
                modulePositionId: modulePositionId
            });
        }

        if (totalPercentage != 100)
            revert InvalidTotalPercentage();
    }

    function _collectFees(
        IERC20 _token,
        uint _inputAmount,
        address _strategist,
        address _referrer
    ) internal returns (uint remainingAmount) {
        uint totalFee = (_inputAmount * totalFeeBp) / 1e4;
        uint strategistFee = (totalFee * strategistPercentageBp) / 1e4;
        uint referrerFee = (totalFee * referrerPercentageBp) / 1e4;

        rewards[_strategist][_token] += strategistFee;
        rewards[_referrer][_token] += referrerFee;
        rewards[treasury][_token] += totalFee - strategistFee - referrerFee;

        return _inputAmount - totalFee;
    }

    function _setReferrer(address _referrer) internal virtual {
        // return if user is not a new investor
        if (_investedBefore[msg.sender])
            return;

        _investedBefore[msg.sender] = true;

        // ignores zero address and self-referral
        if (_referrer == address(0) || _referrer == msg.sender)
            return;

        uint deadline = block.timestamp + referralDuration;

        _referrals[msg.sender] = Referral({
            referrer: _referrer,
            deadline: deadline
        });

        emit ReferralLinked(msg.sender, _referrer, deadline);
    }

    function _getReferrer(address _user) internal view returns (address) {
        Referral memory referral = _referrals[_user];

        return block.timestamp > referral.deadline
            ? address(0)
            : referral.referrer;
    }
}
