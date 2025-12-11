// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/FishSupplyChain.sol";

contract DeployFish is Script {
    function run() external {
        // 使用 Anvil 默认私钥进行部署
        uint256 deployerPrivateKey =
            vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));

        vm.startBroadcast(deployerPrivateKey);

        // 部署真正的合约
        new FishSupplyChain();

        vm.stopBroadcast();
    }
}
