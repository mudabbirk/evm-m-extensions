// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { Blacklistable } from "../../src/abstract/components/Blacklistable.sol";

contract BlacklistableHarness is Blacklistable {
    constructor(address blacklistManager_) Blacklistable(blacklistManager_) {}
}
