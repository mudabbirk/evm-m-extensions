// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

import { AccessControl } from "../../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

import { IBlacklistable } from "../../interfaces/IBlacklistable.sol";

/**
 * @title Blacklistable
 * @notice A contract that allows for the blacklisting of accounts.
 * @dev This contract is used to prevent certain accounts from interacting with the contract.
 */
abstract contract Blacklistable is IBlacklistable, AccessControl {
    /* ============ Variables ============ */

    /// @inheritdoc IBlacklistable
    bytes32 public constant BLACKLIST_MANAGER_ROLE = keccak256("BLACKLIST_MANAGER_ROLE");

    /// @inheritdoc IBlacklistable
    mapping(address account => bool isBlacklisted) public isBlacklisted;

    /**
     * @notice Constructor that blacklists a list of accounts.
     * @param blacklistManager_ The address of a blacklist manager.
     */
    constructor(address blacklistManager_) {
        if (blacklistManager_ == address(0)) revert ZeroBlacklistManager();
        _grantRole(BLACKLIST_MANAGER_ROLE, blacklistManager_);
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc IBlacklistable
    function blacklist(address account) external onlyRole(BLACKLIST_MANAGER_ROLE) {
        _blacklist(account);
    }

    /// @inheritdoc IBlacklistable
    function blacklistAccounts(address[] calldata accounts) external onlyRole(BLACKLIST_MANAGER_ROLE) {
        for (uint256 i; i < accounts.length; ++i) {
            _blacklist(accounts[i]);
        }
    }

    /// @inheritdoc IBlacklistable
    function unblacklist(address account) external onlyRole(BLACKLIST_MANAGER_ROLE) {
        _unblacklist(account);
    }

    /// @inheritdoc IBlacklistable
    function unblacklistAccounts(address[] calldata accounts) external onlyRole(BLACKLIST_MANAGER_ROLE) {
        for (uint256 i; i < accounts.length; ++i) {
            _unblacklist(accounts[i]);
        }
    }

    /* ============ Internal Interactive Functions ============ */

    /**
     * @notice Internal function that blacklists an account.
     * @param account The account to blacklist.
     */
    function _blacklist(address account) internal virtual {
        _revertIfBlacklisted(account);

        isBlacklisted[account] = true;

        emit Blacklisted(account, block.timestamp);
    }

    /**
     * @notice Internal function that unblacklists an account.
     * @param account The account to unblacklist.
     */
    function _unblacklist(address account) internal {
        if (!isBlacklisted[account]) revert AccountNotBlacklisted(account);

        isBlacklisted[account] = false;

        emit Unblacklisted(account, block.timestamp);
    }

    /* ============ Internal View/Pure Functions ============ */

    /**
     * @notice Internal function that reverts if an account is blacklisted.
     * @param account The account to check.
     */
    function _revertIfBlacklisted(address account) internal view {
        if (isBlacklisted[account]) revert AccountBlacklisted(account);
    }
}
