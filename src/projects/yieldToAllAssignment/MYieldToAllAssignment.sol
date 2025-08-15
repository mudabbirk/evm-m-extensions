// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

import {
    AccessControlUpgradeable
} from "../../../lib/common/lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";

import { IERC20 } from "../../../lib/common/src/interfaces/IERC20.sol";

import { ContinuousIndexingMath } from "../../../lib/common/src/libs/ContinuousIndexingMath.sol";
import { UIntMath } from "../../../lib/common/src/libs/UIntMath.sol";

import { IndexingMath } from "../../libs/IndexingMath.sol";

import { IMExtension } from "../../interfaces/IMExtension.sol";
import { IMTokenLike } from "../../interfaces/IMTokenLike.sol";

import { IMYieldToAllAssignment } from "./IMYieldToAllAssignment.sol";
import { IContinuousIndexing } from "../yieldToAllWithFee/interfaces/IContinuousIndexing.sol";

import { MExtension } from "../../MExtension.sol";

abstract contract MYieldToAllAssignmentStorageLayout {
    /// @custom:storage-location erc7201:M0.storage.MYieldToAllAssignment
    struct MYieldToAllAssignmentStorageStruct {
        // NOTE: Slot 1
        uint256 totalSupply;
        // NOTE: Slot 2
        uint112 totalPrincipal;
        uint128 latestIndex;
        uint16  __gap16; // small gap for 256-bit alignment clarity
        // NOTE: Slot 3
        uint40 latestUpdateTimestamp;
        uint32 latestRate;
        bool isEarningEnabled;
        // NOTE: Slot 4
        mapping(address account => uint256 balance) balanceOf;
        // NOTE: Slot 5
        mapping(address account => uint112 principal) principalOf;
        // NOTE: Slot 6
        mapping(address account => bool isWhitelisted) isWhitelisted;
    }

    // keccak256(abi.encode(uint256(keccak256("M0.storage.MYieldToAllAssignment")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _M_YIELD_TO_ALL_ASSIGNMENT_STORAGE_LOCATION =
        0x2248a56235aa2a04b79e076e424a418a57c2d9ea2fcb8df22ea1e5a9cacf5900;

    function _getMYieldToAllAssignmentStorageLocation() internal pure returns (MYieldToAllAssignmentStorageStruct storage $) {
        assembly {
            $.slot := _M_YIELD_TO_ALL_ASSIGNMENT_STORAGE_LOCATION
        }
    }
}

/**
 * @title MYieldToAllAssignment
 * @notice Upgradeable ERC20 Token contract for wrapping M into a non-rebasing token.
 *         Extended to include a whitelisting mechanism for addresses that are allowed to mint/burn.
 * @dev    All holders of this ERC20 token are earners.
 * @author Mudabbir Kaleem
 */
