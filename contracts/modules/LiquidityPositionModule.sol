// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {INonfungiblePositionManager} from "../interfaces/external/INonfungiblePositionManager.sol";
import {BasePositionModule} from "../abstract/BasePositionModule.sol";
import {HubRouter} from "../libraries/HubRouter.sol";

contract LiquidityPositionModule is BasePositionModule("DeFihub Liquidity Position", "DHLP") {
    using SafeERC20 for IERC20;

    struct Investment {
        address positionManager;
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

    struct LiquidityPosition {
        address positionManager;
        uint tokenId;
        uint128 liquidity;
        IERC20 token0; // TODO check if saving tokens will save gas on withdrawal
        IERC20 token1;
    }

    /// @notice Links a liquidity module position to multiple liquidity positions in decentralized exchanges
    /// @dev modulePositionId => LiquidityPosition[]
    mapping(uint => LiquidityPosition[]) public _positions;

    function _invest(
        uint _positionId,
        bytes memory _encodedInvestments
    ) internal override {
        Investment[] memory investments = abi.decode(_encodedInvestments, (Investment[]));

        // TODO pull funds

        for (uint i; i < investments.length; ++i) {
            Investment memory investment = investments[i];

            // TODO distribute and validate funds

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

            (uint256 tokenId, uint128 liquidity,,) = INonfungiblePositionManager(investment.positionManager).mint(
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

            _positions[_positionId][i] = LiquidityPosition({
                positionManager: investment.positionManager,
                tokenId: tokenId,
                liquidity: liquidity,
                token0: investment.token0,
                token1: investment.token1
            });
        }
    }
}
