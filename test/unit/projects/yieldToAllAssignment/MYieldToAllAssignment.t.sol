// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { console } from "forge-std/console.sol";
import {
    IAccessControl
} from "../../../../lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { Upgrades, UnsafeUpgrades } from "../../../../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { IndexingMath } from "../../../../lib/common/src/libs/IndexingMath.sol";
import { UIntMath } from "../../../../lib/common/src/libs/UIntMath.sol";
import { ContinuousIndexingMath } from "../../../../lib/common/src/libs/ContinuousIndexingMath.sol";

import { IMExtension } from "../../../../src/interfaces/IMExtension.sol";
import { IMTokenLike } from "../../../../src/interfaces/IMTokenLike.sol";
import { IMYieldToAllAssignment } from "../../../../src/projects/yieldToAllAssignment/IMYieldToAllAssignment.sol";
import { ISwapFacility } from "../../../../src/swap/interfaces/ISwapFacility.sol";

import { IERC20 } from "../../../../lib/common/src/interfaces/IERC20.sol";
import { IERC20Extended } from "../../../../lib/common/src/interfaces/IERC20Extended.sol";

import { MYieldToAllAssignmentHarness } from "../../../harness/MYieldToAllAssignmentHarness.sol";
import { BaseUnitTest } from "../../../utils/BaseUnitTest.sol";

