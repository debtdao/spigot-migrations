// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Spigot} from "Line-of-Credit/modules/spigot/Spigot.sol";
import {SecuredLine} from "Line-of-Credit/modules/credit/SecuredLine.sol";

contract Migration {
    address private immutable owner;

    // address idleMultiSig;
    // address idleFeeCollector;

    // address governanceProposal;
    // Spigot spigot;
    address spigot;

    // 0 - deploy spigot
    // 1 - take owner ship of revenue contract from governance
    // 2 - transfer ownership of revenue to spigot
    // 3 - test revenue can be claimed
    constructor(address spigot_) {
        owner = msg.sender;
        spigot = spigot_;
    }

    function migrate() external onlyOwner {}

    modifier onlyOwner() {
        require(msg.sender == owner, "Migration: Unauthorized");
        _;
    }
}
