// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BasePositionModule} from "./abstract/BasePositionModule.sol";
import {UseTreasury} from "./abstract/UseTreasury.sol";

contract StrategyPositionModule is BasePositionModule("DeFihub Strategy Position", "DHSP"), UseTreasury {
    using SafeERC20 for IERC20;

    struct Investment {
        // Represents the portion of the deposited balance allocated for this specific investment module.
        uint16 allocationBps;
        // Where to invest the allocated funds
        address module;
        // Encoded data specific to the investment module
        bytes encodedParams;
    }

    struct InvestParams {
        IERC20 inputToken;
        uint inputAmount;

        StrategyIdentifier strategyIdentifier;
        address referrer;

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

    /// @notice positionId => StrategyPosition[]
    mapping(uint => StrategyPosition[]) internal _positions;

    /// @notice referred account => referrer account
    mapping(address => Referral) internal _referrals;
    mapping(address => bool) internal _investedBefore;

    /// @notice user => token => rewards
    mapping(address => mapping(IERC20 => uint)) public rewards;

    // settings
    uint16 public feeBps;
    uint16 public strategistFeeSharingBps;
    uint16 public referrerFeeSharingBps;
    uint public referralDuration;

    event FeeUpdated(uint16 feeBps);
    event FeeSharingUpdated(uint16 strategistFeeSharingBps, uint16 referrerFeeSharingBps);
    event FeeDistributed(address from, address to, uint strategyRef, IERC20 token, uint amount, FeeReceiver receiver);
    event ReferralLinked(address referredAccount, address referrerAccount, uint deadline);

    error InvalidInput();
    error InvalidTotalPercentage();

    constructor(
        address _owner,
        address _treasury,
        uint16 _feeBps,
        uint16 _strategistFeeSharingBps,
        uint16 _referrerFeeSharingBps,
        uint _referralDuration
    ) UseTreasury(_owner, _treasury) {
        _setFeeSharing(_strategistFeeSharingBps, _referrerFeeSharingBps);
        _setFeeBps(_feeBps);

        referralDuration = _referralDuration;
    }

    function setFeeBps(uint16 _feeBps) external onlyOwner {
        _setFeeBps(_feeBps);
    }

    /// @dev max fee is 1%
    function _setFeeBps(uint16 _feeBps) internal {
        if (_feeBps > 100)
            revert InvalidInput();

        feeBps = _feeBps;

        emit FeeUpdated(_feeBps);
    }

    function setFeeSharing(uint16 _strategistFeeSharingBps, uint16 _referrerFeeSharingBps) external onlyOwner {
        _setFeeSharing(_strategistFeeSharingBps, _referrerFeeSharingBps);
    }

    function _setFeeSharing(uint16 _strategistFeeSharingBps, uint16 _referrerFeeSharingBps) internal {
        if ((_strategistFeeSharingBps + _referrerFeeSharingBps) > 1e4)
            revert InvalidInput();

        strategistFeeSharingBps = _strategistFeeSharingBps;
        referrerFeeSharingBps = _referrerFeeSharingBps;

        emit FeeSharingUpdated(_strategistFeeSharingBps, _referrerFeeSharingBps);
    }

    // TODO add invest with permit and invest native

    // TODO test: exploit by investing using strategy position as one of the investment modules
    function _createPosition(
        uint _strategyPositionId,
        bytes memory _encodedInvestments
    ) internal override {
        InvestParams memory params = abi.decode(_encodedInvestments, (InvestParams));
        uint16 totalAllocationBps;

        _setReferrer(params.referrer);

        uint amount = _collectFees(
            params.inputToken,
            _pullToken(params.inputToken, params.inputAmount),
            params.strategyIdentifier
        );

        for (uint i; i < params.investments.length; ++i) {
            Investment memory investment = params.investments[i];

            totalAllocationBps += investment.allocationBps;

            params.inputToken.safeIncreaseAllowance(
                investment.module,
                (amount * investment.allocationBps) / 1e4
            );

            uint modulePositionId = BasePositionModule(investment.module).createPosition(investment.encodedParams);

            _positions[_strategyPositionId].push(StrategyPosition({
                moduleAddress: investment.module,
                modulePositionId: modulePositionId
            }));
        }

        if (totalAllocationBps != 1e4)
            revert InvalidTotalPercentage();
    }

    function _collectPosition(address _beneficiary, uint _positionId, bytes memory _data) internal override {
        bytes[] memory data = abi.decode(_data, (bytes[]));

        for (uint i; i < _positions[_positionId].length; ++i) {
            StrategyPosition memory position = _positions[_positionId][i];

            BasePositionModule(position.moduleAddress).collectPosition(_beneficiary, position.modulePositionId, data[i]);
        }
    }

    function _closePosition(address _beneficiary, uint _positionId, bytes memory _data) internal override {
        bytes[] memory data = abi.decode(_data, (bytes[]));

        for (uint i; i < _positions[_positionId].length; ++i) {
            StrategyPosition memory position = _positions[_positionId][i];

            BasePositionModule(position.moduleAddress).closePosition(_beneficiary, position.modulePositionId, data[i]);
        }
    }

    function _collectFees(
        IERC20 _token,
        uint _inputAmount,
        StrategyIdentifier memory _strategy
    ) internal returns (uint remainingAmount) {
        address referrer = _getReferrer(msg.sender);
        uint totalFee = (_inputAmount * feeBps) / 1e4;
        uint strategistFee;
        uint referrerFee;

        if (_strategy.strategist != address(0)) {
            strategistFee = (totalFee * strategistFeeSharingBps) / 1e4;
            rewards[_strategy.strategist][_token] += strategistFee;
            emit FeeDistributed(msg.sender, _strategy.strategist, _strategy.externalRef, _token, strategistFee, FeeReceiver.STRATEGIST);
        }

        if (referrer != address(0)) {
            referrerFee = (totalFee * referrerFeeSharingBps) / 1e4;
            rewards[referrer][_token] += referrerFee;
            emit FeeDistributed(msg.sender, referrer, _strategy.externalRef, _token, referrerFee, FeeReceiver.REFERRER);
        }

        // TODO gasopt: test if saving treasury to variable saves gas
        uint treasuryFee = totalFee - strategistFee - referrerFee;
        rewards[_getTreasury()][_token] += treasuryFee;
        emit FeeDistributed(msg.sender, _getTreasury(), _strategy.externalRef, _token, treasuryFee, FeeReceiver.TREASURY);

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

        return block.timestamp > referral.deadline ? address(0) : referral.referrer;
    }
}
