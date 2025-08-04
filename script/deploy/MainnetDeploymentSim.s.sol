// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { DeployBase } from "./DeployBase.s.sol";
import { console } from "forge-std/console.sol";

import { SwapFacility } from "../../src/swap/SwapFacility.sol";
import { UniswapV3SwapAdapter } from "../../src/swap/UniswapV3SwapAdapter.sol";
import { IMTokenLike } from "../../src/interfaces/IMTokenLike.sol";
import { IMExtension } from "../../src/interfaces/IMExtension.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract MainnetDeploymentSim is DeployBase {
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    function run() public {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));

        vm.startPrank(deployer);

        (, address swapFacilityProxy, ) = _deploySwapFacility(deployer);

        console.log("SwapFacilityProxy:", swapFacilityProxy);

        vm.writeJson(vm.toString(swapFacilityProxy), "deployments/1.json", ".swapFacility");

        address swapAdapter = _deploySwapAdapter(deployer);

        console.log("SwapAdapter:", swapAdapter);

        SwapFacility facility = SwapFacility(swapFacilityProxy);
        UniswapV3SwapAdapter adapter = UniswapV3SwapAdapter(swapAdapter);

        IMTokenLike m = IMTokenLike(M_TOKEN);
        IMExtension wm = IMExtension(WRAPPED_M_TOKEN);

        console.log("m", address(m));

        m.approve(address(facility), type(uint256).max);
        wm.approve(address(facility), type(uint256).max);
        wm.approve(address(adapter), type(uint256).max);
        IERC20(USDC).approve(address(adapter), type(uint256).max);
        (bool success, ) = USDT.call(
            abi.encodeWithSelector(IERC20.approve.selector, address(adapter), type(uint256).max)
        );

        facility.swapInM(WRAPPED_M_TOKEN, 10000, deployer);

        uint256 wmBalance = wm.balanceOf(deployer);

        console.log("wmBalance", wmBalance);

        adapter.swapOut(WRAPPED_M_TOKEN, wmBalance, USDT, 0, deployer, "");

        uint256 usdtBalance = IERC20(USDT).balanceOf(deployer);

        console.log("usdtBalance", usdtBalance);

        adapter.swapIn(USDT, usdtBalance, WRAPPED_M_TOKEN, 0, deployer, "");

        wmBalance = wm.balanceOf(deployer);

        console.log("wmBalance", wmBalance);

        vm.stopPrank();
    }
}
