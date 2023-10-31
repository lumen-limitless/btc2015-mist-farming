// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {MistFarmingPool} from "../src/MistFarmingPool.sol";

import "forge-std/Script.sol";

contract MistFarmingPoolScript is Script {
    function run() public returns (MistFarmingPool deployment) {
        vm.startBroadcast();

        deployment = new MistFarmingPool();

        vm.stopBroadcast();
    }
}
