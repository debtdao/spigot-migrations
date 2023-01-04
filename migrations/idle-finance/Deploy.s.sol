// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Script.sol";
import {IdleMigration} from "./Migration.sol";

contract DeployIdleMigrations is Script {

    IdleMigration migration;

    address constant lineFactory = address(0x123); // TODO: update
    uint256 constant ttl = 365 days;
    constructor() {}

    event log_named_uint(string key, uint256 val);

    function run() public {
        
        uint256 deployerKey = vm.envUint("DEPLOYER_PVT_KEY");

        emit log_named_uint("deployer key", deployerKey);

        vm.startBroadcast(deployerKey);
        
        migration = new IdleMigration(lineFactory, ttl);

        console.log("migration contract", address(migration));

    }

}