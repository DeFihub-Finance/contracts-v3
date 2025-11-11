// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

import {BasePositionModule} from "./abstract/BasePositionModule.sol";
import {BaseRewardModule} from "./abstract/BaseRewardModule.sol";
import {UseTreasury} from "./abstract/UseTreasury.sol";
import {IWETH} from "./interfaces/external/IWETH.sol";

contract StrategyPositionModule is BasePositionModule("DeFihub Strategy Position", "DHSP"), BaseRewardModule, UseTreasury {
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
        uint moduleTokenId;
    }

    struct Referral {
        address referrer;
        uint deadline;
    }

    struct ERC20Permit {
        address owner;
        address spender;
        uint value;
        uint deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    IWETH public immutable WETH;

    mapping(uint => Position[]) internal _tokenToPositions;

    /// @notice referred account => referrer account
    mapping(address => Referral) internal _referrals;
    mapping(address => bool) internal _investedBefore;

    // settings
    uint16 internal constant MAX_TOTAL_FEE_BPS = 100; // 1%
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
        IWETH _weth,
        uint16 _protocolFeeBps,
        uint16 _strategistFeeBps,
        uint16 _referrerFeeBps,
        uint _referralDuration
    ) UseTreasury(_owner, _treasury) {
        _setFees(_protocolFeeBps, _strategistFeeBps, _referrerFeeBps);

        WETH = _weth;
        referralDuration = _referralDuration;
    }

    function getPositions(uint _tokenId) external view returns (Position[] memory) {
        return _tokenToPositions[_tokenId];
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

    /// @dev _params.inputAmount is ignored, msg.value is used instead
    function createPositionEth(
        InvestParams memory _params
    ) external payable returns (uint tokenId) {
        tokenId = _createToken();

        WETH.deposit{value: msg.value}();

        _params.inputToken = IERC20(address(WETH));
        _params.inputAmount = msg.value;

        _makeInvestments(tokenId, _params);
    }

    function createPositionPermit(
        InvestParams memory _params,
        ERC20Permit memory _permit
    ) external returns (uint tokenId) {
        if (_permit.owner != msg.sender || _permit.spender != address(this))
            revert Unauthorized();

        tokenId = _createToken();

        IERC20Permit(address(_params.inputToken)).permit(
            _permit.owner,
            _permit.spender,
            _permit.value,
            _permit.deadline,
            _permit.v,
            _permit.r,
            _permit.s
        );

        _params.inputAmount = _pullToken(_params.inputToken, _params.inputAmount);

        _makeInvestments(tokenId, _params);
    }

    // TODO test: exploit by investing using strategy position as one of the investment modules
    function _createPosition(
        uint _tokenId,
        bytes memory _encodedInvestments
    ) internal override {
        InvestParams memory params = abi.decode(_encodedInvestments, (InvestParams));

        params.inputAmount = _pullToken(params.inputToken, params.inputAmount);

        _makeInvestments(_tokenId, params);
    }

    function _makeInvestments(uint _tokenId, InvestParams memory _params) internal {
        _setReferrer(_params.referrer);

        uint totalAmount = _collectFees(
            _params.inputToken,
            _params.inputAmount,
            _params.strategyIdentifier
        );
        uint totalAllocatedAmount;

        for (uint i; i < _params.investments.length; ++i) {
            Investment memory investment = _params.investments[i];

            totalAllocatedAmount += investment.allocatedAmount;

            _params.inputToken.safeIncreaseAllowance(investment.module, investment.allocatedAmount);

            uint moduleTokenId = BasePositionModule(investment.module).createPosition(investment.encodedParams);

            _tokenToPositions[_tokenId].push(Position({
                moduleAddress: investment.module,
                moduleTokenId: moduleTokenId
            }));
        }

        _validateAllocatedAmount(totalAllocatedAmount, totalAmount);
    }

    function _collectPosition(address _beneficiary, uint _tokenId, bytes memory _data) internal override {
        bytes[] memory data = abi.decode(_data, (bytes[]));

        for (uint i; i < _tokenToPositions[_tokenId].length; ++i) {
            Position memory position = _tokenToPositions[_tokenId][i];

            BasePositionModule(position.moduleAddress).collectPosition(_beneficiary, position.moduleTokenId, data[i]);
        }
    }

    function _closePosition(address _beneficiary, uint _tokenId, bytes memory _data) internal override {
        bytes[] memory data = abi.decode(_data, (bytes[]));

        for (uint i; i < _tokenToPositions[_tokenId].length; ++i) {
            Position memory position = _tokenToPositions[_tokenId][i];

            BasePositionModule(position.moduleAddress).closePosition(_beneficiary, position.moduleTokenId, data[i]);
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
