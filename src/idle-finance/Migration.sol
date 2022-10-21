// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Spigot} from "Line-of-Credit/modules/spigot/Spigot.sol";
import {SecuredLine} from "Line-of-Credit/modules/credit/SecuredLine.sol";
import {ModuleFactory} from "Line-of-Credit/modules/factories/ModuleFactory.sol";
import {LineFactory} from "Line-of-Credit/modules/factories/LineFactory.sol";

import {ILineFactory} from "Line-of-Credit/interfaces/ILineFactory.sol";

contract Migration {
    address private constant zeroExSwapTarget =
        0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
    address private immutable owner;
    address private immutable oracle;
    address private immutable debtDaoDeployer;

    ModuleFactory moduleFactory;
    LineFactory lineFactory;

    // address idleMultiSig;
    // address idleFeeCollector;

    // address governanceProposal;
    // Spigot spigot;
    address spigot;

    // 0 - deploy spigot
    // 1 - take owner ship of revenue contract from governance
    // 2 - transfer ownership of revenue to spigot
    // 3 - test revenue can be claimed
    constructor(
        address debtDaoDeployer_,
        address oracle_,
        address borrower_,
        uint256 ttl_
    ) {
        owner = msg.sender;
        debtDaoDeployer = debtDaoDeployer_;
        oracle = oracle_;
        moduleFactory = new ModuleFactory();
        lineFactory = new LineFactory(
            address(moduleFactory), // module factory
            debtDaoDeployer_, // arbiter
            oracle_, // oracle
            zeroExSwapTarget // swapTarget
        );

        ILineFactory.CoreLineParams memory coreParams = ILineFactory
            .CoreLineParams({
                borrower: borrower_, // idleTreasuryLeagueMultiSig,
                ttl: ttl_,
                cratio: 0, //uint32(creditRatio),
                revenueSplit: 100 //uint8(revenueSplit)
            });

        lineFactory.deploySecuredLineWithConfig(coreParams);
    }

    function migrate() external onlyOwner {}

    modifier onlyOwner() {
        require(msg.sender == owner, "Migration: Unauthorized");
        _;
    }
}
