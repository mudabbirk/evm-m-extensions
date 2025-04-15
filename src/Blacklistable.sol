// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

/**
 * @title Blacklistable
 * @notice A contract that allows for the blacklisting of accounts.
 * @dev This contract is used to prevent certain accounts from interacting with the contract.
 */
abstract contract Blacklistable {

    /* ============ Errors ============ */
    /// @notice Emitted when a blacklisted account attempts to interact with the contract.
    error AccountBlacklisted(address account);
    // @notice Emitted when trying to unblacklist a non-blacklisted account.
    error AccountNotBlacklisted(address account);

    /* ============ Events ============ */
    /// @notice Emitted when an account is blacklisted.
    event Blacklisted(address account, uint256 timestamp);
    /// @notice Emitted when an account is unblacklisted.
    event Unblacklisted(address account, uint256 timestamp);

    /* ============ Storage ============ */
    /// @notice A mapping of accounts to their blacklist status.
    mapping(address account => bool isBlacklisted) public isBlacklisted;

    /* ============ Modifiers ============ */
    /// @notice Modifier that reverts if an account is blacklisted.
    modifier ifNotBlacklisted(address account) {
        _revertIfBlacklisted(account);
        _;
    }

    /**
     * @notice Constructor that blacklists a list of accounts.
     * @param blacklistedAccounts The list of accounts to blacklist.
     */
    constructor(address[] memory blacklistedAccounts) {
        for (uint256 i = 0; i < blacklistedAccounts.length; i++) {
            _blacklist(blacklistedAccounts[i]);
        }
    }

    /* ============ Internal Functions ============ */

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
    function _unblacklist(address account) internal virtual {
        _revertIfNotBlacklisted(account);
        isBlacklisted[account] = false;
        emit Unblacklisted(account, block.timestamp);
    }


    /**
     * @notice Internal function that reverts if an account is blacklisted.
     * @param account The account to check.
     */
    function _revertIfBlacklisted(address account) internal view {
        if (isBlacklisted[account]) revert AccountBlacklisted(account);
    }

    /**
     * @notice Internal function that reverts if an account is not blacklisted.
     * @param account The account to check.
     */
    function _revertIfNotBlacklisted(address account) internal view {
        if (!isBlacklisted[account]) revert AccountNotBlacklisted(account);
    }

}

