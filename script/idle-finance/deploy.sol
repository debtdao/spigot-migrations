// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "{forge-std/Script.sol";
import {Spigot} from "Line-of-Credit/modules/spigot/Spigot.sol";

contract DeployIdleMigrations is Script {
    /*
        1 - Deploy Spigot
        2 - Deploy Migration
        3 - Transfer ownership of spigot to migration
    */
    constructor() {}

    function run() public {
        vm.broadcast();
    }
}
