// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { ContinuousIndexingMath } from "../../../../lib/common/src/libs/ContinuousIndexingMath.sol";
import { IndexingMath } from "../../../../lib/common/src/libs/IndexingMath.sol";
import { UIntMath } from "../../../../lib/common/src/libs/UIntMath.sol";

import { Upgrades, UnsafeUpgrades } from "../../../../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { IMTokenLike } from "../../../../src/interfaces/IMTokenLike.sol";

import { IContinuousIndexing } from "../../../../src/projects/yieldToAllWithFee/interfaces/IContinuousIndexing.sol";
import { IRateOracle } from "../../../../src/projects/yieldToAllWithFee/interfaces/IRateOracle.sol";
import { IMSpokeYieldFee } from "../../../../src/projects/yieldToAllWithFee/interfaces/IMSpokeYieldFee.sol";

import { MSpokeYieldFeeHarness } from "../../../harness/MSpokeYieldFeeHarness.sol";
import { BaseUnitTest } from "../../../utils/BaseUnitTest.sol";

contract MSpokeYieldFeeUnitTests is BaseUnitTest {
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");

    MSpokeYieldFeeHarness public mYieldFee;

    function setUp() public override {
        super.setUp();

        mYieldFee = MSpokeYieldFeeHarness(
            Upgrades.deployUUPSProxy(
                "MSpokeYieldFeeHarness.sol:MSpokeYieldFeeHarness",
                abi.encodeWithSelector(
                    MSpokeYieldFeeHarness.initialize.selector,
                    "MSpokeYieldFee",
                    "MSYF",
                    address(mToken),
                    address(swapFacility),
                    YIELD_FEE_RATE,
                    feeRecipient,
                    admin,
                    yieldFeeManager,
                    claimRecipientManager,
                    address(rateOracle)
                )
            )
        );

        rateOracle.setEarnerRate(M_EARNER_RATE);
    }

    /* ============ initialize ============ */

    function test_initialize() external view {
        assertEq(mYieldFee.ONE_HUNDRED_PERCENT(), 10_000);
        assertEq(mYieldFee.latestIndex(), EXP_SCALED_ONE);
        assertEq(mYieldFee.feeRate(), YIELD_FEE_RATE);
        assertEq(mYieldFee.feeRecipient(), feeRecipient);
        assertTrue(mYieldFee.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(mYieldFee.hasRole(FEE_MANAGER_ROLE, yieldFeeManager));
        assertEq(mYieldFee.rateOracle(), address(rateOracle));
    }

    function test_initialize_zeroRateOracle() external {
        address implementation = address(new MSpokeYieldFeeHarness());

        vm.expectRevert(IMSpokeYieldFee.ZeroRateOracle.selector);
        MSpokeYieldFeeHarness(
            UnsafeUpgrades.deployUUPSProxy(
                implementation,
                abi.encodeWithSelector(
                    MSpokeYieldFeeHarness.initialize.selector,
                    "MSpokeYieldFee",
                    "MSYF",
                    address(mToken),
                    address(swapFacility),
                    YIELD_FEE_RATE,
                    feeRecipient,
                    admin,
                    yieldFeeManager,
                    claimRecipientManager,
                    address(0)
                )
            )
        );
    }

    /* ============ currentIndex ============ */

    function test_currentIndex() external {
        mYieldFee.setLatestRate(mYiedFeeEarnerRate);

        uint256 expectedIndex = EXP_SCALED_ONE;
        assertEq(mYieldFee.currentIndex(), expectedIndex);

        uint40 previousTimestamp = uint40(startTimestamp);
        uint40 nextTimestamp = uint40(vm.getBlockTimestamp() + 365 days);

        vm.warp(nextTimestamp);

        mToken.setLatestUpdateTimestamp(nextTimestamp);
        expectedCurrentIndex = _getCurrentIndex(EXP_SCALED_ONE, mYiedFeeEarnerRate, startTimestamp);

        assertEq(mYieldFee.currentIndex(), expectedCurrentIndex);
        assertEq(mYieldFee.updateIndex(), expectedCurrentIndex);

        previousTimestamp = nextTimestamp;
        nextTimestamp = uint40(vm.getBlockTimestamp() + 365 days * 2);

        vm.warp(nextTimestamp);

        mToken.setLatestUpdateTimestamp(nextTimestamp);
        expectedCurrentIndex = _getCurrentIndex(expectedCurrentIndex, mYiedFeeEarnerRate, previousTimestamp);

        assertEq(mYieldFee.currentIndex(), expectedCurrentIndex);

        // Half the earner rate
        rateOracle.setEarnerRate(M_EARNER_RATE / 2);
        mYiedFeeEarnerRate = _getEarnerRate(M_EARNER_RATE / 2, YIELD_FEE_RATE);

        assertEq(mYieldFee.updateIndex(), expectedCurrentIndex);
        assertEq(mYieldFee.latestRate(), mYiedFeeEarnerRate);

        previousTimestamp = nextTimestamp;
        nextTimestamp = uint40(vm.getBlockTimestamp() + 365 days * 3);

        vm.warp(nextTimestamp);

        mToken.setLatestUpdateTimestamp(nextTimestamp);
        expectedCurrentIndex = _getCurrentIndex(expectedCurrentIndex, mYiedFeeEarnerRate, previousTimestamp);

        assertEq(mYieldFee.currentIndex(), expectedCurrentIndex);
        assertEq(mYieldFee.updateIndex(), expectedCurrentIndex);

        // Disable earning
        mYieldFee.disableEarning();

        previousTimestamp = nextTimestamp;

        nextTimestamp = uint40(vm.getBlockTimestamp() + 365 days * 4);
        vm.warp(nextTimestamp);

        // Index should not change
        assertEq(mYieldFee.currentIndex(), expectedCurrentIndex);

        // TODO: uncomment once updateIndex H01 bug has been fixed
        // assertEq(mYieldFee.updateIndex(), expectedCurrentIndex);

        // Re-enable earning
        mYieldFee.enableEarning();

        // mYiedFeeEarnerRate = _getEarnerRate(M_EARNER_RATE, YIELD_FEE_RATE);
        // mYieldFee.setLatestRate(mYiedFeeEarnerRate);
        assertEq(mYieldFee.latestRate(), mYiedFeeEarnerRate);

        // Index was just re-enabled, so value should still be the same
        assertEq(mYieldFee.updateIndex(), expectedCurrentIndex);
        assertEq(mYieldFee.currentIndex(), expectedCurrentIndex);

        nextTimestamp = uint40(vm.getBlockTimestamp() + 365 days * 5);
        vm.warp(nextTimestamp);

        mToken.setLatestUpdateTimestamp(nextTimestamp);
        expectedCurrentIndex = _getCurrentIndex(expectedCurrentIndex, mYiedFeeEarnerRate, previousTimestamp);

        assertEq(mYieldFee.currentIndex(), expectedCurrentIndex);
        assertEq(mYieldFee.updateIndex(), expectedCurrentIndex);
    }

    function testFuzz_currentIndex(
        uint32 earnerRate,
        uint32 nextEarnerRate,
        uint16 feeRate,
        uint16 nextYieldFeeRate,
        uint128 latestIndex,
        uint40 latestUpdateTimestamp,
        uint40 nextTimestamp,
        uint40 finalTimestamp
    ) external {
        vm.assume(nextTimestamp > latestUpdateTimestamp);

        feeRate = _setupYieldFeeRate(feeRate);

        vm.mockCall(address(mToken), abi.encodeWithSelector(IMTokenLike.earnerRate.selector), abi.encode(earnerRate));
        uint32 latestRate = mYieldFee.latestRate();

        latestIndex = _setupLatestIndex(latestIndex);
        latestRate = _setupLatestRate(latestRate);

        vm.warp(latestUpdateTimestamp);

        mToken.setLatestUpdateTimestamp(latestUpdateTimestamp);
        mYieldFee.setLatestUpdateTimestamp(latestUpdateTimestamp);

        // No change in timestamp, so the index should be equal to the latest stored index
        assertEq(mYieldFee.currentIndex(), latestIndex);

        vm.warp(nextTimestamp);

        mToken.setLatestUpdateTimestamp(nextTimestamp);

        uint128 expectedIndex = _getCurrentIndex(latestIndex, latestRate, latestUpdateTimestamp);
        assertEq(mYieldFee.currentIndex(), expectedIndex);

        vm.assume(finalTimestamp > nextTimestamp);

        // Update yield fee rate and M earner rate
        feeRate = _setupYieldFeeRate(nextYieldFeeRate);

        vm.mockCall(
            address(rateOracle),
            abi.encodeWithSelector(IRateOracle.earnerRate.selector),
            abi.encode(nextEarnerRate)
        );

        latestRate = mYieldFee.latestRate();
        latestRate = _setupLatestRate(latestRate);

        vm.warp(finalTimestamp);

        // expectedIndex was saved as the latest index and nextTimestamp is the latest saved timestamp
        expectedIndex = _getCurrentIndex(expectedIndex, latestRate, nextTimestamp);
        assertEq(mYieldFee.currentIndex(), expectedIndex);
    }

    /* ============ _latestEarnerRateAccrualTimestamp ============ */

    function test_latestEarnerRateAccrualTimestamp() external {
        uint40 timestamp = uint40(22470340);

        vm.mockCall(
            address(mToken),
            abi.encodeWithSelector(IContinuousIndexing.latestUpdateTimestamp.selector),
            abi.encode(timestamp)
        );

        assertEq(mYieldFee.latestEarnerRateAccrualTimestamp(), timestamp);
    }

    /* ============ _currentEarnerRate ============ */

    function test_currentEarnerRate() external {
        uint32 earnerRate = 415;

        vm.mockCall(
            address(rateOracle),
            abi.encodeWithSelector(IRateOracle.earnerRate.selector),
            abi.encode(earnerRate)
        );

        assertEq(mYieldFee.currentEarnerRate(), earnerRate);
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
                        uint32(mYieldFee.latestEarnerRateAccrualTimestamp() - latestUpdateTimestamp)
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
        principal_ = IndexingMath.getPrincipalAmountRoundedDown(balanceWithYield, mYieldFee.currentIndex());

        mYieldFee.setAccountOf(account, balance, principal_);
        mYieldFee.setTotalPrincipal(mYieldFee.totalPrincipal() + principal_);
        mYieldFee.setTotalSupply(mYieldFee.totalSupply() + balance);
    }

    function _setupSupply(uint240 totalSupplyWithYield, uint240 totalSupply) internal returns (uint112 principal_) {
        principal_ = IndexingMath.getPrincipalAmountRoundedDown(totalSupplyWithYield, mYieldFee.currentIndex());

        mYieldFee.setTotalPrincipal(mYieldFee.totalPrincipal() + principal_);
        mYieldFee.setTotalSupply(mYieldFee.totalSupply() + totalSupply);
    }

    function _setupYieldFeeRate(uint16 rate) internal returns (uint16) {
        rate = uint16(bound(rate, 0, ONE_HUNDRED_PERCENT));

        vm.prank(yieldFeeManager);
        mYieldFee.setFeeRate(rate);

        return rate;
    }

    function _setupLatestRate(uint32 rate) internal returns (uint32) {
        rate = uint32(bound(rate, 10, 10_000));
        mYieldFee.setLatestRate(rate);
        return rate;
    }

    function _setupLatestIndex(uint128 latestIndex) internal returns (uint128) {
        latestIndex = uint128(bound(latestIndex, EXP_SCALED_ONE, 10_000000000000));
        mYieldFee.setLatestIndex(latestIndex);
        return latestIndex;
    }

    function _setupIndex(bool earningEnabled, uint32 rate, uint128 latestIndex) internal returns (uint128) {
        mYieldFee.setLatestIndex(bound(latestIndex, EXP_SCALED_ONE, 10_000000000000));

        if (earningEnabled) {
            // Earning is enabled when latestRate != 0
            _setupLatestRate(rate);
        } else {
            // Earning is disabled when latestRate == 0
            mYieldFee.setLatestRate(0);
        }

        return mYieldFee.currentIndex();
    }
}
