// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

import { IERC20 } from "../lib/common/src/interfaces/IERC20.sol";

import { IMTokenLike } from "./interfaces/IMTokenLike.sol";
import { IMYieldToOne } from "./interfaces/IMYieldToOne.sol";

import { Blacklistable } from "./abstract/components/Blacklistable.sol";

import { MExtension } from "./abstract/MExtension.sol";

/**
 * @title  ERC20 Token contract for wrapping M into a non-rebasing token with claimable yields.
 * @author M^0 Labs
 */
contract MYieldToOne is IMYieldToOne, MExtension, Blacklistable {
    /* ============ Variables ============ */

    /// @inheritdoc IMYieldToOne
    bytes32 public constant YIELD_RECIPIENT_MANAGER_ROLE = keccak256("YIELD_RECIPIENT_MANAGER_ROLE");

    /// @inheritdoc IMYieldToOne
    address public yieldRecipient;

    /// @inheritdoc IERC20
    mapping(address account => uint256 balance) public balanceOf;

    /// @inheritdoc IERC20
    uint256 public totalSupply;

    /* ============ Constructor ============ */

    /**
     * @dev   Constructs the M extension token with yield claimable by a single recipient.
     * @param name_                  The name of the token (e.g. "M Yield to One").
     * @param symbol_                The symbol of the token (e.g. "MYO").
     * @param mToken_                The address of an M Token.
     * @param registrar_             The address of a registrar.
     * @param yieldRecipient_        The address of an yield destination.
     * @param defaultAdmin_          The address of a default admin.
     * @param blacklistManager_      The address of a blacklist manager.
     * @param yieldRecipientManager_ The address of a recipient setter.
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address mToken_,
        address registrar_,
        address yieldRecipient_,
        address defaultAdmin_,
        address blacklistManager_,
        address yieldRecipientManager_
    ) MExtension(name_, symbol_, mToken_, registrar_) Blacklistable(blacklistManager_) {
        if (yieldRecipientManager_ == address(0)) revert ZeroYieldRecipientManager();
        if (defaultAdmin_ == address(0)) revert ZeroDefaultAdmin();

        _setYieldRecipient(yieldRecipient_);

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin_);
        _grantRole(YIELD_RECIPIENT_MANAGER_ROLE, yieldRecipientManager_);
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

    /// @inheritdoc IMYieldToOne
    function setYieldRecipient(address account) external onlyRole(YIELD_RECIPIENT_MANAGER_ROLE) {
        _setYieldRecipient(account);
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
     * @dev Approve `spender` to spend `amount` of tokens from `account`.
     * @param account The address approving the allowance.
     * @param spender The address approved to spend the tokens.
     * @param amount  The amount of tokens being approved for spending.
     */
    function _approve(address account, address spender, uint256 amount) internal override {
        _revertIfBlacklisted(account);
        _revertIfBlacklisted(spender);

        super._approve(account, spender, amount);
    }

    /**
     * @dev    Hooks called before wrapping M into M Extension token.
     * @param  account   The account from which M is deposited.
     * @param  recipient The account receiving the minted M Extension token.
     */
    function _beforeWrap(address account, address recipient, uint256 /* amount */) internal view override {
        _revertIfBlacklisted(account);
        _revertIfBlacklisted(recipient);
    }

    /**
     * @dev   Mints `amount` tokens to `recipient`.
     * @param recipient The address whose account balance will be incremented.
     * @param amount    The present amount of tokens to mint.
     */
    function _mint(address recipient, uint256 amount) internal override {
        _revertIfInsufficientAmount(amount);
        _revertIfInvalidRecipient(recipient);

        unchecked {
            balanceOf[recipient] += amount;
            totalSupply += amount;
        }

        emit Transfer(address(0), recipient, amount);
    }

    /**
     * @dev   Hook called before unwrapping M Extension token.
     * @param account   The account from which M Extension token is burned.
     * @param recipient The account receiving the withdrawn M.
     */
    function _beforeUnwrap(address account, address recipient, uint256 /* amount */) internal view override {
        _revertIfBlacklisted(account);
        _revertIfBlacklisted(recipient);
    }

    /**
     * @dev   Burns `amount` tokens from `account`.
     * @param account The address whose account balance will be decremented.
     * @param amount  The present amount of tokens to burn.
     */
    function _burn(address account, uint256 amount) internal override {
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
    function _transfer(address sender, address recipient, uint256 amount) internal override {
        _revertIfBlacklisted(sender);
        _revertIfBlacklisted(recipient);
        _revertIfInvalidRecipient(recipient);

        emit Transfer(sender, recipient, amount);

        if (amount == 0) return;

        // NOTE: Can be `unchecked` because `_transfer` already checked for insufficient sender balance.
        unchecked {
            balanceOf[sender] -= amount;
            balanceOf[recipient] += amount;
        }
    }

    /**
     * @dev Sets the yield recipient.
     * @param account The address of the new yield recipient.
     */
    function _setYieldRecipient(address account) internal {
        if (account == address(0)) revert ZeroYieldRecipient();
        if (account == yieldRecipient) return;

        yieldRecipient = account;

        emit YieldRecipientSet(account);
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
