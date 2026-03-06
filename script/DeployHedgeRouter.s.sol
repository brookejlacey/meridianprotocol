// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script, console} from "@forge-std/Script.sol";
import {HedgeRouter} from "../src/HedgeRouter.sol";

contract DeployHedgeRouter is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address pricer = 0x31DBEe51017EB6Cf4f536a43408F072339b5c83F;
        address shieldFactory = 0x9A9e51c6A91573dEFf7657baB7570EF4888Aaa3A;

        vm.startBroadcast(deployerPrivateKey);
        HedgeRouter router = new HedgeRouter(pricer, shieldFactory, deployer);
        vm.stopBroadcast();

        console.log("HedgeRouter deployed at:", address(router));
        console.log("");
        console.log("Add to frontend/.env.local:");
        console.log("NEXT_PUBLIC_HEDGE_ROUTER=%s", address(router));
    }
}
