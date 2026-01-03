// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {INonfungiblePositionManager} from "../../external/interfaces/INonfungiblePositionManager.sol";

import {UsePosition} from "../abstract/UsePosition.sol";
import {UseReward} from "../abstract/UseReward.sol";
import {UseTreasury} from "../abstract/UseTreasury.sol";
import {HubRouter} from "../libraries/HubRouter.sol";

contract Liquidity is UsePosition("DeFihub Liquidity Position", "DHLP"), UseReward, UseTreasury, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Investment {
        INonfungiblePositionManager positionManager;
        IERC20 token0;
        IERC20 token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        HubRouter.HubSwap swap0;
        HubRouter.HubSwap swap1;
        uint swapAmount0;
        uint swapAmount1;
        uint minAmount0;
        uint minAmount1;
    }

    struct InvestParams {
        IERC20 inputToken;
        uint inputAmount;
        Investment[] investments;
        StrategyIdentifier strategy;
        uint16 strategistPerformanceFeeBps;
    }

    struct DexPosition {
        INonfungiblePositionManager positionManager;
        uint lpTokenId;
        uint128 liquidity;
        IERC20 token0; // TODO gasopt: check if saving tokens will save gas on withdrawal
        IERC20 token1;
    }

    struct Position {
        StrategyIdentifier strategy;
        uint16 strategistPerformanceFeeBps;
        DexPosition[] dexPositions;
    }

    struct Pair {
        IERC20 token0;
        IERC20 token1;
    }

    struct PairAmounts {
        uint amount0;
        uint amount1;
    }

    struct RewardSplit {
        uint userAmount;
        uint strategistAmount;
        uint treasuryAmount;
    }

    uint16 internal constant MAX_PROTOCOL_FEE_BPS = 1_500; // 15%
    uint16 internal constant MAX_STRATEGIST_FEE_BPS = 1_500; // 15%

    /// @notice Links a liquidity module position to multiple liquidity positions in decentralized exchanges
    mapping(uint => Position) internal _tokenToPositions;

    uint16 public protocolPerformanceFeeBps;

    event RewardDistributed(
        address from,
        address to,
        uint tokenId,
        uint positionIndex,
        IERC20 token0,
        IERC20 token1,
        uint amount0,
        uint amount1,
        RewardReceiver receiver
    );
    event Dust(
        address owner,
        uint tokenId,
        IERC20 token,
        uint amount
    );
    event PositionCollected(address owner, address beneficiary, uint tokenId, PairAmounts[] withdrawnAmounts);
    event PositionClosed(address owner, address beneficiary, uint tokenId, PairAmounts[] withdrawnAmounts);
    event ProtocolPerformanceFeeUpdated(uint16 protocolPerformanceFeeBps);

    error FeeTooHigh();

    constructor(
        address _owner,
        address _treasury,
        uint16 _protocolPerformanceFeeBps
    ) UseTreasury(_treasury) Ownable(_owner) {
        _setProtocolPerformanceFee(_protocolPerformanceFeeBps);
    }

    function getPositions(uint _tokenId) external view returns (Position memory) {
        return _tokenToPositions[_tokenId];
    }

    function setProtocolPerformanceFee(uint16 _protocolPerformanceFeeBps) external onlyOwner {
        _setProtocolPerformanceFee(_protocolPerformanceFeeBps);
    }

    function _setProtocolPerformanceFee(uint16 _protocolPerformanceFeeBps) internal {
        if (_protocolPerformanceFeeBps > MAX_PROTOCOL_FEE_BPS)
            revert FeeTooHigh();

        protocolPerformanceFeeBps = _protocolPerformanceFeeBps;

        emit ProtocolPerformanceFeeUpdated(_protocolPerformanceFeeBps);
    }

    function _createPosition(uint _tokenId, bytes memory _encodedInvestments) internal override nonReentrant {
        InvestParams memory params = abi.decode(_encodedInvestments, (InvestParams));

        if (params.strategistPerformanceFeeBps > MAX_STRATEGIST_FEE_BPS)
            revert FeeTooHigh();

        Position storage position = _tokenToPositions[_tokenId];

        position.strategy = params.strategy;
        position.strategistPerformanceFeeBps = params.strategistPerformanceFeeBps;

        uint initialBalanceInputToken = params.inputToken.balanceOf(address(this));
        uint totalAmount = _pullToken(params.inputToken, params.inputAmount);
        uint totalAllocatedAmount;

        for (uint i; i < params.investments.length; ++i) {
            Investment memory investment = params.investments[i];

            uint initialBalance0 = investment.token0.balanceOf(address(this));
            uint initialBalance1 = investment.token1.balanceOf(address(this));

            totalAllocatedAmount += investment.swapAmount0 + investment.swapAmount1;

            uint inputAmount0 = HubRouter.execute(
                investment.swap0,
                params.inputToken,
                investment.token0,
                investment.swapAmount0
            );
            uint inputAmount1 = HubRouter.execute(
                investment.swap1,
                params.inputToken,
                investment.token1,
                investment.swapAmount1
            );

            investment.token0.forceApprove(address(investment.positionManager), inputAmount0);
            investment.token1.forceApprove(address(investment.positionManager), inputAmount1);

            (uint lpTokenId, uint128 liquidity,,) = investment.positionManager.mint(
                INonfungiblePositionManager.MintParams({
                    token0: address(investment.token0),
                    token1: address(investment.token1),
                    fee: investment.fee,
                    tickLower: investment.tickLower,
                    tickUpper: investment.tickUpper,
                    amount0Desired: inputAmount0,
                    amount1Desired: inputAmount1,
                    amount0Min: investment.minAmount0,
                    amount1Min: investment.minAmount1,
                    recipient: address(this),
                    deadline: block.timestamp
                })
            );

            investment.token0.forceApprove(address(investment.positionManager), 0);
            investment.token1.forceApprove(address(investment.positionManager), 0);

            uint finalBalance0 = params.inputToken != investment.token0
                ? investment.token0.balanceOf(address(this))
                : 0;
            uint finalBalance1 = params.inputToken != investment.token1
                ? investment.token1.balanceOf(address(this))
                : 0;

            if (finalBalance0 > initialBalance0) {
                uint dust0 = finalBalance0 - initialBalance0;

                rewards[msg.sender][investment.token0] += dust0;

                emit Dust(msg.sender, _tokenId, investment.token0, dust0);
            }

            if (finalBalance1 > initialBalance1) {
                uint dust1 = finalBalance1 - initialBalance1;

                rewards[msg.sender][investment.token1] += dust1;

                emit Dust(msg.sender, _tokenId, investment.token1, dust1);
            }

            position.dexPositions.push(DexPosition({
                positionManager: investment.positionManager,
                lpTokenId: lpTokenId,
                liquidity: liquidity,
                token0: investment.token0,
                token1: investment.token1
            }));
        }

        uint finalBalanceInputToken = params.inputToken.balanceOf(address(this));

        if (finalBalanceInputToken > initialBalanceInputToken)
            params.inputToken.safeTransfer(msg.sender, finalBalanceInputToken - initialBalanceInputToken);

        _validateAllocatedAmount(totalAllocatedAmount, totalAmount);
    }

    function _collectPosition(address _beneficiary, uint _tokenId, bytes memory) internal override {
        Position memory position = _tokenToPositions[_tokenId];
        DexPosition[] memory dexPositions = position.dexPositions;
        PairAmounts[] memory withdrawnAmounts = new PairAmounts[](dexPositions.length);

        for (uint i; i < dexPositions.length; ++i) {
            DexPosition memory dexPosition = dexPositions[i];
            Pair memory pair = _getPairFromLP(dexPosition.positionManager, dexPosition.lpTokenId);

            PairAmounts memory userRewards = _distributeLiquidityRewards(
                pair,
                _claimLiquidityPositionTokens(dexPosition, pair),
                position.strategy, // TODO gasopt: test gas cost of passing the entire position as a single argument
                _tokenId,
                i,
                position.strategistPerformanceFeeBps
            );

            pair.token0.safeTransfer(_beneficiary, userRewards.amount0);
            pair.token1.safeTransfer(_beneficiary, userRewards.amount1);

            withdrawnAmounts[i] = userRewards;
        }

        emit PositionCollected(msg.sender, _beneficiary, _tokenId, withdrawnAmounts);
    }

    function _closePosition(address _beneficiary, uint _tokenId, bytes memory _data) internal override {
        Position memory position = _tokenToPositions[_tokenId];
        DexPosition[] memory dexPositions = position.dexPositions;
        PairAmounts[] memory withdrawnAmounts = new PairAmounts[](dexPositions.length);
        PairAmounts[] memory minOutputs = abi.decode(_data, (PairAmounts[]));

        for (uint i; i < dexPositions.length; ++i) {
            DexPosition memory dexPosition = dexPositions[i];
            Pair memory pair = _getPairFromLP(dexPosition.positionManager, dexPosition.lpTokenId);
            PairAmounts memory minOutput = minOutputs.length > i
                ? minOutputs[i]
                : PairAmounts(0, 0);

            PairAmounts memory userRewards = _distributeLiquidityRewards(
                pair,
                _claimLiquidityPositionTokens(dexPosition, pair),
                position.strategy,
                _tokenId,
                i,
                position.strategistPerformanceFeeBps
            );

            dexPosition.positionManager.decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: dexPosition.lpTokenId,
                    liquidity: dexPosition.liquidity,
                    amount0Min: minOutput.amount0,
                    amount1Min: minOutput.amount1,
                    deadline: block.timestamp
                })
            );

            PairAmounts memory balances = _claimLiquidityPositionTokens(dexPosition, pair);

            PairAmounts memory transferAmounts = PairAmounts({
                amount0: balances.amount0 + userRewards.amount0,
                amount1: balances.amount1 + userRewards.amount1
            });

            pair.token0.safeTransfer(_beneficiary, transferAmounts.amount0);
            pair.token1.safeTransfer(_beneficiary, transferAmounts.amount1);

            withdrawnAmounts[i] = transferAmounts;
        }

        emit PositionClosed(msg.sender, _beneficiary, _tokenId, withdrawnAmounts);
    }

    function _claimLiquidityPositionTokens(
        DexPosition memory _position,
        Pair memory _pair
    ) internal returns (PairAmounts memory amounts) {
        uint initialBalance0 = _pair.token0.balanceOf(address(this));
        uint initialBalance1 = _pair.token1.balanceOf(address(this));

        _position.positionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: _position.lpTokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        uint finalBalance0 = _pair.token0.balanceOf(address(this));
        uint finalBalance1 = _pair.token1.balanceOf(address(this));

        return PairAmounts({
            amount0: finalBalance0 - initialBalance0,
            amount1: finalBalance1 - initialBalance1
        });
    }

    function _distributeLiquidityRewards(
        Pair memory _pair,
        PairAmounts memory _amounts,
        StrategyIdentifier memory _strategy,
        uint _tokenId,
        uint _positionIndex,
        uint16 _strategistPerformanceFeeBps
    ) internal returns (PairAmounts memory amounts) {
        RewardSplit memory split0 = _calculateLiquidityRewardSplits(_amounts.amount0, _strategistPerformanceFeeBps);
        RewardSplit memory split1 = _calculateLiquidityRewardSplits(_amounts.amount1, _strategistPerformanceFeeBps);

        if (_strategistPerformanceFeeBps > 0) {
            rewards[_strategy.strategist][_pair.token0] += split0.strategistAmount;
            rewards[_strategy.strategist][_pair.token1] += split1.strategistAmount;

            emit RewardDistributed(
                msg.sender,
                _strategy.strategist,
                _tokenId,
                _positionIndex,
                _pair.token0,
                _pair.token1,
                split0.strategistAmount,
                split1.strategistAmount,
                RewardReceiver.STRATEGIST
            );
        }

        // TODO gasopt: test if saving treasury to variable saves gas
        rewards[_getTreasury()][_pair.token0] += split0.treasuryAmount;
        rewards[_getTreasury()][_pair.token1] += split1.treasuryAmount;

        emit RewardDistributed(
            msg.sender,
            _getTreasury(),
            _tokenId,
            _positionIndex,
            _pair.token0,
            _pair.token1,
            split0.treasuryAmount,
            split1.treasuryAmount,
            RewardReceiver.TREASURY
        );

        return PairAmounts({
            amount0: split0.userAmount,
            amount1: split1.userAmount
        });
    }

    function _calculateLiquidityRewardSplits(
        uint _amount,
        uint16 _strategistPerformanceFeeBps
    ) internal view returns (RewardSplit memory split) {
        uint strategistAmount = _amount * _strategistPerformanceFeeBps / 1e4;
        uint treasuryAmount = _amount * protocolPerformanceFeeBps / 1e4;

        return RewardSplit({
            userAmount: _amount - strategistAmount - treasuryAmount,
            strategistAmount: strategistAmount,
            treasuryAmount: treasuryAmount
        });
    }

    function _getPairFromLP(
        INonfungiblePositionManager _positionManager,
        uint _lpTokenId
    ) internal view returns (Pair memory pair) {
        (,, address token0, address token1,,,,,,,,) = _positionManager.positions(_lpTokenId);

        return Pair(IERC20(token0), IERC20(token1));
    }
}
