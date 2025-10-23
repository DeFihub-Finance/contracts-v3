// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {INonfungiblePositionManager} from "../interfaces/external/INonfungiblePositionManager.sol";
import {BasePositionModule} from "../abstract/BasePositionModule.sol";
import {UseTreasury} from "../abstract/UseTreasury.sol";
import {HubRouter} from "../libraries/HubRouter.sol";

contract LiquidityPositionModule is BasePositionModule("DeFihub Liquidity Position", "DHLP"), UseTreasury {
    using SafeERC20 for IERC20;

    struct Investment {
        INonfungiblePositionManager positionManager;
        IERC20 inputToken;
        IERC20 token0;
        IERC20 token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        bytes swap0;
        bytes swap1;
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
        uint16 feeOnRewardsBps;
    }

    struct Position {
        INonfungiblePositionManager positionManager;
        uint tokenId;
        uint128 liquidity;
        IERC20 token0; // TODO gasopt: check if saving tokens will save gas on withdrawal
        IERC20 token1;
        StrategyIdentifier strategy;
        uint16 feeOnRewardsBps;
    }

    struct MinOutputs {
        uint token0;
        uint token1;
    }

    struct Pair {
        IERC20 token0;
        IERC20 token1;
    }

    struct PairBalance {
        uint balance0;
        uint balance1;
    }

    struct RewardSplit {
        uint userAmount;
        uint strategistAmount;
        uint treasuryAmount;
    }

    /// @notice Links a liquidity module position to multiple liquidity positions in decentralized exchanges
    /// @dev modulePositionId => Position[]
    mapping(uint => Position[]) public _positions;

    /// @notice user => token => rewards
    mapping(address => mapping(IERC20 => uint)) public rewards;

    uint16 internal _strategistFeeSharingBps;

    event Fee(
        address from,
        address to,
        uint positionId,
        uint positionIndex,
        IERC20 token0,
        IERC20 token1,
        uint amount0,
        uint amount1,
        FeeReceiver receiver
    );
    event PositionCollected(address owner, address beneficiary, uint positionId, uint[2][] withdrawnAmounts);
    event PositionClosed(address owner, address beneficiary, uint positionId, uint[2][] withdrawnAmounts);
    event FeeSharingUpdated(uint16 strategistFeeSharingBps);

    error InvalidBasisPoints();
    error SwapAmountExceedsBalance();

    constructor(
        address _owner,
        address _treasury,
        uint16 _newStrategistFeeSharingBps
    ) UseTreasury(_owner, _treasury) {
        _setStrategistFeeSharingBps(_newStrategistFeeSharingBps);
    }

    function setStrategistFeeSharingBps(uint16 _newStrategistFeeSharingBps) external onlyOwner {
        _setStrategistFeeSharingBps(_newStrategistFeeSharingBps);
    }

    function _setStrategistFeeSharingBps(uint16 _newStrategistFeeSharingBps) internal {
        if (_newStrategistFeeSharingBps > 1e4)
            revert InvalidBasisPoints();

        _strategistFeeSharingBps = _newStrategistFeeSharingBps;

        emit FeeSharingUpdated(_newStrategistFeeSharingBps);
    }

    function _createPosition(
        uint _positionId,
        bytes memory _encodedInvestments
    ) internal override {
        InvestParams memory params = abi.decode(_encodedInvestments, (InvestParams));

        uint remainingAmount = _pullToken(params.inputToken, params.inputAmount);

        for (uint i; i < params.investments.length; ++i) {
            Investment memory investment = params.investments[i];

            uint required = investment.swapAmount0 + investment.swapAmount1;

            if (remainingAmount < required)
                revert SwapAmountExceedsBalance();

            remainingAmount -= required;

            uint inputAmount0 = HubRouter.execute(
                investment.swap0,
                investment.inputToken,
                investment.token0,
                investment.swapAmount0
            );
            uint inputAmount1 = HubRouter.execute(
                investment.swap1,
                investment.inputToken,
                investment.token1,
                investment.swapAmount1
            );

            investment.token0.safeIncreaseAllowance(address(investment.positionManager), inputAmount0);
            investment.token1.safeIncreaseAllowance(address(investment.positionManager), inputAmount1);

            (uint256 tokenId, uint128 liquidity,,) = investment.positionManager.mint(
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

            _positions[_positionId].push(Position({
                positionManager: investment.positionManager,
                tokenId: tokenId,
                liquidity: liquidity,
                token0: investment.token0,
                token1: investment.token1,
                strategy: params.strategy,
                feeOnRewardsBps: params.feeOnRewardsBps
            }));
        }
    }

    function _collectPosition(address _beneficiary, uint _positionId, bytes memory) internal override {
        Position[] memory positions = _positions[_positionId];
        uint[2][] memory withdrawnAmounts = new uint[2][](positions.length);

        for (uint i; i < positions.length; ++i) {
            Position memory position = positions[i];
            Pair memory pair = _getPairFromLP(position.positionManager, position.tokenId);

            (uint rewards0, uint rewards1) = _claimLiquidityPositionTokens(position, pair);

            (uint userRewards0, uint userRewards1) = _distributeLiquidityRewards(
                pair,
                rewards0,
                rewards1,
                position.strategy, // TODO gasopt: test gas cost of passing the entire position as a single argument
                _positionId,
                i,
                position.feeOnRewardsBps
            );

            pair.token0.safeTransfer(msg.sender, userRewards0);
            pair.token1.safeTransfer(msg.sender, userRewards1);

            withdrawnAmounts[i] = [userRewards0, userRewards1];
        }

        emit PositionCollected(msg.sender, _beneficiary, _positionId, withdrawnAmounts);
    }

    function _closePosition(address _beneficiary, uint _positionId, bytes memory _data) internal override {
        MinOutputs[] memory minOutputs = abi.decode(_data, (MinOutputs[]));
        Position[] memory positions = _positions[_positionId];
        uint[2][] memory withdrawnAmounts = new uint[2][](positions.length);

        for (uint i; i < positions.length; ++i) {
            Position memory position = positions[i];
            Pair memory pair = _getPairFromLP(position.positionManager, position.tokenId);
            MinOutputs memory minOutput = minOutputs.length > i
                ? minOutputs[i]
                : MinOutputs(0, 0);

            // Claim must be called before decreasing liquidity to subtract fees only from rewards
            (uint rewards0, uint rewards1) = _claimLiquidityPositionTokens(position, pair);

            (uint userRewards0, uint userRewards1) = _distributeLiquidityRewards(
                pair,
                rewards0,
                rewards1,
                position.strategy,
                _positionId,
                i,
                position.feeOnRewardsBps
            );

            position.positionManager.decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: position.tokenId,
                    liquidity: position.liquidity,
                    amount0Min: minOutput.token0,
                    amount1Min: minOutput.token1,
                    deadline: block.timestamp
                })
            );

            (uint balance0, uint balance1) = _claimLiquidityPositionTokens(position, pair);

            uint transferAmount0 = balance0 + userRewards0;
            uint transferAmount1 = balance1 + userRewards1;

            pair.token0.safeTransfer(_beneficiary, transferAmount0);
            pair.token1.safeTransfer(_beneficiary, transferAmount1);

            withdrawnAmounts[i] = [transferAmount0, transferAmount1];
        }

        emit PositionClosed(msg.sender, _beneficiary, _positionId, withdrawnAmounts);
    }

    function _claimLiquidityPositionTokens(
        Position memory _position,
        Pair memory _pair
    ) internal returns (uint amount0, uint amount1) {
        uint initialBalance0 = _pair.token0.balanceOf(address(this));
        uint initialBalance1 = _pair.token1.balanceOf(address(this));

        _position.positionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: _position.tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        uint finalBalance0 = _pair.token0.balanceOf(address(this));
        uint finalBalance1 = _pair.token1.balanceOf(address(this));

        amount0 = finalBalance0 - initialBalance0;
        amount1 = finalBalance1 - initialBalance1;
    }

    function _distributeLiquidityRewards(
        Pair memory _pair,
        uint _amount0,
        uint _amount1,
        StrategyIdentifier memory _strategy,
        uint _positionId,
        uint _positionIndex,
        uint16 _feeOnRewardsBps
    ) internal returns (uint userAmount0, uint userAmount1) {
        if (_feeOnRewardsBps == 0)
            return (_amount0, _amount1);

        RewardSplit memory split0 = _calculateLiquidityRewardSplits(_amount0, _feeOnRewardsBps);
        RewardSplit memory split1 = _calculateLiquidityRewardSplits(_amount1, _feeOnRewardsBps);

        rewards[_strategy.strategist][_pair.token0] += split0.strategistAmount;
        rewards[_strategy.strategist][_pair.token1] += split1.strategistAmount;

        // TODO gasopt: test if saving treasury to variable saves gas
        rewards[_getTreasury()][_pair.token0] += split0.treasuryAmount;
        rewards[_getTreasury()][_pair.token1] += split1.treasuryAmount;

        emit Fee(
            msg.sender,
            _strategy.strategist,
            _positionId,
            _positionIndex,
            _pair.token0,
            _pair.token1,
            split0.strategistAmount,
            split1.strategistAmount,
            FeeReceiver.STRATEGIST
        );

        emit Fee(
            msg.sender,
            _getTreasury(),
            _positionId,
            _positionIndex,
            _pair.token0,
            _pair.token1,
            split0.treasuryAmount,
            split1.treasuryAmount,
            FeeReceiver.TREASURY
        );

        return (split0.userAmount, split1.userAmount);
    }

    function _calculateLiquidityRewardSplits(
        uint _amount,
        uint16 _strategyLiquidityFeeBps
    ) internal view returns (RewardSplit memory split) {
        uint totalFees = _amount * _strategyLiquidityFeeBps / 1e4;
        uint strategistAmount = totalFees * _strategistFeeSharingBps / 1e4;

        return RewardSplit({
            userAmount: _amount - totalFees,
            strategistAmount: strategistAmount,
            treasuryAmount: totalFees - strategistAmount
        });
    }

    function _getPairFromLP(
        INonfungiblePositionManager _positionManager,
        uint _tokenId
    ) internal view returns (Pair memory pair) {
        (,, address token0, address token1,,,,,,,,) = _positionManager.positions(_tokenId);

        return Pair(IERC20(token0), IERC20(token1));
    }
}
