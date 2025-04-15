// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;


abstract contract Blacklistable {

    error AccountBlacklisted(address account);
    error AccountNotBlacklisted(address account);

    event Blacklisted(address account, uint256 timestamp);
    event Unblacklisted(address account, uint256 timestamp);


    mapping(address account => bool isBlacklisted) public isBlacklisted;

    
    modifier ifNotBlacklisted(address account) {
        _revertIfBlacklisted(account);
        _;
    }

    constructor(address[] memory blacklistedAccounts) {
        for (uint256 i = 0; i < blacklistedAccounts.length; i++) {
            _blacklist(blacklistedAccounts[i]);
        }
    }


    function _blacklist(address account) internal virtual {
        _revertIfBlacklisted(account);
        isBlacklisted[account] = true;
        emit Blacklisted(account, block.timestamp);
    }


    function _unblacklist(address account) internal virtual {
        _revertIfNotBlacklisted(account);
        isBlacklisted[account] = false;
        emit Unblacklisted(account, block.timestamp);
    }


    function _revertIfBlacklisted(address account) internal view {
        if (isBlacklisted[account]) revert AccountBlacklisted(account);
    }


    function _revertIfNotBlacklisted(address account) internal view {
        if (!isBlacklisted[account]) revert AccountNotBlacklisted(account);
    }





}

