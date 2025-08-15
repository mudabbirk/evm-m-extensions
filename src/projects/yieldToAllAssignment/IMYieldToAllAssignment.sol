// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

/**
 * @title  Interface for M Yield To All Assignment.
 * @author Mudabbir Kaleem
 */
interface IMYieldToAllAssignment {
    /* ============ Events ============ */

    /**
     * @notice Emitted when an account's yield is claimed.
     * @param  claimer   The address that claimed the yield.
     * @param  yield     The amount of M yield claimed.
     */
    event YieldClaimed(address indexed claimer, uint256 yield);

    /**
     * @notice Emitted when an address is whitelisted or removed from the whitelist.
     * @param  account The address being whitelisted or removed from the whitelist.
     * @param  isWhitelisted Boolean indicating whether the address is whitelisted (true) or removed from the whitelist (false).
     */
    event AddressWhitelisted(address indexed account, bool isWhitelisted);

    /* ============ Custom Errors ============ */

    /// @notice Emitted in constructor if the admin is 0x0.
    error ZeroAdmin();

    /// @notice Emitted in constructor if the whitelistManager is 0x0.
    error ZeroWhitelistManager();

    /// @notice Emitted if the account is 0x0.
    error ZeroAccount();

    /// @notice Emitted if the address is not whitelisted.
    error AddressNotWhitelisted();

    /* ============ Interactive Functions ============ */

    /**
     * @notice Claims `account`'s accrued yield.
     * @dev    Can be used to claim yield on behalf of `account`.
     * @param  account The address of the account.
     * @return yieldWithFee The total amount of M extension yield claimed for the account.
     */
    function claimFor(address account) external returns (uint256);

    /**
     * @notice Whitelists or removes an address from the whitelist.
     * @dev    Only callable by an account with the `EARNER_MANAGER_ROLE`.
     * @param  account The address to be whitelisted or removed from the whitelist.
     * @param  addToWhitelist Boolean indicating whether to add to whitelist (true) or remove from the whitelist (false).
     */
    function whitelistAddress(address account, bool addToWhitelist) external;

    /* ============ View/Pure Functions ============ */

    /// @notice Returns 100% in basis points.
    function ONE_HUNDRED_PERCENT() external pure returns (uint16);

    /// @notice Returns the whitelist manager role hash.
    function WHITELIST_MANAGER_ROLE() external pure returns (bytes32);

    /**
     * @notice Returns the yield accrued for `account`, which is claimable.
     * @param  account The account being queried.
     * @return The amount of yield that is claimable.
     */
    function accruedYieldOf(address account) external view returns (uint256);

    /// @notice Returns the current value of the earner rate in basis points.
    function earnerRate() external view returns (uint32);

    /**
     * @notice Returns the token balance of `account` including any accrued yield.
     * @param  account The address of some account.
     * @return The token balance of `account` including any accrued yield.
     */
    function balanceWithYieldOf(address account) external view returns (uint256);

    /**
     * @notice Returns the principal of `account`.
     * @param  account The address of some account.
     * @return The principal of `account`.
     */
    function principalOf(address account) external view returns (uint112);

    /// @notice The projected total supply if all accrued yield was claimed at this moment.
    function projectedTotalSupply() external view returns (uint256);

    /// @notice The current total accrued yield claimable by holders.
    function totalAccruedYield() external view returns (uint256);

    /// @notice The total principal to help compute `totalAccruedYield()`.
    function totalPrincipal() external view returns (uint112);

    /**
     * @notice Returns true if the account is whitelisted, otherwise false.
     * @param  account The address to check for whitelist status.
     * @return True if the account is whitelisted, otherwise false.
     */
    function isWhitelisted(address account) external view returns (bool);
}
