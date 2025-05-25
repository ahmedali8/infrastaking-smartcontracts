// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Script.sol";
import "../src/InfraStaking.sol";

contract DeployInfraStaking is Script {
    address constant BENQI_LIQUID_STAKING = 0x2b2C81e08f1Af8835a78Bb2A90AE924ACE0eA4bE;
    address constant DEFAULT_COLLATERAL = 0xE3C983013B8c5830D866F550a28fD7Ed4393d5B7;

    function run() external {
        // Load the private key from .env (or set it in foundry.toml)
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerKey);

        // Deploy the contract
        InfraStaking infra = new InfraStaking(BENQI_LIQUID_STAKING, DEFAULT_COLLATERAL);
        console.log("InfraStaking deployed at:", address(infra));

        vm.stopBroadcast();
    }
}

// Deployment Command:
// forge script script/DeployInfraStaking.s.sol:DeployInfraStaking \
//   --rpc-url https://ethereum-holesky-rpc.publicnode.com \
//   --broadcast \
//   --verify \
//   --etherscan-api-key EYQWCNC8YRGVATC3WG4B79W23Z67VME32W \
//   --chain 17000

// axax rpc: https://avalanche-c-chain-rpc.publicnode.com
// chain id: 43114
