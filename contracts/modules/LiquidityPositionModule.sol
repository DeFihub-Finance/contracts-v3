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
        uint16 performanceFeeBps;
    }

    struct DexPosition {
        INonfungiblePositionManager positionManager;
        uint tokenId;
        uint128 liquidity;
        IERC20 token0; // TODO gasopt: check if saving tokens will save gas on withdrawal
        IERC20 token1;
    }

    struct Position {
        StrategyIdentifier strategy;
        uint16 performanceFeeBps;
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

    /// @notice Links a liquidity module position to multiple liquidity positions in decentralized exchanges
    mapping(uint => Position) internal _positions;

    /// @notice user => token => rewards
    mapping(address => mapping(IERC20 => uint)) public rewards;

    uint16 internal _strategistFeeSharingBps;

    event FeeDistributed(
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
    event PositionCollected(address owner, address beneficiary, uint positionId, PairAmounts[] withdrawnAmounts);
    event PositionClosed(address owner, address beneficiary, uint positionId, PairAmounts[] withdrawnAmounts);
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

    function getPositions(uint _positionId) external view returns (Position memory) {
        return _positions[_positionId];
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
        Position storage position = _positions[_positionId];

        position.strategy = params.strategy;
        position.performanceFeeBps = params.performanceFeeBps;

        uint totalAmount = _pullToken(params.inputToken, params.inputAmount);
        uint totalAllocatedAmount;

        for (uint i; i < params.investments.length; ++i) {
            Investment memory investment = params.investments[i];

            totalAllocatedAmount += investment.swapAmount0 + investment.swapAmount1;

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

            position.dexPositions.push(DexPosition({
                positionManager: investment.positionManager,
                tokenId: tokenId,
                liquidity: liquidity,
                token0: investment.token0,
                token1: investment.token1
            }));
        }

        _validateAllocatedAmount(totalAllocatedAmount, totalAmount);
    }

    function _collectPosition(address _beneficiary, uint _positionId, bytes memory) internal override {
        Position memory position = _positions[_positionId];
        DexPosition[] memory dexPositions = position.dexPositions;
        PairAmounts[] memory withdrawnAmounts = new PairAmounts[](dexPositions.length);

        for (uint i; i < dexPositions.length; ++i) {
            DexPosition memory dexPosition = dexPositions[i];
            Pair memory pair = _getPairFromLP(dexPosition.positionManager, dexPosition.tokenId);

            PairAmounts memory userRewards = _distributeLiquidityRewards(
                pair,
                _claimLiquidityPositionTokens(dexPosition, pair),
                position.strategy, // TODO gasopt: test gas cost of passing the entire position as a single argument
                _positionId,
                i,
                position.performanceFeeBps
            );

            pair.token0.safeTransfer(msg.sender, userRewards.amount0);
            pair.token1.safeTransfer(msg.sender, userRewards.amount1);

            withdrawnAmounts[i] = userRewards;
        }

        emit PositionCollected(msg.sender, _beneficiary, _positionId, withdrawnAmounts);
    }

    function _closePosition(address _beneficiary, uint _positionId, bytes memory _data) internal override {
        Position memory position = _positions[_positionId];
        DexPosition[] memory dexPositions = position.dexPositions;
        PairAmounts[] memory withdrawnAmounts = new PairAmounts[](dexPositions.length);
        PairAmounts[] memory minOutputs = abi.decode(_data, (PairAmounts[]));

        for (uint i; i < dexPositions.length; ++i) {
            DexPosition memory dexPosition = dexPositions[i];
            Pair memory pair = _getPairFromLP(dexPosition.positionManager, dexPosition.tokenId);
            PairAmounts memory minOutput = minOutputs.length > i
                ? minOutputs[i]
                : PairAmounts(0, 0);

            PairAmounts memory userRewards = _distributeLiquidityRewards(
                pair,
                _claimLiquidityPositionTokens(dexPosition, pair),
                position.strategy,
                _positionId,
                i,
                position.performanceFeeBps
            );

            dexPosition.positionManager.decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: dexPosition.tokenId,
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

        emit PositionClosed(msg.sender, _beneficiary, _positionId, withdrawnAmounts);
    }

    function _claimLiquidityPositionTokens(
        DexPosition memory _position,
        Pair memory _pair
    ) internal returns (PairAmounts memory amounts) {
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

        return PairAmounts({
            amount0: finalBalance0 - initialBalance0,
            amount1: finalBalance1 - initialBalance1
        });
    }

    function _distributeLiquidityRewards(
        Pair memory _pair,
        PairAmounts memory _amounts,
        StrategyIdentifier memory _strategy,
        uint _positionId,
        uint _positionIndex,
        uint16 _performanceFeeBps
    ) internal returns (PairAmounts memory amounts) {
        if (_performanceFeeBps == 0)
            return _amounts;

        RewardSplit memory split0 = _calculateLiquidityRewardSplits(_amounts.amount0, _performanceFeeBps);
        RewardSplit memory split1 = _calculateLiquidityRewardSplits(_amounts.amount1, _performanceFeeBps);

        rewards[_strategy.strategist][_pair.token0] += split0.strategistAmount;
        rewards[_strategy.strategist][_pair.token1] += split1.strategistAmount;

        // TODO gasopt: test if saving treasury to variable saves gas
        rewards[_getTreasury()][_pair.token0] += split0.treasuryAmount;
        rewards[_getTreasury()][_pair.token1] += split1.treasuryAmount;

        emit FeeDistributed(
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

        emit FeeDistributed(
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

        return PairAmounts({
            amount0: split0.userAmount,
            amount1: split1.userAmount
        });
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
