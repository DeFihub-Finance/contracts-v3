// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BasePositionModule} from "./abstract/BasePositionModule.sol";
import {UseTreasury} from "./abstract/UseTreasury.sol";

contract StrategyPositionModule is BasePositionModule("DeFihub Strategy Position", "DHSP"), UseTreasury {
    using SafeERC20 for IERC20;

    struct Investment {
        // Where to invest the allocated funds
        address module;
        // The portion of the deposited balance allocated for this specific investment module
        uint allocatedAmount;
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

    struct Position {
        address moduleAddress;
        uint modulePositionId;
    }

    struct Referral {
        address referrer;
        uint deadline;
    }

    /// @notice positionId => Position[]
    mapping(uint => Position[]) internal _positions;

    /// @notice referred account => referrer account
    mapping(address => Referral) internal _referrals;
    mapping(address => bool) internal _investedBefore;

    /// @notice user => token => rewards
    mapping(address => mapping(IERC20 => uint)) public rewards;

    // settings
    uint16 internal constant MAX_TOTAL_FEE_BPS = 250; // 2.5%
    uint16 public protocolFeeBps;
    uint16 public strategistFeeBps;
    uint16 public referrerFeeBps;
    uint public referralDuration;

    event FeesUpdated(uint16 protocolFeeBps, uint16 strategistFeeBps, uint16 referrerFeeBps);
    event FeeDistributed(address from, address to, uint strategyRef, IERC20 token, uint amount, FeeReceiver receiver);
    event ReferralLinked(address referredAccount, address referrerAccount, uint deadline);

    error InvalidInput();

    constructor(
        address _owner,
        address _treasury,
        uint16 _protocolFeeBps,
        uint16 _strategistFeeBps,
        uint16 _referrerFeeBps,
        uint _referralDuration
    ) UseTreasury(_owner, _treasury) {
        _setFees(_protocolFeeBps, _strategistFeeBps, _referrerFeeBps);

        referralDuration = _referralDuration;
    }

    function getPositions(uint _positionId) external view returns (Position[] memory) {
        return _positions[_positionId];
    }

    function setFees(
        uint16 _protocolFeeBps,
        uint16 _strategistFeeBps,
        uint16 _referrerFeeBps
    ) external onlyOwner {
        _setFees(_protocolFeeBps, _strategistFeeBps, _referrerFeeBps);
    }

    function _setFees(
        uint16 _protocolFeeBps,
        uint16 _strategistFeeBps,
        uint16 _referrerFeeBps
    ) internal {
        if ((_protocolFeeBps + _strategistFeeBps + _referrerFeeBps) > MAX_TOTAL_FEE_BPS)
            revert InvalidInput();

        protocolFeeBps = _protocolFeeBps;
        strategistFeeBps = _strategistFeeBps;
        referrerFeeBps = _referrerFeeBps;

        emit FeesUpdated(_protocolFeeBps, _strategistFeeBps, _referrerFeeBps);
    }

    // TODO add invest with permit and invest native

    // TODO test: exploit by investing using strategy position as one of the investment modules
    function _createPosition(
        uint _strategyPositionId,
        bytes memory _encodedInvestments
    ) internal override {
        InvestParams memory params = abi.decode(_encodedInvestments, (InvestParams));

        _setReferrer(params.referrer);

        uint totalAmount = _collectFees(
            params.inputToken,
            _pullToken(params.inputToken, params.inputAmount),
            params.strategyIdentifier
        );
        uint totalAllocatedAmount;

        for (uint i; i < params.investments.length; ++i) {
            Investment memory investment = params.investments[i];

            totalAllocatedAmount += investment.allocatedAmount;

            params.inputToken.safeIncreaseAllowance(investment.module, investment.allocatedAmount);

            uint modulePositionId = BasePositionModule(investment.module).createPosition(investment.encodedParams);

            _positions[_strategyPositionId].push(Position({
                moduleAddress: investment.module,
                modulePositionId: modulePositionId
            }));
        }

        _validateAllocatedAmount(totalAllocatedAmount, totalAmount);
    }

    function _collectPosition(address _beneficiary, uint _positionId, bytes memory _data) internal override {
        bytes[] memory data = abi.decode(_data, (bytes[]));

        for (uint i; i < _positions[_positionId].length; ++i) {
            Position memory position = _positions[_positionId][i];

            BasePositionModule(position.moduleAddress).collectPosition(_beneficiary, position.modulePositionId, data[i]);
        }
    }

    function _closePosition(address _beneficiary, uint _positionId, bytes memory _data) internal override {
        bytes[] memory data = abi.decode(_data, (bytes[]));

        for (uint i; i < _positions[_positionId].length; ++i) {
            Position memory position = _positions[_positionId][i];

            BasePositionModule(position.moduleAddress).closePosition(_beneficiary, position.modulePositionId, data[i]);
        }
    }

    function _collectFees(
        IERC20 _token,
        uint _inputAmount,
        StrategyIdentifier memory _strategy
    ) internal returns (uint remainingAmount) {
        address referrer = _getReferrer(msg.sender);
        bool hasReferrer = referrer != address(0);

        remainingAmount = _inputAmount;

        if (_strategy.strategist != address(0)) {
            uint strategistFee = (_inputAmount * strategistFeeBps) / 1e4;
            rewards[_strategy.strategist][_token] += strategistFee;
            remainingAmount -= strategistFee;
            emit FeeDistributed(msg.sender, _strategy.strategist, _strategy.externalRef, _token, strategistFee, FeeReceiver.STRATEGIST);
        }

        if (hasReferrer) {
            uint referrerFee = (_inputAmount * referrerFeeBps) / 1e4;
            rewards[referrer][_token] += referrerFee;
            remainingAmount -= referrerFee;
            emit FeeDistributed(msg.sender, referrer, _strategy.externalRef, _token, referrerFee, FeeReceiver.REFERRER);
        }

        // TODO gasopt: test if saving treasury to variable saves gas
        uint protocolFee = (hasReferrer ? protocolFeeBps + referrerFeeBps : protocolFeeBps) * _inputAmount / 1e4;
        rewards[_getTreasury()][_token] += protocolFee;
        remainingAmount -= protocolFee;
        emit FeeDistributed(msg.sender, _getTreasury(), _strategy.externalRef, _token, protocolFee, FeeReceiver.TREASURY);
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