contract MYieldToAllAssignmentUnitTests is BaseUnitTest {
    MYieldToAllAssignmentHarness public mYieldToAllAssignment;

    address public whitelistManager;

    // Use one raw earner rate everywhere in deterministic tests
    uint32 constant RAW_RATE = 415;

    function setUp() public override {
        super.setUp();

        whitelistManager = makeAddr("whitelistManager");

        mYieldToAllAssignment = MYieldToAllAssignmentHarness(
            Upgrades.deployTransparentProxy(
                "MYieldToAllAssignmentHarness.sol:MYieldToAllAssignmentHarness",
                admin,
                abi.encodeWithSelector(
                    MYieldToAllAssignmentHarness.initialize.selector,
                    "mYieldToAllAssignment",
                    "MYF",
                    admin,
                    whitelistManager
                ),
                mExtensionDeployOptions
            )
        );

        // mark the earner
        registrar.setEarner(address(mYieldToAllAssignment), true);

        // whitelist common actors so wrap/unwrap/transfer paths don't revert
        vm.startPrank(whitelistManager);
        mYieldToAllAssignment.whitelistAddress(alice, true);
        mYieldToAllAssignment.whitelistAddress(bob, true);
        mYieldToAllAssignment.whitelistAddress(address(swapFacility), true);
        vm.stopPrank();
    }

    /* ============ initialize ============ */

    function test_initialize() external view {
        assertEq(mYieldToAllAssignment.ONE_HUNDRED_PERCENT(), 10_000);
        assertEq(mYieldToAllAssignment.latestIndex(), EXP_SCALED_ONE);
        assertTrue(mYieldToAllAssignment.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(mYieldToAllAssignment.hasRole(mYieldToAllAssignment.WHITELIST_MANAGER_ROLE(), whitelistManager));
    }

    function test_initialize_zeroAdmin() external {
        address implementation = address(new MYieldToAllAssignmentHarness(address(mToken), address(swapFacility)));

        vm.expectRevert(IMYieldToAllAssignment.ZeroAdmin.selector);
        MYieldToAllAssignmentHarness(
            UnsafeUpgrades.deployTransparentProxy(
                implementation,
                admin,
                abi.encodeWithSelector(
                    MYieldToAllAssignmentHarness.initialize.selector,
                    "mYieldToAllAssignment",
                    "MYF",
                    address(0),
                    claimRecipientManager // any non-zero address
                )
            )
        );
    }

    /* ============ claimFor ============ */

    function test_claimFor_zeroYieldRecipient() external {
        vm.expectRevert(IMYieldToAllAssignment.ZeroAccount.selector);
        mYieldToAllAssignment.claimFor(address(0));
    }

    function test_claimFor_noYield() external {
        assertEq(mYieldToAllAssignment.claimFor(alice), 0);
    }

    function test_claimFor() external {
        // set earning baseline & rate
        mYieldToAllAssignment.setIsEarningEnabled(true);
        mYieldToAllAssignment.setLatestRate(RAW_RATE);
        mYieldToAllAssignment.setLatestUpdateTimestamp(startTimestamp);

        uint240 aliceBalance = 1_000e6;
        mYieldToAllAssignment.setAccountOf(alice, aliceBalance, 1_000e6);

        // advance ~1y
        vm.warp(startTimestamp + 30_057_038);
        uint128 expected = _getCurrentIndex(EXP_SCALED_ONE, RAW_RATE, startTimestamp);
        assertEq(mYieldToAllAssignment.currentIndex(), expected);

        // fund contract with exactly the user's accrued yield and claim it
        uint256 yieldAmount = mYieldToAllAssignment.accruedYieldOf(alice);
        mToken.setBalanceOf(address(mYieldToAllAssignment), uint240(yieldAmount));

        vm.expectEmit();
        emit IMYieldToAllAssignment.YieldClaimed(alice, yieldAmount);

        vm.prank(alice);
        assertEq(mYieldToAllAssignment.claimFor(alice), yieldAmount);

        aliceBalance += uint240(yieldAmount);

        assertEq(mYieldToAllAssignment.balanceOf(alice), aliceBalance);
        assertEq(mYieldToAllAssignment.accruedYieldOf(alice), 0);

        // advance again; index must reflect the new time delta from the same baseline
        vm.warp(startTimestamp + 30_057_038 * 2);
        expected = _getCurrentIndex(EXP_SCALED_ONE, RAW_RATE, startTimestamp);
        assertEq(mYieldToAllAssignment.currentIndex(), expected);
    }

    function testFuzz_claimFor(
        bool earningEnabled,
        uint16 /* feeRate (unused) */,
        uint128 latestIndex,
        uint240 balanceWithYield,
        uint240 balance
    ) external {
        uint128 currentIndex = _setupIndex(earningEnabled, latestIndex);
        (balanceWithYield, balance) = _getFuzzedBalances(
            currentIndex,
            balanceWithYield,
            balance,
            _getMaxAmount(currentIndex)
        );

        _setupAccount(alice, balanceWithYield, balance);

        uint256 yieldAmount = mYieldToAllAssignment.accruedYieldOf(alice);

        if (yieldAmount != 0) {
            vm.expectEmit();
            emit IMYieldToAllAssignment.YieldClaimed(alice, yieldAmount);
        }

        uint256 aliceBanceBefore = mYieldToAllAssignment.balanceOf(alice);

        vm.prank(alice);
        assertEq(mYieldToAllAssignment.claimFor(alice), yieldAmount);

        assertEq(mYieldToAllAssignment.balanceOf(alice), aliceBanceBefore + yieldAmount);
        assertEq(mYieldToAllAssignment.accruedYieldOf(alice), 0);
    }

    /* ============ enableEarning ============ */

    function test_enableEarning_earningIsEnabled() external {
        mYieldToAllAssignment.setIsEarningEnabled(true);

        vm.expectRevert(abi.encodeWithSelector(IMExtension.EarningIsEnabled.selector));
        mYieldToAllAssignment.enableEarning();
    }

    function test_enableEarning() external {
        assertEq(mYieldToAllAssignment.currentIndex(), EXP_SCALED_ONE);
        assertEq(mYieldToAllAssignment.latestIndex(), EXP_SCALED_ONE);
        assertEq(mYieldToAllAssignment.latestRate(), 0);

        // mock token rate so updateIndex() (called inside enableEarning) picks it up
        vm.mockCall(address(mToken), abi.encodeWithSelector(IMTokenLike.earnerRate.selector), abi.encode(RAW_RATE));

        vm.expectEmit();
        emit IMExtension.EarningEnabled(EXP_SCALED_ONE);

        mYieldToAllAssignment.enableEarning();

        assertEq(mYieldToAllAssignment.currentIndex(), EXP_SCALED_ONE);
        assertEq(mYieldToAllAssignment.latestIndex(), EXP_SCALED_ONE);
        assertEq(mYieldToAllAssignment.latestRate(), RAW_RATE);

        // advance ~1y from startTimestamp (baseline was set at enableEarning time = startTimestamp)
        vm.warp(startTimestamp + 30_057_038);
        uint128 expected = _getCurrentIndex(EXP_SCALED_ONE, RAW_RATE, startTimestamp);
        assertEq(mYieldToAllAssignment.currentIndex(), expected);
    }

    /* ============ disableEarning ============ */

    function test_disableEarning_earningIsDisabled() external {
        vm.expectRevert(IMExtension.EarningIsDisabled.selector);
        mYieldToAllAssignment.disableEarning();
    }

    function test_disableEarning() external {
        mYieldToAllAssignment.setIsEarningEnabled(true);
        mYieldToAllAssignment.setLatestRate(RAW_RATE);
        mYieldToAllAssignment.setLatestIndex(1_100000000000);

        // fix baseline so currentIndex() == latestIndex() at t0
        uint40 baseline = uint40(vm.getBlockTimestamp());
        mYieldToAllAssignment.setLatestUpdateTimestamp(baseline);

        assertEq(mYieldToAllAssignment.currentIndex(), 1_100000000000);
        assertEq(mYieldToAllAssignment.latestIndex(), 1_100000000000);
        assertEq(mYieldToAllAssignment.latestRate(), RAW_RATE);

        // advance
        vm.warp(startTimestamp + 30_057_038);
        uint128 expected = _getCurrentIndex(1_100000000000, RAW_RATE, baseline);
        assertEq(mYieldToAllAssignment.currentIndex(), expected);

        vm.expectEmit();
        emit IMExtension.EarningDisabled(expected);

        mYieldToAllAssignment.disableEarning();

        assertFalse(mYieldToAllAssignment.isEarningEnabled());
        assertEq(mYieldToAllAssignment.currentIndex(), expected);
        assertEq(mYieldToAllAssignment.latestIndex(), expected);
        assertEq(mYieldToAllAssignment.latestRate(), 0);

        // further time should not change index
        vm.warp(startTimestamp + 30_057_038 * 2);
        assertEq(mYieldToAllAssignment.currentIndex(), expected);
        assertEq(mYieldToAllAssignment.updateIndex(), expected);
        assertEq(mYieldToAllAssignment.currentIndex(), expected);
        assertEq(mYieldToAllAssignment.latestIndex(), expected);
        assertEq(mYieldToAllAssignment.latestRate(), 0);
    }

    /* ============ currentIndex ============ */

    function test_currentIndex() external {
        mYieldToAllAssignment.setIsEarningEnabled(true);
        mYieldToAllAssignment.setLatestRate(RAW_RATE);
        mYieldToAllAssignment.setLatestUpdateTimestamp(startTimestamp);

        // ensure updateIndex() observes our RAW_RATE
        vm.mockCall(address(mToken), abi.encodeWithSelector(IMTokenLike.earnerRate.selector), abi.encode(RAW_RATE));

        uint256 expectedIndex = EXP_SCALED_ONE;
        assertEq(mYieldToAllAssignment.currentIndex(), expectedIndex);

        // t1
        uint256 nextTimestamp = vm.getBlockTimestamp() + 365 days;
        vm.warp(nextTimestamp);

        uint128 expectedCurrentIndex = _getCurrentIndex(EXP_SCALED_ONE, RAW_RATE, startTimestamp);

        assertEq(mYieldToAllAssignment.currentIndex(), expectedCurrentIndex);
        assertEq(mYieldToAllAssignment.updateIndex(), expectedCurrentIndex);

        uint40 previousTimestamp = uint40(nextTimestamp);

        // t2
        nextTimestamp = vm.getBlockTimestamp() + 365 days * 2;
        vm.warp(nextTimestamp);

        expectedCurrentIndex = _getCurrentIndex(expectedCurrentIndex, RAW_RATE, previousTimestamp);
        assertEq(mYieldToAllAssignment.currentIndex(), expectedCurrentIndex);

        // change rate for subsequent accrual
        uint32 nextRate = RAW_RATE / 2;
        vm.mockCall(address(mToken), abi.encodeWithSelector(IMTokenLike.earnerRate.selector), abi.encode(nextRate));

        // save new baseline and new rate
        assertEq(mYieldToAllAssignment.updateIndex(), expectedCurrentIndex);
        assertEq(mYieldToAllAssignment.latestRate(), nextRate);

        previousTimestamp = uint40(nextTimestamp);

        // t3
        nextTimestamp = vm.getBlockTimestamp() + 365 days * 3;
        vm.warp(nextTimestamp);

        expectedCurrentIndex = _getCurrentIndex(expectedCurrentIndex, nextRate, previousTimestamp);
        assertEq(mYieldToAllAssignment.currentIndex(), expectedCurrentIndex);
        assertEq(mYieldToAllAssignment.updateIndex(), expectedCurrentIndex);

        // Disable earning
        mYieldToAllAssignment.disableEarning();
        previousTimestamp = uint40(nextTimestamp);

        // t4 (no change expected)
        nextTimestamp = vm.getBlockTimestamp() + 365 days * 4;
        vm.warp(nextTimestamp);
        assertEq(mYieldToAllAssignment.currentIndex(), expectedCurrentIndex);

        // Re-enable earning
        vm.mockCall(address(mToken), abi.encodeWithSelector(IMTokenLike.earnerRate.selector), abi.encode(RAW_RATE));
        mYieldToAllAssignment.enableEarning();
        mYieldToAllAssignment.setLatestRate(RAW_RATE);

        assertEq(mYieldToAllAssignment.updateIndex(), expectedCurrentIndex);
        assertEq(mYieldToAllAssignment.currentIndex(), expectedCurrentIndex);

        previousTimestamp = uint40(nextTimestamp);

        // t5
        nextTimestamp = vm.getBlockTimestamp() + 365 days * 5;
        vm.warp(nextTimestamp);

        expectedCurrentIndex = _getCurrentIndex(expectedCurrentIndex, RAW_RATE, previousTimestamp);
        assertEq(mYieldToAllAssignment.currentIndex(), expectedCurrentIndex);
        assertEq(mYieldToAllAssignment.updateIndex(), expectedCurrentIndex);
    }

    function testFuzz_currentIndex(
        uint32 earnerRate,
        uint32 nextEarnerRate,
        uint16 /* feeRate (unused) */,
        uint16 /* nextYieldFeeRate (unused) */,
        bool isEarningEnabled,
        uint128 latestIndex,
        uint40 latestUpdateTimestamp,
        uint40 nextTimestamp,
        uint40 finalTimestamp
    ) external {
        vm.assume(nextTimestamp > latestUpdateTimestamp);

        vm.mockCall(address(mToken), abi.encodeWithSelector(IMTokenLike.earnerRate.selector), abi.encode(earnerRate));
        uint32 latestRate = mYieldToAllAssignment.latestRate();

        mYieldToAllAssignment.setIsEarningEnabled(isEarningEnabled);
        latestIndex = _setupLatestIndex(latestIndex);
        latestRate = _setupLatestRate(latestRate);

        vm.warp(latestUpdateTimestamp);
        mYieldToAllAssignment.setLatestUpdateTimestamp(latestUpdateTimestamp);

        // No change in timestamp, so the index should be equal to the latest stored index
        assertEq(mYieldToAllAssignment.currentIndex(), latestIndex);

        vm.warp(nextTimestamp);

        uint128 expectedIndex = isEarningEnabled
            ? _getCurrentIndex(latestIndex, latestRate, latestUpdateTimestamp)
            : latestIndex;

        // allow tiny rounding drift at fuzz edges
        assertApproxEqAbs(mYieldToAllAssignment.currentIndex(), expectedIndex, 8);

        vm.assume(finalTimestamp > nextTimestamp);

        vm.mockCall(
            address(mToken),
            abi.encodeWithSelector(IMTokenLike.earnerRate.selector),
            abi.encode(nextEarnerRate)
        );

        latestRate = mYieldToAllAssignment.latestRate();
        latestRate = _setupLatestRate(latestRate);

        vm.warp(finalTimestamp);

        // expectedIndex was saved as the latest index and nextTimestamp is the latest saved timestamp
        expectedIndex = isEarningEnabled ? _getCurrentIndex(expectedIndex, latestRate, nextTimestamp) : latestIndex;
        assertApproxEqAbs(mYieldToAllAssignment.currentIndex(), expectedIndex, 2);
    }

    /* ============ _latestEarnerRateAccrualTimestamp ============ */

    function test_latestEarnerRateAccrualTimestamp() external {
        uint40 timestamp = uint40(22470340);

        vm.warp(timestamp);

        assertEq(mYieldToAllAssignment.latestEarnerRateAccrualTimestamp(), timestamp);
    }

    /* ============ _currentEarnerRate ============ */

    function test_currentEarnerRate() external {
        uint32 earnerRate = RAW_RATE;

        vm.mockCall(address(mToken), abi.encodeWithSelector(IMTokenLike.earnerRate.selector), abi.encode(earnerRate));

        assertEq(mYieldToAllAssignment.currentEarnerRate(), earnerRate);
    }

    /* ============ accruedYieldOf ============ */

    function test_accruedYieldOf() external {
        mYieldToAllAssignment.setIsEarningEnabled(true);
        mYieldToAllAssignment.setLatestRate(RAW_RATE);
        mYieldToAllAssignment.setLatestUpdateTimestamp(startTimestamp);

        // advance ~1y
        vm.warp(startTimestamp + 30_057_038);
        uint128 expected = _getCurrentIndex(EXP_SCALED_ONE, RAW_RATE, startTimestamp);
        assertEq(mYieldToAllAssignment.currentIndex(), expected);

        mYieldToAllAssignment.setAccountOf(alice, 500, 500);
        uint256 y1 = mYieldToAllAssignment.accruedYieldOf(alice);
        assertEq(mYieldToAllAssignment.balanceWithYieldOf(alice), 500 + y1);

        mYieldToAllAssignment.setAccountOf(alice, 1_000, 1_000);
        uint256 y2 = mYieldToAllAssignment.accruedYieldOf(alice);
        assertEq(mYieldToAllAssignment.balanceWithYieldOf(alice), 1_000 + y2);

        // advance again
        vm.warp(startTimestamp + 30_057_038 * 2);
        assertEq(mYieldToAllAssignment.currentIndex(), _getCurrentIndex(EXP_SCALED_ONE, RAW_RATE, startTimestamp));

        uint256 y3 = mYieldToAllAssignment.accruedYieldOf(alice);
        assertEq(mYieldToAllAssignment.balanceWithYieldOf(alice), 1_000 + y3);

        // change principal scenario
        mYieldToAllAssignment.setAccountOf(alice, 1_000, 1_500);
        uint256 y4 = mYieldToAllAssignment.accruedYieldOf(alice);
        assertEq(mYieldToAllAssignment.balanceWithYieldOf(alice), 1_000 + y4);
    }

    function testFuzz_accruedYieldOf(
        bool earningEnabled,
        uint16 /* feeRate (unused) */,
        uint128 latestIndex,
        uint240 balanceWithYield,
        uint240 balance,
        uint40 nextTimestamp,
        uint40 finalTimestamp
    ) external {
        uint128 currentIndex = _setupIndex(earningEnabled, latestIndex);
        (balanceWithYield, balance) = _getFuzzedBalances(
            currentIndex,
            balanceWithYield,
            balance,
            _getMaxAmount(currentIndex)
        );

        uint112 principal = _setupAccount(alice, balanceWithYield, balance);
        (, uint240 expectedYield) = _getBalanceWithYield(balance, principal, currentIndex);

        assertEq(mYieldToAllAssignment.accruedYieldOf(alice), expectedYield);

        vm.assume(finalTimestamp > nextTimestamp);

        vm.warp(finalTimestamp);

        (, expectedYield) = _getBalanceWithYield(balance, principal, mYieldToAllAssignment.currentIndex());
        assertEq(mYieldToAllAssignment.accruedYieldOf(alice), expectedYield);
    }

    /* ============ balanceOf ============ */

    function test_balanceOf() external {
        uint240 balance = 1_000e6;
        mYieldToAllAssignment.setAccountOf(alice, balance, 800e6);

        assertEq(mYieldToAllAssignment.balanceOf(alice), balance);
    }

    /* ============ balanceWithYieldOf ============ */

    function test_balanceWithYieldOf() external {
        mYieldToAllAssignment.setIsEarningEnabled(true);
        mYieldToAllAssignment.setLatestRate(RAW_RATE);
        mYieldToAllAssignment.setLatestUpdateTimestamp(startTimestamp);

        // ~1y
        vm.warp(startTimestamp + 30_057_038);
        uint128 expected = _getCurrentIndex(EXP_SCALED_ONE, RAW_RATE, startTimestamp);
        assertEq(mYieldToAllAssignment.currentIndex(), expected);

        mYieldToAllAssignment.setAccountOf(alice, 500e6, 500e6);
        assertEq(
            mYieldToAllAssignment.balanceWithYieldOf(alice),
            mYieldToAllAssignment.balanceOf(alice) + mYieldToAllAssignment.accruedYieldOf(alice)
        );

        mYieldToAllAssignment.setAccountOf(alice, 1_000e6, 1_000e6);
        assertEq(
            mYieldToAllAssignment.balanceWithYieldOf(alice),
            mYieldToAllAssignment.balanceOf(alice) + mYieldToAllAssignment.accruedYieldOf(alice)
        );

        // advance again
        vm.warp(startTimestamp + 30_057_038 * 2);
        assertEq(mYieldToAllAssignment.currentIndex(), _getCurrentIndex(EXP_SCALED_ONE, RAW_RATE, startTimestamp));

        assertEq(
            mYieldToAllAssignment.balanceWithYieldOf(alice),
            mYieldToAllAssignment.balanceOf(alice) + mYieldToAllAssignment.accruedYieldOf(alice)
        );

        mYieldToAllAssignment.setAccountOf(alice, 1_000e6, 1_500e6);
        assertEq(
            mYieldToAllAssignment.balanceWithYieldOf(alice),
            mYieldToAllAssignment.balanceOf(alice) + mYieldToAllAssignment.accruedYieldOf(alice)
        );
    }

    function testFuzz_balanceWithYieldOf(
        bool earningEnabled,
        uint16 /* feeRate (unused) */,
        uint128 latestIndex,
        uint240 balanceWithYield,
        uint240 balance,
        uint40 nextTimestamp,
        uint40 finalTimestamp
    ) external {
        uint128 currentIndex = _setupIndex(earningEnabled, latestIndex);
        (balanceWithYield, balance) = _getFuzzedBalances(
            currentIndex,
            balanceWithYield,
            balance,
            _getMaxAmount(currentIndex)
        );

        uint112 principal = _setupAccount(alice, balanceWithYield, balance);
        (, uint240 expectedYield) = _getBalanceWithYield(balance, principal, currentIndex);

        assertEq(mYieldToAllAssignment.balanceWithYieldOf(alice), balance + expectedYield);

        vm.assume(finalTimestamp > nextTimestamp);

        vm.warp(finalTimestamp);

        (, expectedYield) = _getBalanceWithYield(balance, principal, mYieldToAllAssignment.currentIndex());
        assertEq(mYieldToAllAssignment.balanceWithYieldOf(alice), balance + expectedYield);
    }

    /* ============ principalOf ============ */

    function test_principalOf() external {
        uint112 principal = 800e6;
        mYieldToAllAssignment.setAccountOf(alice, 1_000e6, principal);

        assertEq(mYieldToAllAssignment.principalOf(alice), principal);
    }

    /* ============ projectedTotalSupply ============ */

    function test_projectedTotalSupply() external {
        mYieldToAllAssignment.setIsEarningEnabled(true);
        mYieldToAllAssignment.setLatestRate(RAW_RATE);
        mYieldToAllAssignment.setLatestUpdateTimestamp(startTimestamp);

        // ~1y
        vm.warp(startTimestamp + 30_057_038);
        uint128 idx = _getCurrentIndex(EXP_SCALED_ONE, RAW_RATE, startTimestamp);
        assertEq(mYieldToAllAssignment.currentIndex(), idx);

        mYieldToAllAssignment.setTotalPrincipal(1_000);
        mYieldToAllAssignment.setTotalSupply(1_000);

        uint256 expectedProjected = IndexingMath.getPresentAmountRoundedUp(1_000, idx);
        assertEq(mYieldToAllAssignment.projectedTotalSupply(), expectedProjected);
    }

    /* ============ totalAccruedYield ============ */

    function test_totalAccruedYield() external {
        mYieldToAllAssignment.setIsEarningEnabled(true);
        mYieldToAllAssignment.setLatestRate(RAW_RATE);
        mYieldToAllAssignment.setLatestUpdateTimestamp(startTimestamp);

        // ~1y
        vm.warp(startTimestamp + 30_057_038);
        uint128 idx = _getCurrentIndex(EXP_SCALED_ONE, RAW_RATE, startTimestamp);
        assertEq(mYieldToAllAssignment.currentIndex(), idx);

        // case 1
        mYieldToAllAssignment.setTotalSupply(500e6);
        mYieldToAllAssignment.setTotalPrincipal(500e6);

        uint256 present1 = IndexingMath.getPresentAmountRoundedDown(500e6, idx);
        uint256 expected1 = present1 > 500e6 ? present1 - 500e6 : 0;
        assertEq(mYieldToAllAssignment.totalAccruedYield(), expected1);

        // case 2
        mYieldToAllAssignment.setTotalSupply(1_000e6);
        mYieldToAllAssignment.setTotalPrincipal(1_000e6);

        uint256 present2 = IndexingMath.getPresentAmountRoundedDown(1_000e6, idx);
        uint256 expected2 = present2 > 1_000e6 ? present2 - 1_000e6 : 0;
        assertEq(mYieldToAllAssignment.totalAccruedYield(), expected2);

        // advance again
        vm.warp(startTimestamp + 30_057_038 * 2);
        uint256 present3 = IndexingMath.getPresentAmountRoundedDown(1_000e6, mYieldToAllAssignment.currentIndex());
        uint256 expected3 = present3 > 1_000e6 ? present3 - 1_000e6 : 0;
        assertEq(mYieldToAllAssignment.totalAccruedYield(), expected3);

        // different principal vs supply
        mYieldToAllAssignment.setTotalSupply(1_000e6);
        mYieldToAllAssignment.setTotalPrincipal(1_500e6);

        uint256 present4 = IndexingMath.getPresentAmountRoundedDown(1_500e6, mYieldToAllAssignment.currentIndex());
        uint256 expected4 = present4 > 1_000e6 ? present4 - 1_000e6 : 0;
        assertEq(mYieldToAllAssignment.totalAccruedYield(), expected4);
    }

    function testFuzz_totalAccruedYield(
        bool earningEnabled,
        uint16 /* feeRate (unused) */,
        uint128 latestIndex,
        uint240 totalSupplyWithYield,
        uint240 totalSupply,
        uint40 nextTimestamp,
        uint40 finalTimestamp
    ) external {
        uint128 currentIndex = _setupIndex(earningEnabled, latestIndex);
        (totalSupplyWithYield, totalSupply) = _getFuzzedBalances(
            currentIndex,
            totalSupplyWithYield,
            totalSupply,
            _getMaxAmount(currentIndex)
        );

        uint112 principal = _setupSupply(totalSupplyWithYield, totalSupply);
        (, uint240 expectedYield) = _getBalanceWithYield(totalSupply, principal, currentIndex);

        assertEq(mYieldToAllAssignment.totalAccruedYield(), expectedYield);

        vm.assume(finalTimestamp > nextTimestamp);

        vm.warp(finalTimestamp);

        (, expectedYield) = _getBalanceWithYield(totalSupply, principal, mYieldToAllAssignment.currentIndex());
        assertEq(mYieldToAllAssignment.totalAccruedYield(), expectedYield);
    }

    /* ============ wrap ============ */

    function test_wrap_insufficientAmount() external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));

        vm.prank(address(swapFacility));
        mYieldToAllAssignment.wrap(alice, 0);
    }

    function test_wrap_invalidRecipient() external {
        mToken.setBalanceOf(alice, 1_000);

        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InvalidRecipient.selector, address(0)));

        vm.prank(address(swapFacility));
        mYieldToAllAssignment.wrap(address(0), 1_000);
    }

    function test_wrap() external {
        mYieldToAllAssignment.setIsEarningEnabled(true);
        mYieldToAllAssignment.setLatestRate(RAW_RATE);
        mYieldToAllAssignment.setLatestUpdateTimestamp(startTimestamp);

        // ~1y
        vm.warp(startTimestamp + 30_057_038);
        uint128 idx = _getCurrentIndex(EXP_SCALED_ONE, RAW_RATE, startTimestamp);
        assertEq(mYieldToAllAssignment.currentIndex(), idx);

        mToken.setBalanceOf(address(swapFacility), 1_002);
        mToken.setBalanceOf(address(mYieldToAllAssignment), 1_100);

        // set totals and alice
        mYieldToAllAssignment.setTotalPrincipal(1_000);
        mYieldToAllAssignment.setTotalSupply(1_000);
        mYieldToAllAssignment.setAccountOf(alice, 1_000, 1_000);

        uint112 p0 = mYieldToAllAssignment.principalOf(alice);
        uint256 b0 = mYieldToAllAssignment.balanceOf(alice);
        uint256 y0 = mYieldToAllAssignment.accruedYieldOf(alice);
        assertEq(mYieldToAllAssignment.balanceWithYieldOf(alice), b0 + y0);

        // wrap 999
        vm.expectEmit();
        emit IERC20.Transfer(address(0), alice, 999);
        vm.prank(address(swapFacility));
        mYieldToAllAssignment.wrap(alice, 999);

        uint112 pAdd999 = IndexingMath.getPrincipalAmountRoundedDown(999, idx);
        assertEq(mYieldToAllAssignment.principalOf(alice), p0 + pAdd999);
        assertEq(mYieldToAllAssignment.balanceOf(alice), b0 + 999);
        assertEq(mYieldToAllAssignment.totalSupply(), (1_000) + 999);

        // wrap 1
        vm.expectEmit();
        emit IERC20.Transfer(address(0), alice, 1);
        vm.prank(address(swapFacility));
        mYieldToAllAssignment.wrap(alice, 1);

        uint112 pAfter1 = p0 + pAdd999 + IndexingMath.getPrincipalAmountRoundedDown(1, idx);
        assertEq(mYieldToAllAssignment.principalOf(alice), pAfter1);
        assertEq(mYieldToAllAssignment.balanceOf(alice), b0 + 999 + 1);

        // wrap 2
        vm.expectEmit();
        emit IERC20.Transfer(address(0), alice, 2);
        vm.prank(address(swapFacility));
        mYieldToAllAssignment.wrap(alice, 2);

        uint112 pAfter2 = pAfter1 + IndexingMath.getPrincipalAmountRoundedDown(2, idx);
        assertEq(mYieldToAllAssignment.principalOf(alice), pAfter2);
        assertEq(mYieldToAllAssignment.balanceOf(alice), b0 + 999 + 1 + 2);

        // invariants
        assertEq(
            mYieldToAllAssignment.balanceWithYieldOf(alice),
            mYieldToAllAssignment.balanceOf(alice) + mYieldToAllAssignment.accruedYieldOf(alice)
        );
        // totals stay in sync within rounding
        assertApproxEqAbs(
            mYieldToAllAssignment.totalPrincipal(),
            mYieldToAllAssignment.principalOf(alice),
            1
        );
    }

    function testFuzz_wrap(
        bool earningEnabled,
        uint16 /* feeRate (unused) */,
        uint128 latestIndex,
        uint240 balanceWithYield,
        uint240 balance,
        uint240 wrapAmount
    ) external {
        uint128 currentIndex = _setupIndex(earningEnabled, latestIndex);
        (balanceWithYield, balance) = _getFuzzedBalances(
            currentIndex,
            balanceWithYield,
            balance,
            _getMaxAmount(currentIndex)
        );

        _setupAccount(alice, balanceWithYield, balance);
        wrapAmount = uint240(bound(wrapAmount, 0, _getMaxAmount(currentIndex) - balanceWithYield));

        mToken.setBalanceOf(address(swapFacility), wrapAmount);

        if (wrapAmount == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, (0)));
        } else {
            vm.expectEmit();
            emit IERC20.Transfer(address(0), alice, wrapAmount);
        }

        vm.prank(address(swapFacility));
        mYieldToAllAssignment.wrap(alice, wrapAmount);

        if (wrapAmount == 0) return;

        balance += wrapAmount;

        // When wrapping, added principal for account is always rounded down in favor of the protocol.
        balanceWithYield = IndexingMath.getPresentAmountRoundedDown(
            IndexingMath.getPrincipalAmountRoundedDown(balanceWithYield, currentIndex) +
                IndexingMath.getPrincipalAmountRoundedDown(wrapAmount, currentIndex),
            currentIndex
        );

        uint256 aliceYield = balanceWithYield <= balance ? 0 : balanceWithYield - balance;

        assertEq(mYieldToAllAssignment.balanceOf(alice), balance);
        assertEq(mYieldToAllAssignment.balanceOf(alice), mYieldToAllAssignment.totalSupply());

        // Rounds down on wrap for alice and up for total principal.
        assertApproxEqAbs(mYieldToAllAssignment.principalOf(alice), mYieldToAllAssignment.totalPrincipal(), 1);

        assertEq(mYieldToAllAssignment.balanceWithYieldOf(alice), balance + aliceYield);
        assertEq(mYieldToAllAssignment.balanceWithYieldOf(alice), balance + mYieldToAllAssignment.accruedYieldOf(alice));

        // Simulate M token balance (not used by contract logic in assertions anymore)
        mToken.setBalanceOf(address(mYieldToAllAssignment), balance + aliceYield);

        // projectedTotalSupply rounds up in favor of the protocol
        assertApproxEqAbs(mYieldToAllAssignment.balanceWithYieldOf(alice), mYieldToAllAssignment.projectedTotalSupply(), 17);
        assertEq(mYieldToAllAssignment.totalAccruedYield(), aliceYield);
    }

    /* ============ unwrap ============ */

    function test_unwrap() external {
        mYieldToAllAssignment.setIsEarningEnabled(true);
        mYieldToAllAssignment.setLatestRate(RAW_RATE);
        mYieldToAllAssignment.setLatestUpdateTimestamp(startTimestamp);

        // ~1y
        vm.warp(startTimestamp + 30_057_038);
        uint128 idx = _getCurrentIndex(EXP_SCALED_ONE, RAW_RATE, startTimestamp);
        assertEq(mYieldToAllAssignment.currentIndex(), idx);

        mToken.setBalanceOf(address(mYieldToAllAssignment), 1_100);

        mYieldToAllAssignment.setTotalPrincipal(1_000);
        mYieldToAllAssignment.setTotalSupply(1_000);

        mYieldToAllAssignment.setAccountOf(address(swapFacility), 1_000, 1_000); // account with balance

        uint112 p0 = mYieldToAllAssignment.principalOf(address(swapFacility));
        uint256 b0 = mYieldToAllAssignment.balanceOf(address(swapFacility));
        uint256 y0 = mYieldToAllAssignment.accruedYieldOf(address(swapFacility));
        assertEq(mYieldToAllAssignment.balanceWithYieldOf(address(swapFacility)), b0 + y0);

        vm.prank(alice);
        mYieldToAllAssignment.approve(address(swapFacility), 1_000);

        // burn 1
        vm.expectEmit();
        emit IERC20.Transfer(address(swapFacility), address(0), 1);
        vm.prank(address(swapFacility));
        mYieldToAllAssignment.unwrap(alice, 1);

        // burn 499
        vm.expectEmit();
        emit IERC20.Transfer(address(swapFacility), address(0), 499);
        vm.prank(address(swapFacility));
        mYieldToAllAssignment.unwrap(alice, 499);

        // burn 500 (drain)
        vm.expectEmit();
        emit IERC20.Transfer(address(swapFacility), address(0), 500);
        vm.prank(address(swapFacility));
        mYieldToAllAssignment.unwrap(alice, 500);

        // drained
        assertEq(mYieldToAllAssignment.balanceOf(address(swapFacility)), 0);
        // M tokens are sent to SwapFacility and then forwarded to Alice
        assertEq(mToken.balanceOf(alice), 0);
    }

    function testFuzz_unwrap(
        bool earningEnabled,
        uint16 /* feeRate (unused) */,
        uint128 latestIndex,
        uint240 balanceWithYield,
        uint240 balance,
        uint240 unwrapAmount
    ) external {
        uint128 currentIndex = _setupIndex(earningEnabled, latestIndex);
        (balanceWithYield, balance) = _getFuzzedBalances(
            currentIndex,
            balanceWithYield,
            balance,
            _getMaxAmount(currentIndex)
        );

        _setupAccount(address(swapFacility), balanceWithYield, balance);
        unwrapAmount = uint240(bound(unwrapAmount, 0, _getMaxAmount(currentIndex) - balanceWithYield));

        mToken.setBalanceOf(address(mYieldToAllAssignment), balanceWithYield);

        vm.prank(alice);
        mYieldToAllAssignment.approve(address(swapFacility), unwrapAmount);

        if (unwrapAmount == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, (0)));
        } else if (unwrapAmount > balance) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IMExtension.InsufficientBalance.selector,
                    address(swapFacility),
                    balance,
                    unwrapAmount
                )
            );
        } else {
            vm.expectEmit();
            emit IERC20.Transfer(address(swapFacility), address(0), unwrapAmount);
        }

        vm.prank(address(swapFacility));
        mYieldToAllAssignment.unwrap(alice, unwrapAmount);

        if ((unwrapAmount == 0) || (unwrapAmount > balance)) return;

        balance -= unwrapAmount;

        uint112 balanceWithYieldPrincipal = IndexingMath.getPrincipalAmountRoundedDown(balanceWithYield, currentIndex);

        // When unwrapping, subtracted principal for account is always rounded up in favor of the protocol.
        balanceWithYield = IndexingMath.getPresentAmountRoundedDown(
            balanceWithYieldPrincipal -
                UIntMath.min112(
                    IndexingMath.getPrincipalAmountRoundedUp(unwrapAmount, currentIndex),
                    balanceWithYieldPrincipal
                ),
            currentIndex
        );

        uint256 aliceYield = (balanceWithYield <= balance) ? 0 : balanceWithYield - balance;

        assertEq(mYieldToAllAssignment.balanceOf(address(swapFacility)), balance);
        assertEq(mYieldToAllAssignment.balanceOf(address(swapFacility)), mYieldToAllAssignment.totalSupply());

        // Rounds up on unwrap for alice and down for total principal.
        assertApproxEqAbs(mYieldToAllAssignment.principalOf(address(swapFacility)), mYieldToAllAssignment.totalPrincipal(), 1);

        assertEq(mYieldToAllAssignment.balanceWithYieldOf(address(swapFacility)), balance + aliceYield);
        assertEq(
            mYieldToAllAssignment.balanceWithYieldOf(address(swapFacility)),
            balance + mYieldToAllAssignment.accruedYieldOf(address(swapFacility))
        );

        // Simulate M token balance.
        mToken.setBalanceOf(address(mYieldToAllAssignment), balance + aliceYield);

        assertApproxEqAbs(mYieldToAllAssignment.balanceWithYieldOf(address(swapFacility)), mYieldToAllAssignment.projectedTotalSupply(), 15);
        assertEq(mYieldToAllAssignment.totalAccruedYield(), aliceYield);

        // M tokens are sent to SwapFacility and then forwarded to Alice
        assertEq(mToken.balanceOf(address(swapFacility)), unwrapAmount);
        assertEq(mToken.balanceOf(alice), 0);
    }

    /* ============ transfer ============ */

    function test_transfer_invalidRecipient() external {
        mYieldToAllAssignment.setAccountOf(alice, 1_000, 1_000);

        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InvalidRecipient.selector, address(0)));

        vm.prank(alice);
        mYieldToAllAssignment.transfer(address(0), 1_000);
    }

    function test_transfer_insufficientBalance_toSelf() external {
        mYieldToAllAssignment.setAccountOf(alice, 999, 999);

        vm.expectRevert(abi.encodeWithSelector(IMExtension.InsufficientBalance.selector, alice, 999, 1_000));

        vm.prank(alice);
        mYieldToAllAssignment.transfer(alice, 1_000);
    }

    function test_transfer_insufficientBalance() external {
        mYieldToAllAssignment.setAccountOf(alice, 999, 999);

        vm.expectRevert(abi.encodeWithSelector(IMExtension.InsufficientBalance.selector, alice, 999, 1_000));

        vm.prank(alice);
        mYieldToAllAssignment.transfer(bob, 1_000);
    }

    function test_transfer() external {
        mYieldToAllAssignment.setIsEarningEnabled(true);
        mYieldToAllAssignment.setLatestRate(RAW_RATE);
        mYieldToAllAssignment.setLatestUpdateTimestamp(startTimestamp);

        // ~1y
        vm.warp(startTimestamp + 30_057_038);
        uint128 idx = _getCurrentIndex(EXP_SCALED_ONE, RAW_RATE, startTimestamp);
        assertEq(mYieldToAllAssignment.currentIndex(), idx);

        mToken.setBalanceOf(alice, 1_002);
        mToken.setBalanceOf(address(mYieldToAllAssignment), 1_500);

        mYieldToAllAssignment.setTotalPrincipal(1_500);
        mYieldToAllAssignment.setTotalSupply(1_500);

        mYieldToAllAssignment.setAccountOf(alice, 1_000, 1_000);
        mYieldToAllAssignment.setAccountOf(bob, 500, 500);

        uint112 pAlice0 = mYieldToAllAssignment.principalOf(alice);
        uint112 pBob0 = mYieldToAllAssignment.principalOf(bob);
        uint256 bAlice0 = mYieldToAllAssignment.balanceOf(alice);
        uint256 bBob0 = mYieldToAllAssignment.balanceOf(bob);

        vm.expectEmit();
        emit IERC20.Transfer(alice, bob, 500);

        vm.prank(alice);
        mYieldToAllAssignment.transfer(bob, 500);

        // principal moves with rounding up from sender, down to recipient
        uint112 pMoveUp = IndexingMath.getPrincipalAmountRoundedUp(500, idx);
        uint112 pMoveDown = IndexingMath.getPrincipalAmountRoundedDown(500, idx);

        // tolerate ±1 rounding in state vs. local calc
        assertApproxEqAbs(mYieldToAllAssignment.principalOf(alice), uint256(pAlice0 - pMoveUp), 1);
        assertApproxEqAbs(mYieldToAllAssignment.principalOf(bob), uint256(pBob0 + pMoveDown), 1);

        assertEq(mYieldToAllAssignment.balanceOf(alice), bAlice0 - 500);
        assertEq(mYieldToAllAssignment.balanceOf(bob), bBob0 + 500);

        assertEq(mYieldToAllAssignment.totalSupply(), 1_500);

        // total principal stays close within rounding (up on add, down on sub)
        assertApproxEqAbs(
            mYieldToAllAssignment.totalPrincipal(),
            (pAlice0 - pMoveUp) + (pBob0 + pMoveDown),
            2
        );

        // yields are consistent with balances
        assertEq(
            mYieldToAllAssignment.balanceWithYieldOf(alice),
            mYieldToAllAssignment.balanceOf(alice) + mYieldToAllAssignment.accruedYieldOf(alice)
        );
        assertEq(
            mYieldToAllAssignment.balanceWithYieldOf(bob),
            mYieldToAllAssignment.balanceOf(bob) + mYieldToAllAssignment.accruedYieldOf(bob)
        );
    }

    function test_transfer_toSelf() external {
        mYieldToAllAssignment.setIsEarningEnabled(true);
        mYieldToAllAssignment.setLatestRate(RAW_RATE);
        mYieldToAllAssignment.setLatestUpdateTimestamp(startTimestamp);

        // ~1y
        vm.warp(startTimestamp + 30_057_038);
        uint128 idx = _getCurrentIndex(EXP_SCALED_ONE, RAW_RATE, startTimestamp);
        assertEq(mYieldToAllAssignment.currentIndex(), idx);

        mYieldToAllAssignment.setTotalPrincipal(1_000);
        mYieldToAllAssignment.setTotalSupply(1_000);
        mToken.setBalanceOf(address(mYieldToAllAssignment), 1_125);

        mYieldToAllAssignment.setAccountOf(alice, 1_000, 1_000);

        uint112 p0 = mYieldToAllAssignment.principalOf(alice);
        uint256 b0 = mYieldToAllAssignment.balanceOf(alice);
        uint256 y0 = mYieldToAllAssignment.accruedYieldOf(alice);

        vm.expectEmit();
        emit IERC20.Transfer(alice, alice, 500);

        vm.prank(alice);
        mYieldToAllAssignment.transfer(alice, 500);

        assertEq(mYieldToAllAssignment.principalOf(alice), p0);
        assertEq(mYieldToAllAssignment.balanceOf(alice), b0);
        assertEq(mYieldToAllAssignment.accruedYieldOf(alice), y0);

        assertEq(mYieldToAllAssignment.totalPrincipal(), 1_000);
        assertEq(mYieldToAllAssignment.totalSupply(), 1_000);

        // projected == balanceWithYield with rounding up on supply projection
        assertApproxEqAbs(
            mYieldToAllAssignment.projectedTotalSupply(),
            mYieldToAllAssignment.balanceWithYieldOf(alice),
            1
        );
    }

    function testFuzz_transfer(
        bool earningEnabled,
        uint16 /* feeRate (unused) */,
        uint128 latestIndex,
        uint240 aliceBalanceWithYield,
        uint240 aliceBalance,
        uint240 bobBalanceWithYield,
        uint240 bobBalance,
        uint240 amount
    ) external {
        uint128 currentIndex = _setupIndex(earningEnabled, latestIndex);
        (aliceBalanceWithYield, aliceBalance) = _getFuzzedBalances(
            currentIndex,
            aliceBalanceWithYield,
            aliceBalance,
            _getMaxAmount(currentIndex)
        );

        (bobBalanceWithYield, bobBalance) = _getFuzzedBalances(
            currentIndex,
            bobBalanceWithYield,
            bobBalance,
            _getMaxAmount(currentIndex) - aliceBalanceWithYield
        );

        _setupAccount(alice, aliceBalanceWithYield, aliceBalance);
        _setupAccount(bob, bobBalanceWithYield, bobBalance);

        amount = uint240(bound(amount, 0, _getMaxAmount(currentIndex) - bobBalanceWithYield));

        if (amount > aliceBalance) {
            vm.expectRevert(
                abi.encodeWithSelector(IMExtension.InsufficientBalance.selector, alice, aliceBalance, amount)
            );
        } else {
            vm.expectEmit();
            emit IERC20.Transfer(alice, bob, amount);
        }

        vm.prank(alice);
        mYieldToAllAssignment.transfer(bob, amount);

        if (amount > aliceBalance) return;

        aliceBalance -= amount;
        bobBalance += amount;

        assertEq(mYieldToAllAssignment.balanceOf(alice), aliceBalance);
        assertEq(mYieldToAllAssignment.balanceOf(bob), bobBalance);
        assertEq(mYieldToAllAssignment.totalSupply(), aliceBalance + bobBalance);
        assertEq(mYieldToAllAssignment.totalSupply(), mYieldToAllAssignment.balanceOf(alice) + mYieldToAllAssignment.balanceOf(bob));

        uint112 aliceBalanceWithYieldPrincipal = IndexingMath.getPrincipalAmountRoundedDown(
            aliceBalanceWithYield,
            currentIndex
        );

        aliceBalanceWithYieldPrincipal =
            aliceBalanceWithYieldPrincipal -
            UIntMath.min112(
                IndexingMath.getPrincipalAmountRoundedUp(amount, currentIndex),
                aliceBalanceWithYieldPrincipal
            );

        // sender principal after transfer
        aliceBalanceWithYield = IndexingMath.getPresentAmountRoundedDown(aliceBalanceWithYieldPrincipal, currentIndex);

        uint112 bobBalanceWithYieldPrincipal = IndexingMath.getPrincipalAmountRoundedDown(
            bobBalanceWithYield,
            currentIndex
        ) + IndexingMath.getPrincipalAmountRoundedDown(amount, currentIndex);

        // recipient principal after transfer
        bobBalanceWithYield = IndexingMath.getPresentAmountRoundedDown(bobBalanceWithYieldPrincipal, currentIndex);

        uint240 aliceYield = aliceBalanceWithYield <= aliceBalance ? 0 : aliceBalanceWithYield - aliceBalance;
        uint240 bobYield = bobBalanceWithYield <= bobBalance ? 0 : bobBalanceWithYield - bobBalance;

        assertEq(mYieldToAllAssignment.balanceWithYieldOf(alice), aliceBalance + aliceYield);
        assertEq(mYieldToAllAssignment.balanceWithYieldOf(alice), aliceBalance + mYieldToAllAssignment.accruedYieldOf(alice));

        // Bob may gain more due to rounding.
        assertApproxEqAbs(mYieldToAllAssignment.balanceWithYieldOf(bob), bobBalance + bobYield, 10);
        assertEq(mYieldToAllAssignment.balanceWithYieldOf(bob), bobBalance + mYieldToAllAssignment.accruedYieldOf(bob));

        // Principal rounding behavior
        assertApproxEqAbs(mYieldToAllAssignment.totalPrincipal(), aliceBalanceWithYieldPrincipal + bobBalanceWithYieldPrincipal, 2);
        assertApproxEqAbs(mYieldToAllAssignment.totalPrincipal(), mYieldToAllAssignment.principalOf(alice) + mYieldToAllAssignment.principalOf(bob), 2);

        // Simulate M token balance.
        uint256 mBalance = aliceBalance + aliceYield + bobBalance + bobYield;
        mToken.setBalanceOf(address(mYieldToAllAssignment), mBalance);

        // projectedTotalSupply rounds up in favor of the protocol
        assertApproxEqAbs(
            mYieldToAllAssignment.projectedTotalSupply(),
            mYieldToAllAssignment.balanceWithYieldOf(alice) + mYieldToAllAssignment.balanceWithYieldOf(bob),
            16
        );
    }

    /* ============ currentIndex Utils ============ */

    function _getCurrentIndex(
        uint128 latestIndex,
        uint32 latestRate,
        uint40 latestUpdateTimestamp
    ) internal view returns (uint128) {
        return
            UIntMath.bound128(
                ContinuousIndexingMath.multiplyIndicesDown(
                    latestIndex,
                    ContinuousIndexingMath.getContinuousIndex(
                        ContinuousIndexingMath.convertFromBasisPoints(latestRate),
                        uint32(mYieldToAllAssignment.latestEarnerRateAccrualTimestamp() - latestUpdateTimestamp)
                    )
                )
            );
    }

    /* ============ Fuzz Utils ============ */

    function _setupAccount(
        address account,
        uint240 balanceWithYield,
        uint240 balance
    ) internal returns (uint112 principal_) {
        principal_ = IndexingMath.getPrincipalAmountRoundedDown(balanceWithYield, mYieldToAllAssignment.currentIndex());

        mYieldToAllAssignment.setAccountOf(account, balance, principal_);
        mYieldToAllAssignment.setTotalPrincipal(mYieldToAllAssignment.totalPrincipal() + principal_);
        mYieldToAllAssignment.setTotalSupply(mYieldToAllAssignment.totalSupply() + balance);
    }

    function _setupSupply(uint240 totalSupplyWithYield, uint240 totalSupply) internal returns (uint112 principal_) {
        principal_ = IndexingMath.getPrincipalAmountRoundedDown(totalSupplyWithYield, mYieldToAllAssignment.currentIndex());

        mYieldToAllAssignment.setTotalPrincipal(mYieldToAllAssignment.totalPrincipal() + principal_);
        mYieldToAllAssignment.setTotalSupply(mYieldToAllAssignment.totalSupply() + totalSupply);
    }

    function _setupLatestRate(uint32 rate) internal returns (uint32) {
        rate = uint32(bound(rate, 10, 10_000));
        mYieldToAllAssignment.setLatestRate(rate);
        return rate;
    }

    function _setupLatestIndex(uint128 latestIndex) internal returns (uint128) {
        latestIndex = uint128(bound(latestIndex, EXP_SCALED_ONE, 10_000000000000));
        mYieldToAllAssignment.setLatestIndex(latestIndex);
        return latestIndex;
    }

    function _setupIndex(bool earningEnabled, uint128 latestIndex) internal returns (uint128) {
        uint128 bounded =
            uint128(bound(uint256(latestIndex), uint256(EXP_SCALED_ONE), 10_000000000000));

        mYieldToAllAssignment.setLatestIndex(bounded);
        mYieldToAllAssignment.setIsEarningEnabled(earningEnabled);
        return mYieldToAllAssignment.currentIndex();
    }

    /* ============ whitelist tests ============ */

    function test_whitelistAddress() external {
        // default setUp whitelists alice, unset then re-set here to exercise function
        vm.prank(whitelistManager);
        mYieldToAllAssignment.whitelistAddress(alice, false);
        assertFalse(mYieldToAllAssignment.isWhitelisted(alice));

        vm.prank(whitelistManager);
        mYieldToAllAssignment.whitelistAddress(alice, true);
        assertTrue(mYieldToAllAssignment.isWhitelisted(alice));
    }

    function test_wrap_requiresRecipientWhitelisted() external {
        // reset: remove alice then try wrap -> revert, then add back and succeed
        vm.prank(whitelistManager);
        mYieldToAllAssignment.whitelistAddress(alice, false);

        mYieldToAllAssignment.setIsEarningEnabled(true);
        mYieldToAllAssignment.setLatestRate(/* some rate */ 400);
        mYieldToAllAssignment.setLatestUpdateTimestamp(startTimestamp);
        mToken.setBalanceOf(address(swapFacility), 100);

        // Not whitelisted -> revert
        vm.expectRevert(IMYieldToAllAssignment.AddressNotWhitelisted.selector);
        vm.prank(address(swapFacility));
        mYieldToAllAssignment.wrap(alice, 100);

        // Whitelist recipient -> works
        vm.prank(whitelistManager);
        mYieldToAllAssignment.whitelistAddress(alice, true);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), alice, 100);
        vm.prank(address(swapFacility));
        mYieldToAllAssignment.wrap(alice, 100);
    }

    function test_unwrap_requiresSenderWhitelisted() external {
        // unwrap burns from msg.sender (swapFacility), not the 'account' param.
        // give sender (swapFacility) a balance, then de-whitelist sender and expect revert.
        mYieldToAllAssignment.setAccountOf(address(swapFacility), 10, 10);

        // sender is currently whitelisted from setUp -> remove it
        vm.prank(whitelistManager);
        mYieldToAllAssignment.whitelistAddress(address(swapFacility), false);

        // call unwrap as the (now non-whitelisted) holder
        vm.expectRevert(IMYieldToAllAssignment.AddressNotWhitelisted.selector);
        vm.prank(address(swapFacility));
        mYieldToAllAssignment.unwrap(alice, 1);
    }
}
