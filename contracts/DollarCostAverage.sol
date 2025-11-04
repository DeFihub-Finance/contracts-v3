// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {HubRouter} from "./libraries/HubRouter.sol";
import {UseTreasury} from "./abstract/UseTreasury.sol";
import {BasePositionModule} from "./abstract/BasePositionModule.sol";

contract DollarCostAverage is BasePositionModule("DeFihub DCA Position", "DHDCAP"), UseTreasury {
    using SafeERC20 for IERC20;

    struct PoolIdentifier {
        IERC20 inputToken;
        IERC20 outputToken;

        uint32 interval;
    }

    struct Position {
        uint32 swaps;
        uint32 finalSwap;
        uint32 lastUpdateSwap;

        PoolIdentifier poolId;
        uint amountPerSwap;
    }

    struct Pool {
        uint32 performedSwaps;

        uint nextSwapAmount;
        uint lastSwapTimestamp;

        mapping(uint32 => uint) endingPositionDeduction;
        mapping(uint32 => uint) accruedSwapQuote;
    }

    struct SwapParams {
        PoolIdentifier poolId;
        HubRouter.HubSwap swap;
    }

    struct CreatePositionParams {
        PoolIdentifier poolId;
        uint32 swaps;
        uint amount;
    }

    uint32 public constant DAILY_INTERVAL = 1 days;
    uint32 public constant WEEKLY_INTERVAL = 1 weeks;
    uint32 public constant MONTHLY_INTERVAL = 4 weeks;

    uint16 public constant MAX_SWAP_FEE_BPS = 100; // 1%

    // TODO gasopt: test if changing to uint256 saves gas by avoiding type conversions
    uint128 public constant SWAP_QUOTE_PRECISION = 1e18;

    // @dev inputToken => outputToken => interval => boolean
    mapping(IERC20 => mapping(IERC20 => mapping(uint32 => Pool))) public _pools;

    mapping(uint => Position[]) internal _tokenToPositions;

    address public swapper;
    uint16 public swapFeeBps;

    event PoolCreated(uint poolId, IERC20 inputToken, IERC20 outputToken, uint32 interval);
    event PositionCreated(address user, uint poolId, uint tokenId, uint swaps, uint amountPerSwap, uint finalSwap);
//    event Swap(uint poolId, uint amountIn, uint amountOut); // TODO maybe add extra data
    event SwapperUpdated(address swapper);
    event SwapFeeUpdated(uint16 swapFeeBps);

    error InvalidInterval();
    error InvalidAddress();
    error InvalidAmount();
    error InvalidNumberOfSwaps();
    error CallerIsNotSwapper();
    error TooEarlyToSwap();
    error NoTokensToSwap();

    constructor(
        address _owner,
        address _treasury,
        address _swapper,
        uint16 _swapFeeBps
    ) UseTreasury(_owner, _treasury) {
        _setSwapper(_swapper);
        _setSwapFeeBps(_swapFeeBps);
    }

    function swap(SwapParams[] calldata _swaps) external {
        if (msg.sender != swapper)
            revert CallerIsNotSwapper();

        uint timestamp = block.timestamp;

        for (uint i; i < _swaps.length; ++i) {
            SwapParams memory swapParam = _swaps[i];

            Pool storage pool = _getPool(swapParam.poolId);

            if (timestamp < pool.lastSwapTimestamp + swapParam.poolId.interval)
                revert TooEarlyToSwap();

            uint inputTokenAmount = pool.nextSwapAmount;

            if (inputTokenAmount == 0)
                revert NoTokensToSwap();

            uint outputTokenAmount = HubRouter.execute(
                swapParam.swap,
                swapParam.poolId.inputToken,
                swapParam.poolId.outputToken,
                inputTokenAmount
            );

            // TODO check slippage against oracle

            uint swapQuote = (outputTokenAmount * SWAP_QUOTE_PRECISION) / inputTokenAmount;
            mapping(uint32 => uint) storage poolAccruedQuotes = pool.accruedSwapQuote;

            poolAccruedQuotes[pool.performedSwaps + 1] = poolAccruedQuotes[pool.performedSwaps] + swapQuote;

            pool.performedSwaps += 1;
            pool.nextSwapAmount -= pool.endingPositionDeduction[pool.performedSwaps + 1];
            pool.lastSwapTimestamp = timestamp;

            // TODO event
//            emit Swap(inputTokenAmount, outputTokenAmount);
        }
    }

    function getPositions(uint _tokenId) external virtual view returns (Position[] memory) {
        return _tokenToPositions[_tokenId];
    }

    function _createPosition(
        uint _tokenId,
        bytes memory _encodedInvestments
    ) internal override {
        CreatePositionParams[] memory params = abi.decode(_encodedInvestments, (CreatePositionParams[]));

        for (uint i; i < params.length; ++i) {
            CreatePositionParams memory param = params[i];

            if (param.swaps == 0)
                revert InvalidNumberOfSwaps();

            if (param.amount == 0)
                revert InvalidAmount();

            Pool storage pool = _getPool(param.poolId);
            Position[] storage positions = _tokenToPositions[_tokenId];

            uint amountPerSwap = param.amount / param.swaps;
            uint32 finalSwap = pool.performedSwaps + param.swaps;

            pool.nextSwapAmount += amountPerSwap;
            pool.endingPositionDeduction[finalSwap + 1] += amountPerSwap;

            positions.push(
                Position({
                    swaps: param.swaps,
                    amountPerSwap: amountPerSwap,
                    poolId: param.poolId,
                    finalSwap: finalSwap,
                    lastUpdateSwap: pool.performedSwaps
                })
            );
        }

//        emit PositionCreated(msg.sender, _poolId, positionId, _swaps, amountPerSwap, finalSwap);
    }

    function _closePosition(address _beneficiary, uint _tokenId, bytes memory) internal override {
        Position[] storage positions = _tokenToPositions[_tokenId];
        // TODO emit event with withdrawn amounts

        for (uint i; i < positions.length; ++i) {
            Position storage position = positions[_tokenId];
            Pool storage pool = _getPool(position.poolId);

            uint inputTokenAmount = _calculateInputTokenBalance(position, pool.performedSwaps);
            uint outputTokenAmount = _calculateOutputTokenBalance(position, pool);

            if (position.finalSwap > pool.performedSwaps) {
                pool.nextSwapAmount -= position.amountPerSwap;
                pool.endingPositionDeduction[position.finalSwap + 1] -= position.amountPerSwap;
            }

            position.lastUpdateSwap = pool.performedSwaps;
            position.amountPerSwap = 0;

            if (inputTokenAmount > 0)
                position.poolId.inputToken.safeTransfer(_beneficiary, inputTokenAmount);

            if (outputTokenAmount > 0)
                position.poolId.outputToken.safeTransfer(_beneficiary, outputTokenAmount);
        }

//        emit PositionClosed(msg.sender, _positionId, inputTokenAmount, outputTokenAmount);
    }

    function _collectPosition(address _beneficiary, uint _tokenId, bytes memory) internal override {
        Position[] storage positions = _tokenToPositions[_tokenId];
        // TODO emit event with withdrawn amounts

        for (uint i; i < positions.length; ++i) {
            Position storage position = positions[_tokenId];
            Pool storage pool = _getPool(position.poolId); // TODO gasopt: check if cheaper removing mappings from this struct so it can be memory instead of storage

            uint outputTokenAmount = _calculateOutputTokenBalance(position, pool);

            position.lastUpdateSwap = pool.performedSwaps;

            position.poolId.outputToken.safeTransfer(_beneficiary, outputTokenAmount);
        }

//        emit PositionCollected(msg.sender, _positionId, outputTokenAmount);
    }

    function _calculateInputTokenBalance(
        Position memory _position,
        uint _performedSwaps
    ) internal pure returns (uint) {
        if (_position.finalSwap < _performedSwaps)
            return 0;

        return (_position.finalSwap - _performedSwaps) * _position.amountPerSwap;
    }

    function _calculateOutputTokenBalance(
        Position memory _position,
        Pool storage _pool // TODO if pool is storage this function can be pure instead of view
    ) internal view returns (uint) {
        uint32 swapToConsider = _pool.performedSwaps > _position.finalSwap
            ? _position.finalSwap
            : _pool.performedSwaps;

        // @dev This means that the last interaction was happened before a new swap happened
        // and the user already withdrawn all the output tokens
        if (_position.lastUpdateSwap > swapToConsider)
            return 0;

        uint quoteAtMostRecentSwap = _pool.accruedSwapQuote[swapToConsider];
        uint quoteAtLastUpdate = _pool.accruedSwapQuote[_position.lastUpdateSwap];
        uint positionAccumulatedRatio = quoteAtMostRecentSwap - quoteAtLastUpdate;

        return positionAccumulatedRatio * _position.amountPerSwap / SWAP_QUOTE_PRECISION;
    }

    function _getPool(PoolIdentifier memory _id) internal view returns (Pool storage) {
        return _pools[_id.inputToken][_id.outputToken][_id.interval];
    }

    function setSwapper(address _swapper) external onlyOwner {
        _setSwapper(_swapper);
    }

    function _setSwapper(address _swapper) internal {
        if (_swapper == address(0))
            revert InvalidAddress();

        swapper = _swapper;

        emit SwapperUpdated(_swapper);
    }

    function setSwapFeeBps(uint16 _swapFeeBps) external onlyOwner {
        _setSwapFeeBps(_swapFeeBps);
    }

    function _setSwapFeeBps(uint16 _swapFeeBps) internal {
        if (_swapFeeBps > MAX_SWAP_FEE_BPS)
            revert InvalidAmount();

        swapFeeBps = _swapFeeBps;

        emit SwapFeeUpdated(_swapFeeBps);
    }
}