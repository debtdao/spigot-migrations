// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {FeeCollector} from "idle-fee-collector/feeCollector/FeeCollector.sol";
import {Spigot} from "Line-of-Credit/contracts/modules/spigot/Spigot.sol";
import {SecuredLine} from "Line-of-Credit/contracts/modules/credit/SecuredLine";

contract Migration {
    address governanceProposal;
    LineFactory linefactory;
    Spigot spigot;

    constructor(
        address gov,
        address rev,
        address spig
    ) {}
}
