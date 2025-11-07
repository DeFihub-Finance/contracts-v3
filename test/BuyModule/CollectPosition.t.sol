// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import "forge-std/Test.sol";

import {Balances} from "../utils/Balances.sol";
import {BuyModuleTestHelpers} from "../shared/BuyModuleTestHelpers.sol";
import {BuyPositionModule} from "../../contracts/modules/BuyPositionModule.sol";
import {BasePositionModule} from "../../contracts/abstract/BasePositionModule.sol";

contract CollectPosition is Test, BuyModuleTestHelpers {
    function setUp() public {
        deployBaseContracts();
    }

    /// @notice Fuzz test for collecting a buy position with varying investments
    function test_fuzz_collectPosition(uint[] memory allocatedAmounts) public {
        vm.assume(allocatedAmounts.length > 0 && allocatedAmounts.length <= 20);

        uint tokenId = _createFuzzyBuyPosition(usdt, allocatedAmounts);

        uint[] memory userBalancesBefore = Balances.getAccountBalances(account0, availableTokens);
        uint[] memory buyModuleBalancesBefore = Balances.getAccountBalances(address(buyPositionModule), availableTokens);

        vm.startPrank(account0);

        // Must be called right before collectPosition function
        _expectEmitPositionClosedEvent(account0, tokenId);
        buyPositionModule.collectPosition(account0, tokenId, new bytes(0));

        vm.stopPrank();

        uint[] memory userBalancesAfter = Balances.getAccountBalances(account0, availableTokens);

        for (uint i; i < availableTokens.length; ++i) {
            // Assert user received tokens
            assertEq(
                userBalancesAfter[i] - userBalancesBefore[i], 
                buyModuleBalancesBefore[i]
            );
        }
    }

    function test_collectPosition_reverts_notOwner() public {
        uint tokenId = _createBuyPosition(0, usdt, new BuyPositionModule.Investment[](0));

        tokenId += 1; // Ensure tokenId is not owned by account0

        vm.startPrank(account0);

        vm.expectRevert(BasePositionModule.Unauthorized.selector);
        buyPositionModule.collectPosition(account0, tokenId, new bytes(0));
    }

    function _expectEmitPositionClosedEvent(address beneficiary, uint tokenId) internal {
        vm.expectEmit(false, false, false, true, address(buyPositionModule));
        emit BuyPositionModule.PositionClosed(
            beneficiary,
            beneficiary,
            tokenId,
            _getWithdrawnAmounts(buyPositionModule.getPositions(tokenId))
        );
    }

    function _getWithdrawnAmounts(
        BuyPositionModule.Position[] memory positions
    ) internal pure returns (uint[] memory withdrawnAmounts) {
        withdrawnAmounts = new uint[](positions.length);

        for (uint i; i < positions.length; ++i) {
            withdrawnAmounts[i] = positions[i].amount;
        }
    }

    function _getBuyPositionClosedEvent(
        Vm.Log[] memory logs
    ) internal pure returns (address, address, uint, uint[] memory) {
        Vm.Log memory log = _getEvent(logs, BuyPositionModule.PositionClosed.selector);

        return abi.decode(log.data, (address, address, uint, uint[]));
    }

    function _getEvent(
        Vm.Log[] memory logs,
        bytes32 signature
    ) internal pure returns (Vm.Log memory log) {
        for (uint i; i < logs.length; ++i) {
            if (logs[i].topics[0] == signature) {
                return logs[i];
            }
        }

        revert("Event not found");
    }
}