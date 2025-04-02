// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

import { ERC20Extended } from "../lib/common/src/ERC20Extended.sol";
import { UIntMath } from "../lib/common/src/libs/UIntMath.sol";

import { IMTokenLike } from "./interfaces/IMTokenLike.sol";
import { IMExtension } from "./interfaces/IMExtension.sol";
import { IRegistrarLike } from "./interfaces/IRegistrarLike.sol";

/**
 * @title  ERC20 Token contract for wrapping M into a non-rebasing token with claimable yields.
 * @author M^0 Labs
 */
abstract contract MExtension is IMExtension, ERC20Extended {
    /* ============ Variables ============ */

    /// @inheritdoc IMExtension
    address public immutable mToken;

    /// @inheritdoc IMExtension
    address public immutable registrar;

    /// @inheritdoc IMExtension
    uint128 public enableMIndex;

    /// @inheritdoc IMExtension
    uint128 public disableIndex;

    /// @dev Registrar key holding value of whether the earners list can be ignored or not.
    bytes32 internal constant _EARNERS_LIST_IGNORED = "earners_list_ignored";

    /// @dev Registrar key of earners list.
    bytes32 internal constant _EARNERS_LIST = "earners";

    /// @notice The scaling of indexes for exponent math.
    uint56 internal constant _EXP_SCALED_ONE = 1e12;

    /* ============ Constructor ============ */

    /**
     * @dev   Constructs the generic M extension token.
     * @param name               The name of the token (e.g. "HALO USD").
     * @param symbol             The symbol of the token (e.g. "HUSD").
     * @param mToken_            The address of an M Token.
     * @param registrar_         The address of a registrar.
     */
    constructor(
        string memory name,
        string memory symbol,
        address mToken_,
        address registrar_
    ) ERC20Extended(name, symbol, 6) {
        if ((mToken = mToken_) == address(0)) revert ZeroMToken();
        if ((registrar = registrar_) == address(0)) revert ZeroRegistrar();
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc IMExtension
    function wrap(address recipient, uint256 amount) external {
        _wrap(msg.sender, recipient, amount);
    }

    /// @inheritdoc IMExtension
    function wrapWithPermit(
        address recipient,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        try IMTokenLike(mToken).permit(msg.sender, address(this), amount, deadline, v, r, s) {} catch {}

        _wrap(msg.sender, recipient, amount);
    }

    /// @inheritdoc IMExtension
    function wrapWithPermit(address recipient, uint256 amount, uint256 deadline, bytes memory signature) external {
        try IMTokenLike(mToken).permit(msg.sender, address(this), amount, deadline, signature) {} catch {}

        _wrap(msg.sender, recipient, amount);
    }

    /// @inheritdoc IMExtension
    function unwrap(address recipient, uint256 amount) external {
        _unwrap(msg.sender, recipient, amount);
    }

    /// @inheritdoc IMExtension
    function enableEarning() external {
        if (!_isThisApprovedEarner()) revert NotApprovedEarner(address(this));
        if (isEarningEnabled()) revert EarningIsEnabled();

        emit EarningEnabled(enableMIndex = _currentMIndex());

        IMTokenLike(mToken).startEarning();
    }

    /// @inheritdoc IMExtension
    function disableEarning() external {
        if (_isThisApprovedEarner()) revert IsApprovedEarner(address(this));
        if (!isEarningEnabled()) revert EarningIsDisabled();

        emit EarningDisabled(disableIndex = currentIndex());

        delete enableMIndex;

        IMTokenLike(mToken).stopEarning();
    }

    /* ============ View/Pure Functions ============ */

    /// @inheritdoc IMExtension
    function currentIndex() public view returns (uint128) {
        uint128 disableIndex_ = disableIndex == 0 ? _EXP_SCALED_ONE : disableIndex;

        unchecked {
            return
                enableMIndex == 0
                    ? disableIndex_
                    : UIntMath.safe128((uint256(disableIndex_) * _currentMIndex()) / enableMIndex);
        }
    }

    /// @inheritdoc IMExtension
    function isEarningEnabled() public view returns (bool) {
        return enableMIndex != 0;
    }

    /* ============ Internal Interactive Functions ============ */

    /**
     * @dev    Wraps `amount` M from `account` into MExtension for `recipient`.
     * @param  account   The account from which M is deposited.
     * @param  recipient The account receiving the minted wM.
     * @param  amount    The amount of M deposited.
     */
    function _wrap(address account, address recipient, uint256 amount) internal {
        // NOTE: The behavior of `IMTokenLike.transferFrom` is known, so its return can be ignored.
        IMTokenLike(mToken).transferFrom(account, address(this), amount);

        // Mints precise amount of Wrapped $M to `recipient`.
        _mint(recipient, amount);
    }

    /**
     * @dev    Unwraps `amount` wM from `account_` into M for `recipient`.
     * @param  account   The account from which WM is burned.
     * @param  recipient The account receiving the withdrawn M.
     * @param  amount    The amount of wM burned.
     */
    function _unwrap(address account, address recipient, uint256 amount) internal {
        _burn(account, amount);

        // NOTE: The behavior of `IMTokenLike.transfer` is known, so its return can be ignored.
        IMTokenLike(mToken).transfer(recipient, amount);
    }

    /**
     * @dev Mints `amount` tokens to `recipient`.
     * @param recipient The address to which the tokens will be minted.
     * @param amount    The amount of tokens to mint.
     */
    function _mint(address recipient, uint256 amount) internal virtual;

    /**
     * @dev Burns `amount` tokens from `account`.
     * @param account The address from which the tokens will be burned.
     * @param amount  The amount of tokens to burn.
     */
    function _burn(address account, uint256 amount) internal virtual;

    /* ============ Internal View/Pure Functions ============ */

    /// @dev Returns the current index of the M Token.
    function _currentMIndex() internal view returns (uint128) {
        return IMTokenLike(mToken).currentIndex();
    }

    /// @dev Returns whether this contract is a Registrar-approved earner.
    function _isThisApprovedEarner() internal view returns (bool) {
        return
            IRegistrarLike(registrar).get(_EARNERS_LIST_IGNORED) != bytes32(0) ||
            IRegistrarLike(registrar).listContains(_EARNERS_LIST, address(this));
    }
}