contract MYieldToAllAssignment is IContinuousIndexing, IMYieldToAllAssignment, AccessControlUpgradeable, MYieldToAllAssignmentStorageLayout, MExtension {
    /* ============ Variables ============ */

    /// @inheritdoc IMYieldToAllAssignment
    uint16 public constant ONE_HUNDRED_PERCENT = 10_000;

    /// @inheritdoc IMYieldToAllAssignment
    bytes32 public constant WHITELIST_MANAGER_ROLE = keccak256("WHITELIST_MANAGER_ROLE");

    /* ============ Constructor ============ */

    /**
     * @custom:oz-upgrades-unsafe-allow constructor
     * @notice Constructs MYieldToAllAssignment Implementation contract
     * @dev    Sets immutable storage.
     * @param  mToken       The address of $M token.
     * @param  swapFacility The address of Swap Facility.
     */
    constructor(address mToken, address swapFacility) MExtension(mToken, swapFacility) {}

    /* ============ Initializer ============ */

    /**
     * @notice Initializes the generic M Yield To All Assignment extension token.
     * @param name                  The name of the token (e.g. "M Yield To All Assignment").
     * @param symbol                The symbol of the token (e.g. "MYF").
     * @param admin                 The address administrating the M extension. Can grant and revoke roles.
     * @param whitelistManager The address managing the whitelist.
     */
    function initialize(
        string memory name,
        string memory symbol,
        address admin,
        address whitelistManager
    ) public virtual initializer {
        if (admin == address(0)) revert ZeroAdmin();
        if (whitelistManager == address(0)) revert ZeroWhitelistManager();

        __MExtension_init(name, symbol);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(WHITELIST_MANAGER_ROLE, whitelistManager);

        _getMYieldToAllAssignmentStorageLocation().latestIndex = ContinuousIndexingMath.EXP_SCALED_ONE;
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc IMYieldToAllAssignment
    function claimFor(address account) public returns (uint256) {
        if (account == address(0)) revert ZeroAccount();

        uint256 yield_ = accruedYieldOf(account);

        if (yield_ == 0) return 0;

        MYieldToAllAssignmentStorageStruct storage $ = _getMYieldToAllAssignmentStorageLocation();

        // NOTE: No change in principal, only the balance is updated to include the newly claimed yield.
        unchecked {
            $.balanceOf[account] += yield_;
            $.totalSupply += yield_;
        }

        // Emit the appropriate `YieldClaimed` and `Transfer` events, depending on the claim override recipient
        emit YieldClaimed(account, yield_);
        emit Transfer(address(0), account, yield_);

        return yield_;
    }

    /// @inheritdoc IMExtension
    function enableEarning() external override {
        MYieldToAllAssignmentStorageStruct storage $ = _getMYieldToAllAssignmentStorageLocation();

        if ($.isEarningEnabled) revert EarningIsEnabled();

        $.isEarningEnabled = true;

        // NOTE: update the index to store the latest state, current index won't accrue since `latestRate` is 0.
        emit EarningEnabled(updateIndex());

        IMTokenLike(mToken).startEarning();
    }

    /// @inheritdoc IMExtension
    function disableEarning() external override {
        MYieldToAllAssignmentStorageStruct storage $ = _getMYieldToAllAssignmentStorageLocation();

        if (!$.isEarningEnabled) revert EarningIsDisabled();

        // NOTE: update the index to store the latest state.
        emit EarningDisabled(updateIndex());

        // NOTE: disable earning by resetting values to their defaults.
        delete $.isEarningEnabled;
        delete $.latestRate;

        IMTokenLike(mToken).stopEarning(address(this));
    }

    /// @inheritdoc IContinuousIndexing
    function updateIndex() public virtual returns (uint128 currentIndex_) {
        MYieldToAllAssignmentStorageStruct storage $ = _getMYieldToAllAssignmentStorageLocation();

        // NOTE: return early if earning is disabled, no need to update the index.
        if (!$.isEarningEnabled) return $.latestIndex;

        // NOTE: Read the current M token rate adjusted by fee rate split.
        uint32 rate_ = earnerRate();
        uint40 latestAccrualTimestamp_ = _latestEarnerRateAccrualTimestamp();

        // NOTE: Return early if the index has already been updated in the current block and the rate has not changed.
        if ($.latestUpdateTimestamp == latestAccrualTimestamp_ && $.latestRate == rate_) return $.latestIndex;

        // NOTE: `currentIndex()` depends on `_latestRate`, so only update it after this.
        $.latestIndex = currentIndex_ = currentIndex();
        $.latestRate = rate_;
        $.latestUpdateTimestamp = latestAccrualTimestamp_;

        emit IndexUpdated(currentIndex_, rate_);
    }

    /// @inheritdoc IMYieldToAllAssignment
    function whitelistAddress(address account, bool addToWhitelist) external onlyRole(WHITELIST_MANAGER_ROLE){

        if (account == address(0)) revert ZeroAccount();

        _getMYieldToAllAssignmentStorageLocation().isWhitelisted[account] = addToWhitelist;

        emit AddressWhitelisted(account, addToWhitelist);
    }

    /* ============ External/Public view functions ============ */

    /// @inheritdoc IMYieldToAllAssignment
    function accruedYieldOf(address account) public view returns (uint256) {
        MYieldToAllAssignmentStorageStruct storage $ = _getMYieldToAllAssignmentStorageLocation();
        return _getAccruedYield($.balanceOf[account], $.principalOf[account], currentIndex());
    }

    /// @inheritdoc IERC20
    function balanceOf(address account) public view override returns (uint256) {
        return _getMYieldToAllAssignmentStorageLocation().balanceOf[account];
    }

    /// @inheritdoc IMYieldToAllAssignment
    function balanceWithYieldOf(address account) external view returns (uint256) {
        unchecked {
            return balanceOf(account) + accruedYieldOf(account);
        }
    }

    /// @inheritdoc IMYieldToAllAssignment
    function principalOf(address account) public view returns (uint112) {
        return _getMYieldToAllAssignmentStorageLocation().principalOf[account];
    }
    
    /// @inheritdoc IContinuousIndexing
    function currentIndex() public view virtual override(IContinuousIndexing, MExtension) returns (uint128) {
        MYieldToAllAssignmentStorageStruct storage $ = _getMYieldToAllAssignmentStorageLocation();

        if (!$.isEarningEnabled) return $.latestIndex;

        // NOTE: Safe to use unchecked here, since `block.timestamp` is always greater than `latestUpdateTimestamp`.
        unchecked {
            return
                // NOTE: Cap the index to `type(uint128).max` to prevent overflow in present value math.
                UIntMath.bound128(
                    ContinuousIndexingMath.multiplyIndicesDown(
                        $.latestIndex,
                        ContinuousIndexingMath.getContinuousIndex(
                            ContinuousIndexingMath.convertFromBasisPoints($.latestRate),
                            uint32(_latestEarnerRateAccrualTimestamp() - $.latestUpdateTimestamp)
                        )
                    )
                );
        }
    }

    /// @inheritdoc IMYieldToAllAssignment
    function earnerRate() public view virtual returns (uint32) {
        return isEarningEnabled() ? _currentEarnerRate() : 0;
    }

        /// @inheritdoc IMExtension
    function isEarningEnabled() public view override returns (bool) {
        return _getMYieldToAllAssignmentStorageLocation().isEarningEnabled;
    }

    /// @inheritdoc IContinuousIndexing
    function latestIndex() public view returns (uint128) {
        return _getMYieldToAllAssignmentStorageLocation().latestIndex;
    }

    /// @inheritdoc IContinuousIndexing
    function latestRate() public view returns (uint32) {
        return _getMYieldToAllAssignmentStorageLocation().latestRate;
    }

    /// @inheritdoc IContinuousIndexing
    function latestUpdateTimestamp() public view returns (uint40) {
        return _getMYieldToAllAssignmentStorageLocation().latestUpdateTimestamp;
    }

    /// @inheritdoc IMYieldToAllAssignment
    function projectedTotalSupply() public view returns (uint256) {
        return IndexingMath.getPresentAmountRoundedUp(_getMYieldToAllAssignmentStorageLocation().totalPrincipal, currentIndex());
    }

    /// @inheritdoc IMYieldToAllAssignment
    function totalAccruedYield() public view returns (uint256) {
        MYieldToAllAssignmentStorageStruct storage $ = _getMYieldToAllAssignmentStorageLocation();
        return _getAccruedYield($.totalSupply, $.totalPrincipal, currentIndex());
    }

    /// @inheritdoc IMYieldToAllAssignment
    function totalPrincipal() public view returns (uint112) {
        return _getMYieldToAllAssignmentStorageLocation().totalPrincipal;
    }

    /// @inheritdoc IERC20
    function totalSupply() public view returns (uint256) {
        return _getMYieldToAllAssignmentStorageLocation().totalSupply;
    }

    /// @inheritdoc IMYieldToAllAssignment
    function isWhitelisted(address account) external view returns (bool) {
        return _getMYieldToAllAssignmentStorageLocation().isWhitelisted[account];
    }

    /* ============ Internal Interactive Functions ============ */

    /**
     * @dev   Mints `amount` tokens to `recipient`.
     * @param recipient The address that will receive tokens.
     * @param amount    The amount of tokens to mint.
     */
    function _mint(address recipient, uint256 amount) internal override {
        _mint(recipient, amount, IndexingMath.getPrincipalAmountRoundedDown(amount, currentIndex()));
    }


    /**
     * @dev   Mints `amount` tokens to `recipient` with a specified principal.
     * @param recipient The address that will receive tokens.
     * @param amount    The amount of tokens to mint.
     * @param principal The principal amount to be associated with the minted tokens.
     */
    function _mint(address recipient, uint256 amount, uint112 principal) internal {

        MYieldToAllAssignmentStorageStruct storage $ = _getMYieldToAllAssignmentStorageLocation();
        // only whitelisted addresses can mint
        if (!$.isWhitelisted[recipient]) revert AddressNotWhitelisted();

        // NOTE: Can be `unchecked` because the max amount of  M is never greater than `type(uint240).max`.
        //       Can be `unchecked` because UIntMath.safe112 is used for principal addition safety for `totalPrincipal`
        unchecked {
            $.balanceOf[recipient] += amount;
            $.totalSupply += amount;

            $.totalPrincipal = UIntMath.safe112(uint256($.totalPrincipal) + principal);
            // No need for `UIntMath.safe112`, `principalOf[recipient]` cannot be greater than `totalPrincipal`.
            $.principalOf[recipient] += principal;
        }

        emit Transfer(address(0), recipient, amount);
    }

    /**
     * @dev   Burns `amount` tokens from `account`.
     * @param account The address whose account balance will be decremented.
     * @param amount  The present amount of tokens to burn.
     */
    function _burn(address account, uint256 amount) internal override {
        MYieldToAllAssignmentStorageStruct storage $ = _getMYieldToAllAssignmentStorageLocation();

        // only whitelisted addresses can burn
        if (!$.isWhitelisted[account]) revert AddressNotWhitelisted();

        // Slightly overestimate the principal amount to be burned and use safe value to avoid underflow in unchecked block
        uint112 fromPrincipal_ = $.principalOf[account];
        uint112 principal_ = IndexingMath.getSafePrincipalAmountRoundedUp(amount, currentIndex(), fromPrincipal_);

        // NOTE: Can be `unchecked` because `_revertIfInsufficientBalance` is used.
        //       Can be `unchecked` because safety adjustment to `principal_` is applied above, and
        //       `principalOf[account]` cannot be greater than `totalPrincipal`.
        unchecked {
            $.balanceOf[account] -= amount;
            $.totalSupply -= amount;

            $.principalOf[account] = fromPrincipal_ - principal_;
            $.totalPrincipal -= principal_;
        }

        emit Transfer(account, address(0), amount);
    }

    /**
     * @dev   Internal ERC20 transfer function that needs to be implemented by the inheriting contract.
     * @param sender    The sender's address.
     * @param recipient The recipient's address.
     * @param amount    The amount to be transferred.
     */
    function _update(address sender, address recipient, uint256 amount) internal override {
        MYieldToAllAssignmentStorageStruct storage $ = _getMYieldToAllAssignmentStorageLocation();

        // Slightly overestimate the principal amount to be moved on transfer
        uint112 fromPrincipal_ = $.principalOf[sender];
        uint112 principal_ = IndexingMath.getSafePrincipalAmountRoundedUp(amount, currentIndex(), fromPrincipal_);

        // NOTE: Can be `unchecked` because we check for insufficient sender balance above.
        //       Can be `unchecked` because safety adjustment to `principal_` is applied above, and
        unchecked {
            $.balanceOf[sender] -= amount;
            $.balanceOf[recipient] += amount;

            $.principalOf[sender] = fromPrincipal_ - principal_;
            $.principalOf[recipient] += principal_;
        }
    }

    /* ============ Internal View/Pure Functions ============ */

    /**
     * @dev   Returns the timestamp when the earner rate was last accrued to accounts.
     *        For L1: returns the current `block.timestamp` as the rate accrues continuously.
     *        For L2: returns the `latestUpdateTimestamp` from the M token when the index was propagated from L1.
     *        Can be overridden by the inheriting contract (for EVM L2 contracts with index propagation).
     *        MUST return the current block timestamp for an M extension token deployed on the mainnet.
     *        MUST return spoke M token's `latestUpdateTimestamp` for an M extension token deployed on a spoke chain.
     * @return The current block timestamp.
     */
    function _latestEarnerRateAccrualTimestamp() internal view virtual returns (uint40) {
        return uint40(block.timestamp);
    }

    /**
     * @dev    Returns the current earner rate.
     *         Needs to be overridden by the inheriting contract.
     *         MUST return M token's earner rate for an M extension token deployed on the mainnet.
     *         MUST return a rate oracle's earner rate for an M extension token deployed on a spoke chain.
     * @return The current earner rate.
     */
    function _currentEarnerRate() internal view virtual returns (uint32) {
        // NOTE: The behavior of M is known, so we can safely retrieve the earner rate.
        return IMTokenLike(mToken).earnerRate();
    }

    /**
     * @dev    Compute the yield given a balance, principal and index.
     * @param  balance   The current balance of the account.
     * @param  principal The principal of the account.
     * @param  index     The current index.
     * @return The yield accrued since the last claim.
     */
    function _getAccruedYield(uint256 balance, uint112 principal, uint128 index) internal pure returns (uint256) {
        uint256 balanceWithYield_ = IndexingMath.getPresentAmountRoundedDown(principal, index);
        unchecked {
            return balanceWithYield_ > balance ? balanceWithYield_ - balance : 0;
        }
    }
}
