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
        _mintAndApproveBuyModule(inputAmount, inputToken, account0);

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
    ) internal pure returns (uint[] memory) {
        for (uint i; i < allocatedAmounts.length; ++i) {
            // TODO review min-max bound values based on input token decimals
            allocatedAmounts[i] = bound(allocatedAmounts[i], 0.01 ether, 1e5 ether);
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

    /// @dev Mint token to a recipient and approve it to be spent by the buy module
    /// @param amount Amount to be minted
    /// @param token Token where the amount will be minted and approved
    /// @param recipient Recipient of the minted token
    function _mintAndApproveBuyModule(
        uint amount, 
        TestERC20 token, 
        address recipient
    ) internal {
        _mintAndApprove(amount, token, recipient, address(buyPositionModule));
    }
}