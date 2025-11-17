// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

import {UsePosition} from "./abstract/UsePosition.sol";
import {UseReferral} from "./abstract/UseReferral.sol";
import {UseReward} from "./abstract/UseReward.sol";
import {UseTreasury} from "./abstract/UseTreasury.sol";
import {IWETH} from "./interfaces/external/IWETH.sol";
import {HubRouter} from "./libraries/HubRouter.sol";
import {TokenArray} from "./libraries/TokenArray.sol";

contract StrategyPositionModule is UsePosition("DeFihub Strategy Position", "DHSP"), UseReward, UseReferral, UseTreasury {
    using SafeERC20 for IERC20;
    using TokenArray for IERC20[];

    struct Investment {
        // Where to invest the allocated funds
        UsePosition module;
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
        UsePosition module;
        uint moduleTokenId;
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

    // settings
    uint16 internal constant MAX_TOTAL_FEE_BPS = 100; // 1%
    uint16 public protocolFeeBps;
    uint16 public strategistFeeBps;
    uint16 public referrerFeeBps;

    event FeesUpdated(uint16 protocolFeeBps, uint16 strategistFeeBps, uint16 referrerFeeBps);
    event FeeDistributed(address from, address to, uint strategyRef, IERC20 token, uint amount, FeeReceiver receiver);

    error InvalidInput();
    error InsufficientOutputAmount();

    constructor(
        address _owner,
        address _treasury,
        IWETH _weth,
        uint16 _protocolFeeBps,
        uint16 _strategistFeeBps,
        uint16 _referrerFeeBps,
        uint _referralDuration
    ) UseTreasury(_treasury) UseReferral(_referralDuration) Ownable(_owner) {
        _setFees(_protocolFeeBps, _strategistFeeBps, _referrerFeeBps);

        WETH = _weth;
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

            _params.inputToken.safeIncreaseAllowance(address(investment.module), investment.allocatedAmount);

            uint moduleTokenId = investment.module.createPosition(investment.encodedParams);

            _tokenToPositions[_tokenId].push(Position({
                module: investment.module,
                moduleTokenId: moduleTokenId
            }));
        }

        _validateAllocatedAmount(totalAllocatedAmount, totalAmount);
    }

    function _collectPosition(address _beneficiary, uint _tokenId, bytes memory _data) internal override {
        bytes[] memory data = abi.decode(_data, (bytes[]));

        for (uint i; i < _tokenToPositions[_tokenId].length; ++i) {
            Position memory position = _tokenToPositions[_tokenId][i];

            position.module.collectPosition(_beneficiary, position.moduleTokenId, data[i]);
        }
    }

    /**
    * @param _tokens must be sorted (asc), unique. There is no need to pass the output token , even if is the output of a module.
    * @param _swaps must have the same length and be sorted as _tokens.
    **/
    function closePositionSingleToken(
        address _beneficiary,
        uint _tokenId,
        bytes memory _data,
        IERC20 _outputToken,
        uint _minOutput,
        IERC20[] memory _tokens,
        HubRouter.HubSwap[] memory _swaps
    ) external onlyPositionOwner(_tokenId) {
        if (_tokens.length != _swaps.length)
            revert InvalidInput();

        _tokens.validateUniqueAndSorted();

        _burn(_tokenId);

        uint[] memory initialTokenBalances = new uint[](_tokens.length);
        uint initialOutputTokenBalance = _outputToken.balanceOf(address(this));

        for (uint i; i < _tokens.length; ++i)
            initialTokenBalances[i] = _tokens[i].balanceOf(address(this));

        _closePosition(address(this), _tokenId, _data);

        for (uint i; i < _tokens.length; ++i) {
            IERC20 token = _tokens[i];

            if (token == _outputToken)
                continue;

            HubRouter.HubSwap memory swap = _swaps[i];

            token.safeTransfer(address(swap.router), token.balanceOf(address(this)) - initialTokenBalances[i]);
            swap.router.execute(swap.commands, swap.inputs);
        }

        uint amountOut = _outputToken.balanceOf(address(this)) - initialOutputTokenBalance;

        if (amountOut < _minOutput)
            revert InsufficientOutputAmount();

        _outputToken.safeTransfer(_beneficiary, amountOut);
    }

    function _closePosition(address _beneficiary, uint _tokenId, bytes memory _data) internal override {
        bytes[] memory data = abi.decode(_data, (bytes[]));

        for (uint i; i < _tokenToPositions[_tokenId].length; ++i) {
            Position memory position = _tokenToPositions[_tokenId][i];

            position.module.closePosition(_beneficiary, position.moduleTokenId, data[i]);
        }
    }

    function _collectFees(
        IERC20 _token,
        uint _inputAmount,
        StrategyIdentifier memory _strategy
    ) internal returns (uint remainingAmount) {
        address referrer = getReferrer(msg.sender);
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
}
