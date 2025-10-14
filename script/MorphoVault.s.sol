// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {MorphoVault} from "src/vaults/MorphoVault.sol";

import {USDC, STEAKHOUSE_USDC_VAULT} from "src/utils/Constants.sol";

contract CounterScript is Script {
    MorphoVault public morphoVault;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // morphoVault = new MorphoVault(USDC, STEAKHOUSE_USDC_VAULT, address(0));

        vm.stopBroadcast();
    }
}
