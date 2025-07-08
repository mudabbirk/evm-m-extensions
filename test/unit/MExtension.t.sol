// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {
    Initializable
} from "../../lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";

import {
    Ownable
} from "../../lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/Ownable.sol";

import { IProxyAdmin } from "../../lib/openzeppelin-foundry-upgrades/src/internal/interfaces/IProxyAdmin.sol";

import { Options } from "../../lib/openzeppelin-foundry-upgrades/src/Options.sol";
import { Upgrades, UnsafeUpgrades } from "../../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { IMExtension } from "../../src/interfaces/IMExtension.sol";

import { MExtensionHarness } from "../harness/MExtensionHarness.sol";

import { BaseUnitTest } from "../utils/BaseUnitTest.sol";
import { MExtensionUpgrade } from "../utils/Mocks.sol";

contract MExtensionUnitTests is BaseUnitTest {
    MExtensionHarness public mExtension;
    IProxyAdmin public proxyAdmin;

    string public constant NAME = "M Extension";
    string public constant SYMBOL = "ME";

    function setUp() public override {
        super.setUp();

        mExtension = MExtensionHarness(
            Upgrades.deployTransparentProxy(
                "MExtensionHarness.sol:MExtensionHarness",
                admin,
                abi.encodeWithSelector(MExtensionHarness.initialize.selector, NAME, SYMBOL),
                mExtensionDeployOptions
            )
        );

        proxyAdmin = IProxyAdmin(Upgrades.getAdminAddress(address(mExtension)));
    }

    /* ============ initialize ============ */

    function test_initialize() external {
        assertEq(mExtension.name(), NAME);
        assertEq(mExtension.symbol(), SYMBOL);
        assertEq(mExtension.decimals(), 6);
        assertEq(mExtension.mToken(), address(mToken));
        assertEq(mExtension.swapFacility(), address(swapFacility));
    }

    function test_initialize_zeroMToken() external {
        vm.expectRevert(IMExtension.ZeroMToken.selector);
        new MExtensionHarness(address(0), address(swapFacility));
    }

    function test_initialize_zeroSwapFacility() external {
        vm.expectRevert(IMExtension.ZeroSwapFacility.selector);
        new MExtensionHarness(address(mToken), address(0));
    }

    /* ============ upgrade ============ */

    function test_initializerDisabled() external {
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));

        vm.prank(alice);
        MExtensionHarness(Upgrades.getImplementationAddress(address(mExtension))).initialize(NAME, SYMBOL);
    }

    function test_upgrade_onlyAdmin() external {
        address v2implementation = address(new MExtensionUpgrade());

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice, admin));

        vm.prank(alice);
        proxyAdmin.upgradeAndCall(address(mExtension), v2implementation, "");
    }

    function test_upgrade() public {
        UnsafeUpgrades.upgradeProxy(address(mExtension), address(new MExtensionUpgrade()), "", admin);

        assertEq(MExtensionUpgrade(address(mExtension)).bar(), 1);
    }
}
