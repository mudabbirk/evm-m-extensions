// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

import { IERC20 } from "../lib/common/src/interfaces/IERC20.sol";

import { IMTokenLike } from "./interfaces/IMTokenLike.sol";
import { IMYieldToOne } from "./interfaces/IMYieldToOne.sol";

import { MExtension } from "./MExtension.sol";

import { Blacklistable } from "./Blacklistable.sol";

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title  ERC20 Token contract for wrapping M into a non-rebasing token with claimable yields.
 * @author M^0 Labs
 */
contract MYieldToOne is IMYieldToOne, MExtension, Blacklistable, AccessControl {
    
    /* ============ Variables ============ */

    bytes32 public constant BLACKLISTER_ROLE = keccak256("BLACKLISTER_ROLE");

    bytes32 public constant RECIPIENT_SETTER_ROLE = keccak256("RECIPIENT_SETTER_ROLE");

    /// @inheritdoc IMYieldToOne
    address public yieldRecipient;

    /// @inheritdoc IERC20
    mapping(address account => uint256 balance) public balanceOf;

    /// @inheritdoc IERC20
    uint256 public totalSupply;

    /* ============ Constructor ============ */

    /**
     * @dev   Constructs the M extension token with yield claimable by a single recipient.
     * @param mToken            The address of an M Token.
     * @param registrar         The address of a registrar.
     * @param yieldRecipient_   The address of an yield destination.
     */
    constructor(
        address mToken,
        address registrar,
        address yieldRecipient_,
        address defaultAdmin,
        address blacklister,
        address recipientSetter,
        address[] memory blacklistedAccounts
    ) MExtension("HALO USD", "HUSD", mToken, registrar) Blacklistable(blacklistedAccounts) {
        if ((yieldRecipient = yieldRecipient_) == address(0)) revert ZeroYieldRecipient();
        if (blacklister == address(0)) revert ZeroBlacklister();
        if (recipientSetter == address(0)) revert ZeroRecipientSetter();
        if (defaultAdmin == address(0)) revert ZeroDefaultAdmin();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(BLACKLISTER_ROLE, blacklister);
        _grantRole(RECIPIENT_SETTER_ROLE, recipientSetter);
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc IMYieldToOne
    function claimYield() external returns (uint256) {
        uint256 yield_ = yield();

        if (yield_ == 0) revert NoYield();

        emit YieldClaimed(yield_);

        // NOTE: The behavior of `IMTokenLike.transfer` is known, so its return can be ignored.
        IMTokenLike(mToken).transfer(yieldRecipient, yield_);

        return yield_;
    }

    function blacklist(address account) external onlyRole(BLACKLISTER_ROLE) {
        _blacklist(account);
    }

    function unblacklist(address account) external onlyRole(BLACKLISTER_ROLE) {
        _unblacklist(account);
    }

    function setYieldRecipient(address account) external onlyRole(RECIPIENT_SETTER_ROLE) {
        if (account == address(0)) revert ZeroYieldRecipient();
        yieldRecipient = account;
        emit YieldRecipientSet(account);
    }


    /* ============ View/Pure Functions ============ */

    /// @inheritdoc IMYieldToOne
    function yield() public view returns (uint256) {
        unchecked {
            uint256 balance_ = _mBalanceOf(address(this));
            return balance_ > totalSupply ? balance_ - totalSupply : 0;
        }
    }

    /* ============ Internal Interactive Functions ============ */

    /**
     * @dev   Mints `amount` tokens to `recipient`.
     * @param recipient The address whose account balance will be incremented.
     * @param amount    The present amount of tokens to mint.
     */
    function _mint(address recipient, uint256 amount) internal override ifNotBlacklisted(recipient) {
        _revertIfInsufficientAmount(amount);
        _revertIfInvalidRecipient(recipient);

        unchecked {
            balanceOf[recipient] += amount;
            totalSupply += amount;
        }

        emit Transfer(address(0), recipient, amount);
    }

    /**
     * @dev   Burns `amount` tokens from `account`.
     * @param account The address whose account balance will be decremented.
     * @param amount  The present amount of tokens to burn.
     */
    function _burn(address account, uint256 amount) internal override ifNotBlacklisted(account) {
        _revertIfInsufficientAmount(amount);

        uint256 balance_ = balanceOf[account];

        if (balance_ < amount) revert InsufficientBalance(account, balance_, amount);

        unchecked {
            balanceOf[account] = balance_ - amount;
            totalSupply -= amount;
        }

        emit Transfer(account, address(0), amount);
    }

    /**
     * @dev   Internal ERC20 transfer function that needs to be implemented by the inheriting contract.
     * @param sender    The sender's address.
     * @param recipient The recipient's address.
     * @param amount    The amount to be transferred.
     */
    function _transfer(address sender, address recipient, uint256 amount) internal override ifNotBlacklisted(sender) ifNotBlacklisted(recipient) ifNotBlacklisted(msg.sender) {
        _revertIfInvalidRecipient(recipient);

        emit Transfer(sender, recipient, amount);

        if (amount == 0) return;

        // NOTE: Can be `unchecked` because `_transfer` already checked for insufficient sender balance.
        unchecked {
            balanceOf[sender] -= amount;
            balanceOf[recipient] += amount;
        }
    }

    function _approve(address account_, address spender_, uint256 amount_) internal override ifNotBlacklisted(account_) ifNotBlacklisted(spender_) {
        super._approve(account_, spender_, amount_);
    }

    /* ============ Internal View/Pure Functions ============ */

    /**
     * @dev    Returns the M Token balance of `account`.
     * @param  account The account being queried.
     * @return balance_ The M Token balance of the account.
     */
    function _mBalanceOf(address account) internal view returns (uint256) {
        return IMTokenLike(mToken).balanceOf(account);
    }

    /**
     * @dev   Reverts if `amount` is equal to 0.
     * @param amount Amount of token.
     */
    function _revertIfInsufficientAmount(uint256 amount) internal pure {
        if (amount == 0) revert InsufficientAmount(amount);
    }

    /**
     * @dev   Reverts if `account` is address(0).
     * @param account Address of an account.
     */
    function _revertIfInvalidRecipient(address account) internal pure {
        if (account == address(0)) revert InvalidRecipient(account);
    }
}
