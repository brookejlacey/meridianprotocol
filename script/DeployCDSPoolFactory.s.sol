// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script, console} from "@forge-std/Script.sol";
import {CDSPoolFactory} from "../src/shield/CDSPoolFactory.sol";

/// @title DeployCDSPoolFactory
/// @notice Deploys the CDS AMM Pool Factory to Fuji testnet.
/// @dev Run: forge script script/DeployCDSPoolFactory.s.sol --rpc-url fuji --broadcast
contract DeployCDSPoolFactory is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);
        CDSPoolFactory factory = new CDSPoolFactory(deployer, deployer, 0);
        vm.stopBroadcast();

        console.log("CDSPoolFactory deployed at:", address(factory));
        console.log("");
        console.log("Add to frontend/.env.local:");
        console.log("NEXT_PUBLIC_CDS_POOL_FACTORY=%s", address(factory));
        console.log("");
        console.log("Add to indexer/.env.local:");
        console.log("CDS_POOL_FACTORY_ADDRESS=%s", address(factory));
    }
}
