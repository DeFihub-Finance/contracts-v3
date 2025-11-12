// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import "forge-std/Test.sol";

import {Constants} from "../utils/Constants.sol";
import {Deployers} from "../utils/Deployers.sol";
import {SwapHelper} from "../utils/SwapHelper.sol";
import {PathUniswapV3} from "../utils/PathUniswapV3.sol";
import {TestERC20} from "../../contracts/test/TestERC20.sol";
import {HubRouter} from "../../contracts/libraries/HubRouter.sol";
import {BuyPositionModule} from "../../contracts/modules/BuyPositionModule.sol";
import {BasePositionModule} from "../../contracts/abstract/BasePositionModule.sol";

abstract contract BuyModuleTestHelpers is Test, Deployers {
    /// Maximum number of investments in a buy position for fuzz testing
    uint8 internal immutable MAX_INVESTMENTS = 20;

    /// @dev Fuzz helper to create a buy position with bounded allocated amounts
    /// @param inputToken Input token of the buy position
    /// @param allocatedAmounts Allocated amounts for each investment
    /// @return tokenId The ID of the created buy position
    function _createFuzzyBuyPosition(
        TestERC20 inputToken,
        uint[] memory allocatedAmounts
    ) internal returns (uint tokenId) {
        _boundAllocatedAmounts(allocatedAmounts);

        (   
            uint totalAmount,
            BuyPositionModule.Investment[] memory investments
        ) = _createBuyInvestments(inputToken, allocatedAmounts);

        return _createBuyPosition(totalAmount, inputToken, investments);
    }

    /// @dev Helper to create a buy position
    /// @param inputAmount Input amount of the buy position
    /// @param inputToken Input token of the buy position
    /// @param investments Investments of the buy position
    /// @return tokenId The ID of the created buy position
    function _createBuyPosition(
        uint inputAmount,
        TestERC20 inputToken,
        BuyPositionModule.Investment[] memory investments
    ) internal returns (uint tokenId) {
        _mintAndApprove(inputAmount, inputToken, account0, address(buyPositionModule));

        vm.startPrank(account0);
        
        tokenId = buyPositionModule.createPosition(
            _getEncodedBuyInvestParams(inputAmount, inputToken, investments)
        );

        vm.stopPrank();
    }

    /// @dev Helper to create buy investments from allocated amounts
    /// @param inputToken Input token of the buy position
    /// @param allocatedAmounts Allocated amounts for each investment
    /// @return totalAmount Total input amount required for the buy position
    /// @return investments Investments of the buy position
    function _createBuyInvestments(
        TestERC20 inputToken,
        uint[] memory allocatedAmounts
    ) internal returns (uint totalAmount, BuyPositionModule.Investment[] memory investments) {
        investments = new BuyPositionModule.Investment[](allocatedAmounts.length);

        for (uint i; i < allocatedAmounts.length; ++i) {
            uint _allocatedAmount = allocatedAmounts[i];
            TestERC20 buyToken = availableTokens[i % availableTokens.length];

            investments[i] = BuyPositionModule.Investment({
                swap: _getSwap(_allocatedAmount, inputToken, buyToken),
                token: buyToken,
                allocatedAmount: _allocatedAmount
            });

            totalAmount += _allocatedAmount;
        }
    }

    /// @dev Helper to bound allocated amounts within a reasonable range
    /// @param allocatedAmounts Allocated amounts to be bounded
    function _boundAllocatedAmounts(
        uint[] memory allocatedAmounts
    ) internal view returns (uint[] memory) {
        vm.assume(allocatedAmounts.length > 0 && allocatedAmounts.length <= MAX_INVESTMENTS);

        for (uint i; i < allocatedAmounts.length; ++i) {
            allocatedAmounts[i] = bound(
                allocatedAmounts[i],
                1e5, // $0,1 in USDC
                1e6 * 10 ** usdc.decimals() // 1M USDC
            );
        }

        return allocatedAmounts;
    }

    /// @dev Helper to encode buy module invest params
    /// @param _inputAmount Input amount of the buy position
    /// @param _inputToken Input token of the buy position
    /// @param _investments Investments of the buy position
    /// @return Bytes of the encoded invest params
    function _getEncodedBuyInvestParams(
        uint _inputAmount,
        TestERC20 _inputToken,
        BuyPositionModule.Investment[] memory _investments
    ) internal view returns (bytes memory) {
        return abi.encode(
            BuyPositionModule.InvestParams({
                inputToken: _inputToken,
                inputAmount: _inputAmount,
                investments: _investments,
                strategy: BasePositionModule.StrategyIdentifier({
                    strategist: owner,
                    externalRef: 1
                })
            })
        );
    }

    /// @dev Helper to get a HubRouter swap
    /// @param _amount Amount to be swapped
    /// @param _inputToken Input token of the swap
    /// @param _outputToken Output token of the swap
    /// @return A HubSwap struct data
    function _getSwap(
        uint _amount,
        TestERC20 _inputToken,
        TestERC20 _outputToken
    ) internal returns (HubRouter.HubSwap memory) {
        return SwapHelper.getHubSwapExactInput(
            SwapHelper.GetHubSwapParams({
                slippageBps: Constants.ONE_PERCENT_BPS,
                recipient: address(buyPositionModule),
                amount: _amount,
                inputToken: _inputToken,
                outputToken: _outputToken,
                quoter: quoterUniV3,
                router: universalRouter,
                path: PathUniswapV3.init(_inputToken).addHop(Constants.FEE_MEDIUM, _outputToken)
            })
        );
    }

    /// @dev Helper to get the withdrawal amounts of a buy position.
    /// @param tokenId ID of the buy position
    /// @return withdrawalAmounts Array of withdrawal amounts
    function _getBuyWithdrawalAmounts(
        uint tokenId
    ) internal view returns (uint[] memory withdrawalAmounts) {
        BuyPositionModule.Position[] memory positions = buyPositionModule
            .getPositions(tokenId);

        withdrawalAmounts = new uint[](positions.length);

        for (uint i; i < positions.length; ++i) {
            withdrawalAmounts[i] = positions[i].amount;
        }
    }

    /// @dev Normalizes an arbitrary number with intrinsic precision to ether.
    /// @param value The value to normalize
    /// @param decimals The decimals of the value
    /// @return The value normalized to 18 decimals
    function _normalizeToEther(
        uint value,
        uint8 decimals
    ) internal pure returns (uint) {
        return decimals == 18 ? value : value * 10 ** (18 - decimals);
    }
}
