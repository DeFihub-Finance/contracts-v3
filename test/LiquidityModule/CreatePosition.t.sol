// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {TestERC20} from "../utils/TestERC20.sol";
import {UniswapV3Helper} from "../utils/UniswapV3Helper.sol";
import {LiquidityTestHelpers, CreateInvestmentParams} from "./LiquidityTestHelpers.sol";
import {Liquidity} from "../../contracts/products/Liquidity.sol";
import {UsePosition} from "../../contracts/abstract/UsePosition.sol";

contract CreatePositionTest is Test, LiquidityTestHelpers {
    function setUp() public {
        deployBaseContracts();
    }

    function test_fuzz_createPosition(
        uint8 rand,
        CreateInvestmentParams[] memory params
    ) public {
        TestERC20 inputToken = availableTokens[rand % availableTokens.length];

        (
            uint totalAmount,
            Liquidity.Investment[] memory investments
        ) = _createLiquidityInvestments(
            inputToken,
            _boundCreateInvestmentParams(inputToken, params)
        );

        uint tokenId = _createLiquidityPosition(totalAmount, inputToken, investments);
        Liquidity.Position memory position = liquidity.getPositions(tokenId);
        Liquidity.DexPosition[] memory dexPositions = position.dexPositions;

        assertEq(tokenId, 0);
        assertEq(liquidity.ownerOf(tokenId), account0);
        assertEq(dexPositions.length, investments.length);
        assertEq(position.strategistPerformanceFeeBps, 100);

        for (uint i; i < dexPositions.length; ++i) {
            Liquidity.Investment memory investment = investments[i];
            Liquidity.DexPosition memory dexPosition = dexPositions[i];

            assertGt(dexPosition.liquidity, 0);

            (uint amount0, uint amount1) = UniswapV3Helper.getPositionTokenAmounts(
                dexPosition.lpTokenId,
                factoryUniV3,
                dexPosition.positionManager
            );

            TestERC20 token0 = TestERC20(address(dexPosition.token0));
            TestERC20 token1 = TestERC20(address(dexPosition.token1));

            // Compare price impact values in USD
            assertApproxEqRel(
                token0.amountToUsd(amount0) + token1.amountToUsd(amount1),
                inputToken.amountToUsd(investment.swapAmount0 + investment.swapAmount1),
                0.05 ether // 5% price impact tolerance
            );
        }
    }

    function test_createPosition_emptyInvestments() public {
        uint tokenId = _createLiquidityPosition(0, usdc, new Liquidity.Investment[](0));

        Liquidity.Position memory position = liquidity.getPositions(tokenId);

        assertEq(tokenId, 0);
        assertEq(position.dexPositions.length, 0);
        assertEq(liquidity.ownerOf(tokenId), account0);
    }

    function test_createPosition_reverts_feeTooHigh() public {
        uint16 performanceFee = 1_501; // 1 bps above max

        vm.startPrank(account0);

        vm.expectRevert(Liquidity.FeeTooHigh.selector);

        liquidity.createPosition(
            abi.encode(
                Liquidity.InvestParams({
                    inputToken: usdc,
                    inputAmount: 0,
                    investments: new Liquidity.Investment[](0),
                    strategistPerformanceFeeBps: performanceFee,
                    strategy: UsePosition.StrategyIdentifier({
                        strategist: owner,
                        externalRef: 1
                    })
                })
            )
        );
    }

    function test_createPosition_reverts_inputAmountLessThanTotalAllocations() public {
        CreateInvestmentParams[] memory investmentParams = new CreateInvestmentParams[](availablePools.length);

        for (uint i; i < investmentParams.length; ++i) {
            IUniswapV3Pool pool = _getPoolFromNumber(i);

            int24 tickSpacing = pool.tickSpacing();
            (uint160 sqrtPriceX96, int24 currentTick,,,,,) = pool.slot0();

            // Position must be in range, otherwise it will revert with insufficient balance
            int24 _tickLower = UniswapV3Helper.alignTick(currentTick - tickSpacing, tickSpacing);
            int24 _tickUpper = UniswapV3Helper.alignTick(currentTick + tickSpacing, tickSpacing);

            investmentParams[i] = CreateInvestmentParams({
                tickLower: _tickLower,
                tickUpper: _tickUpper,
                allocatedAmount: usdc.usdToAmount(10 ether), // $10 in USDC
                liquidityDeltaMax: _getMaxLiquidityFromRange(
                    _tickLower,
                    _tickUpper,
                    tickSpacing,
                    sqrtPriceX96
                )
            });
        }

        (
            uint inputAmount,
            Liquidity.Investment[] memory investments
        ) = _createLiquidityInvestments(usdc, investmentParams);

        inputAmount -= 1; // Subtract to make it less than total allocations

        _mintAndApprove(inputAmount, usdc, account0, address(liquidity));

        vm.startPrank(account0);

        vm.expectRevert(UsePosition.InvalidAllocatedAmount.selector);
        liquidity.createPosition(_encodeLiquidityInvestParams(usdc, inputAmount, investments));
    }

    function test_createPosition_reverts_totalAllocationsLessThanTolerance() public {
        uint inputAmount = 1 ether;

        _mintAndApprove(inputAmount, usdc, account0, address(liquidity));

        vm.startPrank(account0);

        vm.expectRevert(UsePosition.InvalidAllocatedAmount.selector);

        liquidity.createPosition(
            _encodeLiquidityInvestParams(usdc, inputAmount, new Liquidity.Investment[](0))
        );
    }
}
