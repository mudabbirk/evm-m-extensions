// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { Test, console2 } from "../../lib/forge-std/src/Test.sol";

import { MockM, MockRegistrar } from "../utils/Mocks.sol";

import { MYieldToOne } from "../../src/MYieldToOne.sol";

import { IMYieldToOne } from "../../src/interfaces/IMYieldToOne.sol";
import { IMExtension } from "../../src/interfaces/IMExtension.sol";

import { IERC20 } from "../../lib/common/src/interfaces/IERC20.sol";
import { IERC20Extended } from "../../lib/common/src/interfaces/IERC20Extended.sol";

contract MYieldToOneUnitTests is Test {
    bytes32 internal constant _EARNERS_LIST_NAME = "earners";

    uint56 internal constant _EXP_SCALED_ONE = 1e12;

    address internal _yieldRecipient = makeAddr("yieldRecipient");

    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");
    address internal _charlie = makeAddr("charlie");
    address internal _david = makeAddr("david");

    address[] internal _accounts = [_alice, _bob, _charlie, _david];

    MockM internal _mToken;
    MockRegistrar internal _registrar;
    MYieldToOne internal _mYieldToOne;

    function setUp() external {
        _registrar = new MockRegistrar();

        _mToken = new MockM();

        _mYieldToOne = new MYieldToOne(address(_mToken), address(_registrar), _yieldRecipient);
    }

    /* ============ constructor ============ */
    function test_constructor() external view {
        assertEq(_mYieldToOne.mToken(), address(_mToken));
        assertEq(_mYieldToOne.registrar(), address(_registrar));
        assertEq(_mYieldToOne.yieldRecipient(), _yieldRecipient);
        assertEq(_mYieldToOne.name(), "HALO USD");
        assertEq(_mYieldToOne.symbol(), "HUSD");
        assertEq(_mYieldToOne.decimals(), 6);
    }

    function test_constructor_zeroMToken() external {
        vm.expectRevert(IMExtension.ZeroMToken.selector);
        new MYieldToOne(address(0), address(_registrar), address(_yieldRecipient));
    }

    function test_constructor_zeroRegistrar() external {
        vm.expectRevert(IMExtension.ZeroRegistrar.selector);
        new MYieldToOne(address(_mToken), address(0), address(_yieldRecipient));
    }

    function test_constructor_zeroYieldRecipient() external {
        vm.expectRevert(IMYieldToOne.ZeroYieldRecipient.selector);
        new MYieldToOne(address(_mToken), address(_registrar), address(0));
    }

    /* ============ _wrap ============ */

    function test_wrap_insufficientAmount() external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));

        vm.prank(_alice);
        _mYieldToOne.wrap(_alice, 0);
    }

    function test_wrap_invalidRecipient() external {
        _mToken.setBalanceOf(_alice, 1_000);

        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InvalidRecipient.selector, address(0)));

        vm.prank(_alice);
        _mYieldToOne.wrap(address(0), 1_000);
    }

    function test_wrap() external {
        _mToken.setBalanceOf(_alice, 2_000);

        assertEq(_mToken.balanceOf(_alice), 2_000);
        assertEq(_mYieldToOne.totalSupply(), 0);
        assertEq(_mYieldToOne.balanceOf(_alice), 0);
        assertEq(_mYieldToOne.yield(), 0);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), _alice, 1_000);

        vm.prank(_alice);
        _mYieldToOne.wrap(_alice, 1_000);

        assertEq(_mToken.balanceOf(_alice), 1_000);
        assertEq(_mYieldToOne.totalSupply(), 1_000);
        assertEq(_mYieldToOne.balanceOf(_alice), 1_000);
        assertEq(_mToken.balanceOf(address(_mYieldToOne)), 1_000);
        assertEq(_mYieldToOne.yield(), 0);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), _bob, 1_000);

        vm.prank(_alice);
        _mYieldToOne.wrap(_bob, 1_000);

        assertEq(_mToken.balanceOf(_alice), 0);
        assertEq(_mYieldToOne.totalSupply(), 2_000);
        assertEq(_mYieldToOne.balanceOf(_bob), 1_000);
        assertEq(_mToken.balanceOf(address(_mYieldToOne)), 2_000);
        assertEq(_mYieldToOne.yield(), 0);

        // simulate yield accrual by increasing accrued
        _mToken.setBalanceOf(address(_mYieldToOne), 2_500);
        assertEq(_mYieldToOne.yield(), 500);
        assertEq(_mYieldToOne.balanceOf(_bob), 1_000);
        assertEq(_mYieldToOne.balanceOf(_alice), 1_000);
    }

    /* ============ wrapWithPermit vrs ============ */

    function test_wrapWithPermit_vrs() external {
        _mToken.setBalanceOf(_alice, 1_000);

        assertEq(_mToken.balanceOf(_alice), 1_000);
        assertEq(_mYieldToOne.totalSupply(), 0);
        assertEq(_mYieldToOne.balanceOf(_alice), 0);
        assertEq(_mToken.balanceOf(address(_mYieldToOne)), 0);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), _alice, 1_000);

        vm.startPrank(_alice);
        _mYieldToOne.wrapWithPermit(_alice, 1_000, 0, 0, bytes32(0), bytes32(0));

        assertEq(_mToken.balanceOf(_alice), 0);
        assertEq(_mYieldToOne.totalSupply(), 1_000);
        assertEq(_mYieldToOne.balanceOf(_alice), 1_000);
        assertEq(_mToken.balanceOf(address(_mYieldToOne)), 1_000);
    }

    // /* ============ wrapWithPermit signature ============ */
    function test_wrapWithPermit_signature() external {
        _mToken.setBalanceOf(_alice, 1_000);

        assertEq(_mToken.balanceOf(_alice), 1_000);
        assertEq(_mYieldToOne.totalSupply(), 0);
        assertEq(_mYieldToOne.balanceOf(_alice), 0);
        assertEq(_mToken.balanceOf(address(_mYieldToOne)), 0);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), _alice, 1_000);

        vm.startPrank(_alice);
        _mYieldToOne.wrapWithPermit(_alice, 1_000, 0, hex"");

        assertEq(_mToken.balanceOf(_alice), 0);
        assertEq(_mYieldToOne.totalSupply(), 1_000);
        assertEq(_mYieldToOne.balanceOf(_alice), 1_000);
        assertEq(_mToken.balanceOf(address(_mYieldToOne)), 1_000);
    }

    /* ============ _unwrap ============ */
    function test_unwrap_insufficientAmount() external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));

        vm.prank(_alice);
        _mYieldToOne.unwrap(_alice, 0);
    }

    function test_unwrap_insufficientBalance() external {
        _mToken.setBalanceOf(_alice, 999);
        vm.prank(_alice);
        _mYieldToOne.wrap(_alice, 999);

        vm.expectRevert(abi.encodeWithSelector(IMYieldToOne.InsufficientBalance.selector, _alice, 999, 1_000));

        vm.prank(_alice);
        _mYieldToOne.unwrap(_alice, 1_000);
    }

    function test_unwrap() external {
        _mToken.setBalanceOf(_alice, 1000);
        vm.prank(_alice);
        _mYieldToOne.wrap(_alice, 1000);

        assertEq(_mToken.balanceOf(_alice), 0);
        assertEq(_mYieldToOne.balanceOf(_alice), 1_000);
        assertEq(_mYieldToOne.totalSupply(), 1_000);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, address(0), 1);

        vm.prank(_alice);
        _mYieldToOne.unwrap(_alice, 1);

        assertEq(_mYieldToOne.totalSupply(), 999);
        assertEq(_mYieldToOne.balanceOf(_alice), 999);
        assertEq(_mToken.balanceOf(_alice), 1);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, address(0), 499);

        vm.prank(_alice);
        _mYieldToOne.unwrap(_alice, 499);

        assertEq(_mYieldToOne.totalSupply(), 500);
        assertEq(_mYieldToOne.balanceOf(_alice), 500);
        assertEq(_mToken.balanceOf(_alice), 500);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, address(0), 500);

        vm.prank(_alice);
        _mYieldToOne.unwrap(_alice, 500);

        assertEq(_mYieldToOne.totalSupply(), 0);
        assertEq(_mYieldToOne.balanceOf(_alice), 0);
        assertEq(_mToken.balanceOf(_alice), 1000);
    }

    /* ============ yield ============ */
    function test_yield() external {
        _mToken.setBalanceOf(_alice, 1_000);
        _mToken.setBalanceOf(_bob, 1_000);

        vm.prank(_alice);
        _mYieldToOne.wrap(_alice, 1_000);

        vm.prank(_bob);
        _mYieldToOne.wrap(_bob, 1_000);

        assertEq(_mYieldToOne.yield(), 0);

        _mToken.setBalanceOf(address(_mYieldToOne), _mYieldToOne.totalSupply() + 500);

        assertEq(_mYieldToOne.yield(), 500);
    }

    /* ============ claimYield ============ */
    function test_claimYield_noYield() external {
        vm.expectRevert(IMYieldToOne.NoYield.selector);

        vm.prank(_alice);
        _mYieldToOne.claimYield();
    }

    function test_claimYield() external {
        _mToken.setBalanceOf(_alice, 1_000);

        vm.prank(_alice);
        _mYieldToOne.wrap(_alice, 1_000);

        _mToken.setBalanceOf(address(_mYieldToOne), _mYieldToOne.totalSupply() + 500);

        assertEq(_mYieldToOne.yield(), 500);

        vm.expectEmit();
        emit IMYieldToOne.YieldClaimed(500);

        _mYieldToOne.claimYield();

        assertEq(_mYieldToOne.yield(), 0);
        assertEq(_mToken.balanceOf(address(_mYieldToOne)), _mYieldToOne.totalSupply());
        assertEq(_mToken.balanceOf(_yieldRecipient), 500);
    }

    /* ============ enableEarning ============ */
    function test_enableEarning_notApprovedEarner() external {
        vm.expectRevert(abi.encodeWithSelector(IMExtension.NotApprovedEarner.selector, address(_mYieldToOne)));
        _mYieldToOne.enableEarning();
    }

    function test_enableEarning_earningEnabled() external {
        _mToken.setCurrentIndex(1_100000000000);

        _registrar.setListContains(_EARNERS_LIST_NAME, address(_mYieldToOne), true);
        _mYieldToOne.enableEarning();

        vm.expectRevert(IMExtension.EarningIsEnabled.selector);
        _mYieldToOne.enableEarning();
    }

    function test_enableEarning() external {
        _registrar.setListContains(_EARNERS_LIST_NAME, address(_mYieldToOne), true);

        _mToken.setCurrentIndex(1_210000000000);

        vm.expectEmit();
        emit IMExtension.EarningEnabled(1_210000000000);

        _mYieldToOne.enableEarning();

        assertEq(_mYieldToOne.isEarningEnabled(), true);
    }

    /* ============ disableEarning ============ */
    function test_disableEarning_earningIsDisabled() external {
        vm.expectRevert(IMExtension.EarningIsDisabled.selector);
        _mYieldToOne.disableEarning();
    }

    function test_disableEarning_approvedEarner() external {
        _registrar.setListContains(_EARNERS_LIST_NAME, address(_mYieldToOne), true);

        vm.expectRevert(abi.encodeWithSelector(IMExtension.IsApprovedEarner.selector, address(_mYieldToOne)));
        _mYieldToOne.disableEarning();
    }

    function test_disableEarning() external {
        _mToken.setCurrentIndex(1_100000000000);
        _registrar.setListContains(_EARNERS_LIST_NAME, address(_mYieldToOne), true);
        _mYieldToOne.enableEarning();

        _mToken.setCurrentIndex(1_200000000000);

        _registrar.setListContains(_EARNERS_LIST_NAME, address(_mYieldToOne), false);

        vm.expectEmit();
        emit IMExtension.EarningDisabled(1_200000000000);

        _mYieldToOne.disableEarning();

        assertEq(_mYieldToOne.isEarningEnabled(), false);
    }
}
