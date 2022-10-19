// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {FeeCollector} from "idle-fee-collector/feeCollector/FeeCollector.sol";
import {Spigot} from "Line-of-Credit/contracts/modules/spigot/Spigot.sol";
import {SecuredLine} from "Line-of-Credit/contracts/modules/credit/SecuredLine.sol";

contract Migration {
    address private immutable owner;

    address idleMultiSig;
    address idleFeeCollector;

    address governanceProposal;
    LineFactory linefactory;
    Spigot spigot;

    // 0 - deploy spigot
    // 1 - take owner ship of revenue contract from governance
    // 2 - transfer ownership of revenue to spigot
    // 3 - test revenue can be claimed
    constructor(
        address gov,
        address rev,
        address spig
    ) {
        owner = msg.sender;
        spigot = new Spigot(msg.sender, idleMultiSig, idleFeeCollector);
    }

    function migrate() external onlyOwner {}

    function createIdleGovernanceProposal() external onlyOwner {}

    modifier onlyOwner() {
        require(msg.sender == owner, "Migration: Unauthorized");
        _;
    }
}
