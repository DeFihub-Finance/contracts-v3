// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import "forge-std/Test.sol";

import {TestERC20} from "../utils/tokens/TestERC20.sol";
import {BaseProductTestHelpers} from "../utils/BaseProductTestHelpers.sol";
import {DollarCostAverage as DCA} from "../../contracts/products/DollarCostAverage.sol";

struct CreateInvestmentParams {
    uint32 swaps;
    uint allocatedAmount;
}

abstract contract DCATestHelpers is Test, BaseProductTestHelpers {
    /// @dev Helper to create a DCA position
    /// @param inputAmount Input amount of the DCA position
    /// @param inputToken Input token of the DCA position
    /// @param investments Investments of the DCA position
    /// @return tokenId The ID of the created DCA position
    function _createDCAPosition(
        uint inputAmount,
        TestERC20 inputToken,
        DCA.Investment[] memory investments
    ) internal returns (uint tokenId) {
        _mintAndApprove(inputAmount, inputToken, account0, address(dca));

        vm.startPrank(account0);

        tokenId = dca.createPosition(_encodeDCAInvestParams(inputAmount, inputToken, investments));

        vm.stopPrank();
    }

    /// @dev Helper to create DCA investments
    /// @param inputToken Input token of the DCA position
    /// @param params Array of CreateInvestmentParams struct
    /// @return totalAmount Total input amount required for the DCA position
    /// @return investments Investments of the DCA position
    function _createDCAInvestments(
        TestERC20 inputToken,
        CreateInvestmentParams[] memory params
    ) internal returns (uint totalAmount, DCA.Investment[] memory investments) {
        investments = new DCA.Investment[](params.length);

        for (uint i; i < params.length; ++i) {
            CreateInvestmentParams memory investmentParams = params[i];
            uint allocatedAmount = investmentParams.allocatedAmount;
            DCA.PoolIdentifier memory poolId = _getPoolFromNumber(i);

            investments[i] = DCA.Investment({
                inputAmount: allocatedAmount,
                swaps: investmentParams.swaps,
                swap: _getSwap(
                    allocatedAmount,
                    inputToken,
                    TestERC20(address(poolId.inputToken)),
                    address(dca)
                ),
                poolId: DCA.PoolIdentifier({
                    inputToken: poolId.inputToken,
                    outputToken: poolId.outputToken
                })
            });

            totalAmount += allocatedAmount;
        }
    }

    /// @dev Helper to bound the CreateInvestmentParams struct
    /// @param inputToken Input token of the DCA position
    /// @param params Array of CreateInvestmentParams struct to bound
    /// @return Array of bounded CreateInvestmentParams struct
    function _boundCreateInvestmentParams(
        TestERC20 inputToken,
        CreateInvestmentParams[] memory params
    ) internal view returns (CreateInvestmentParams[] memory) {
        uint totalInvestments = params.length;

        vm.assume(totalInvestments > 0 && totalInvestments <= MAX_INVESTMENTS);

        for (uint i; i < totalInvestments; ++i) {
            CreateInvestmentParams memory investmentParams = params[i];

            investmentParams.allocatedAmount = bound(
                investmentParams.allocatedAmount,
                inputToken.usdToAmount(0.01 ether), // $0.01 in input token amount
                inputToken.usdToAmount(1_000_000 ether) // $1M in input token amount
            );

            investmentParams.swaps = uint32(bound(investmentParams.swaps, 1, 365));
        }

        return params;
    }

    /// @dev Helper to encode DCA product invest params
    /// @param _inputAmount Input amount of the DCA position
    /// @param _inputToken Input token of the DCA position
    /// @param _investments Investments of the DCA position
    /// @return Bytes of the encoded invest params
    function _encodeDCAInvestParams(
        uint _inputAmount,
        TestERC20 _inputToken,
        DCA.Investment[] memory _investments
    ) internal pure returns (bytes memory) {
        return abi.encode(
            DCA.InvestParams({
                inputToken: _inputToken,
                inputAmount: _inputAmount,
                investments: _investments
            })
        );
    }

    /// @dev Helper to get pool info
    /// @param poolId Pool identifier of the DCA position
    /// @return performedSwaps Number of performed swaps in the pool
    /// @return nextSwapAmount Pool next swap amount
    /// @return lastSwapTimestamp Pool last swap timestamp
    function _getPoolInfo(
        DCA.PoolIdentifier memory poolId
    ) internal view returns (uint32 performedSwaps, uint nextSwapAmount, uint lastSwapTimestamp) {
        return dca.pools(poolId.inputToken, poolId.outputToken);
    }

    /// @dev Helper to get a Pool Identifier from a number
    /// The number is then mapped to the input and output tokens of the pool.
    /// @param _number Number to get the pool from
    /// @return Pool identifier
    function _getPoolFromNumber(uint _number) internal view returns (DCA.PoolIdentifier memory) {
        return DCA.PoolIdentifier({
            inputToken: _getTokenFromNumber(_number),
            outputToken: _getTokenFromNumber(_number + 1)
        });
    }
}
