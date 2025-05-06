// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

contract MockM {
    uint128 public currentIndex;

    mapping(address account => uint256 balance) public balanceOf;
    mapping(address account => bool isEarning) public isEarning;

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {}

    function permit(address owner, address spender, uint256 value, uint256 deadline, bytes memory signature) external {}

    function transfer(address recipient, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;

        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;

        return true;
    }

    function setBalanceOf(address account, uint256 balance) external {
        balanceOf[account] = balance;
    }

    function setCurrentIndex(uint128 currentIndex_) external {
        currentIndex = currentIndex_;
    }

    function setIsEarning(address account, bool isEarning_) external {
        isEarning[account] = isEarning_;
    }

    function startEarning() external {
        isEarning[msg.sender] = true;
    }

    function stopEarning(address account) external {
        isEarning[account] = false;
    }
}

contract MockRegistrar {
    mapping(bytes32 key => bytes32 value) public get;

    mapping(bytes32 list => mapping(address account => bool contains)) public listContains;

    function set(bytes32 key, bytes32 value) external {
        get[key] = value;
    }

    function setListContains(bytes32 list, address account, bool contains) external {
        listContains[list][account] = contains;
    }
}
