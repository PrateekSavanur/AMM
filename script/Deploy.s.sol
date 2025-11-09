// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import {Factory} from "../src/core/Factory.sol";
import {WETH} from "../src/periphery/WETH.sol";
import {Router} from "../src/periphery/Router.sol";

contract DeployDEX is Script {
    function run() external {
        // Load deployer key from environment
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        // Start broadcasting to the network
        vm.startBroadcast(deployerKey);

        // 1️⃣ Deploy Factory
        Factory factory = new Factory();
        console.log(" Factory deployed at:", address(factory));

        // 2️⃣ Deploy WETH
        WETH weth = new WETH();
        console.log(" WETH deployed at:", address(weth));

        // 3️⃣ Deploy Router with Factory and WETH addresses
        Router router = new Router(address(factory), address(weth));
        console.log(" Router deployed at:", address(router));

        vm.stopBroadcast();
    }
}
