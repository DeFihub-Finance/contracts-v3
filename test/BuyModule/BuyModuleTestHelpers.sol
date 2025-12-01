// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import "forge-std/Test.sol";

import {Constants} from "../utils/Constants.sol";
import {BalanceMapper, BalanceMap} from "../utils/Balances.sol";
import {TestERC20} from "../utils/tokens/TestERC20.sol";
import {SwapHelper} from "../utils/exchange/SwapHelper.sol";
import {PathUniswapV3} from "../utils/exchange/PathUniswapV3.sol";
import {BaseProductTestHelpers} from "../utils/BaseProductTestHelpers.sol";
import {HubRouter} from "../../contracts/libraries/HubRouter.sol";
import {Buy} from "../../contracts/products/Buy.sol";
import {UsePosition} from "../../contracts/abstract/UsePosition.sol";

abstract contract BuyModuleTestHelpers is Test, BaseProductTestHelpers {
    /// @dev Fuzz helper to create a buy position with bounded allocated amounts
    /// @param inputToken Input token of the buy position
    /// @param allocatedAmounts Allocated amounts for each investment
    /// @return tokenId The ID of the created buy position
    function _createFuzzyBuyPosition(
        TestERC20 inputToken,
        uint[] memory allocatedAmounts
    ) internal returns (uint tokenId) {
        _boundAllocatedAmounts(allocatedAmounts, inputToken);

        (
            uint totalAmount,
            Buy.Investment[] memory investments
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
        Buy.Investment[] memory investments
    ) internal returns (uint tokenId) {
        _mintAndApprove(inputAmount, inputToken, account0, address(buy));

        vm.startPrank(account0);

        tokenId = buy.createPosition(
            _encodeBuyInvestParams(inputAmount, inputToken, investments)
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
    ) internal returns (uint totalAmount, Buy.Investment[] memory investments) {
        investments = new Buy.Investment[](allocatedAmounts.length);

        for (uint i; i < allocatedAmounts.length; ++i) {
            uint _allocatedAmount = allocatedAmounts[i];
            TestERC20 buyToken = _getTokenFromNumber(i);

            investments[i] = Buy.Investment({
                swap: _getSwap(_allocatedAmount, inputToken, buyToken, address(buy)),
                token: buyToken,
                allocatedAmount: _allocatedAmount
            });

            totalAmount += _allocatedAmount;
        }
    }

    /// @dev Helper to bound allocated amounts within a reasonable range
    /// @param allocatedAmounts Allocated amounts to be bounded
    /// @param inputToken Input token of the buy position
    function _boundAllocatedAmounts(
        uint[] memory allocatedAmounts,
        TestERC20 inputToken
    ) internal view returns (uint[] memory) {
        vm.assume(allocatedAmounts.length > 0 && allocatedAmounts.length <= MAX_INVESTMENTS);

        for (uint i; i < allocatedAmounts.length; ++i) {
            allocatedAmounts[i] = bound(
                allocatedAmounts[i],
                inputToken.usdToAmount(0.01 ether), // $0.01 in input token amount
                inputToken.usdToAmount(1_000_000 ether) // $1M in input token amount
            );
        }

        return allocatedAmounts;
    }

    /// @dev Helper to encode buy module invest params
    /// @param _inputAmount Input amount of the buy position
    /// @param _inputToken Input token of the buy position
    /// @param _investments Investments of the buy position
    /// @return Bytes of the encoded invest params
    function _encodeBuyInvestParams(
        uint _inputAmount,
        TestERC20 _inputToken,
        Buy.Investment[] memory _investments
    ) internal view returns (bytes memory) {
        return abi.encode(
            Buy.InvestParams({
                inputToken: _inputToken,
                inputAmount: _inputAmount,
                investments: _investments,
                strategy: UsePosition.StrategyIdentifier({
                    strategist: owner,
                    externalRef: 1
                })
            })
        );
    }

    /// @dev Helper to get the withdrawal amounts of a buy position.
    /// @param tokenId ID of the buy position
    /// @return withdrawalAmounts Array of withdrawal amounts
    function _getBuyWithdrawalAmounts(
        uint tokenId
    ) internal view returns (uint[] memory withdrawalAmounts) {
        Buy.Position[] memory positions = buy.getPositions(tokenId);

        withdrawalAmounts = new uint[](positions.length);

        for (uint i; i < positions.length; ++i)
            withdrawalAmounts[i] = positions[i].amount;
    }

    /// @dev Helper to get the position buy amounts grouped by token.
    /// @param tokenId ID of the buy position
    /// @return buyAmountsByToken Buy amounts grouped by token
    function _getPositionAmountsByToken(
        uint tokenId
    ) internal returns (BalanceMap memory buyAmountsByToken) {
        buyAmountsByToken = BalanceMapper.init("buyAmounts");
        Buy.Position[] memory positions = buy.getPositions(tokenId);

        for (uint i; i < positions.length; ++i)
            buyAmountsByToken.add(positions[i].token, positions[i].amount);
    }

    function _getTokenFromNumber(uint _number) internal view returns (TestERC20) {
        return availableTokens[_number % availableTokens.length];
    }
}
