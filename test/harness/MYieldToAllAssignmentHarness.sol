// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { MYieldToAllAssignment } from "../../src/projects/yieldToAllAssignment/MYieldToAllAssignment.sol";

contract MYieldToAllAssignmentHarness is MYieldToAllAssignment {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address mToken, address swapFacility)
        MYieldToAllAssignment(mToken, swapFacility)
    {}

    function initialize(
        string memory name,
        string memory symbol,
        address admin,
        address whitelistManager
    ) public override initializer {
        super.initialize(name, symbol, admin, whitelistManager);
    }

    // --- expose internals for testing ---

    function latestEarnerRateAccrualTimestamp() external view returns (uint40) {
        return _latestEarnerRateAccrualTimestamp();
    }

    function currentEarnerRate() external view returns (uint32) {
        return _currentEarnerRate();
    }

    // --- direct state setters (test-only) ---

    function setAccountOf(address account, uint256 balance, uint112 principal) external {
        MYieldToAllAssignmentStorageStruct storage $ = _getMYieldToAllAssignmentStorageLocation();
        $.balanceOf[account] = balance;
        $.principalOf[account] = principal;
    }

    function setIsEarningEnabled(bool isEarningEnabled_) external {
        _getMYieldToAllAssignmentStorageLocation().isEarningEnabled = isEarningEnabled_;
    }

    function setLatestIndex(uint128 latestIndex_) external {
        _getMYieldToAllAssignmentStorageLocation().latestIndex = latestIndex_;
    }

    function setLatestRate(uint32 latestRate_) external {
        _getMYieldToAllAssignmentStorageLocation().latestRate = latestRate_;
    }

    function setLatestUpdateTimestamp(uint40 latestUpdateTimestamp_) external {
        _getMYieldToAllAssignmentStorageLocation().latestUpdateTimestamp = latestUpdateTimestamp_;
    }

    function setTotalSupply(uint256 totalSupply_) external {
        _getMYieldToAllAssignmentStorageLocation().totalSupply = totalSupply_;
    }

    function setTotalPrincipal(uint112 totalPrincipal_) external {
        _getMYieldToAllAssignmentStorageLocation().totalPrincipal = totalPrincipal_;
    }

    function setWhitelisted(address account, bool allowed) external {
        _getMYieldToAllAssignmentStorageLocation().isWhitelisted[account] = allowed;
    }
}
