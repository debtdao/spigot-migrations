// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Spigot} from "Line-of-Credit/modules/spigot/Spigot.sol";
import {SecuredLine} from "Line-of-Credit/modules/credit/SecuredLine.sol";
import {ModuleFactory} from "Line-of-Credit/modules/factories/ModuleFactory.sol";
import {LineFactory} from "Line-of-Credit/modules/factories/LineFactory.sol";

import {ILineFactory} from "Line-of-Credit/interfaces/ILineFactory.sol";

interface IFeeCollector {
    function hasRole(bytes32 role, address account) external returns (bool);
}

contract Migration {
    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

    address private constant zeroExSwapTarget =
        0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
    address private immutable owner;
    address private immutable oracle;
    address private immutable debtDaoDeployer;
    address private immutable feeCollector;

    ModuleFactory moduleFactory;
    LineFactory lineFactory;

    // address idleMultiSig;
    // address idleFeeCollector;

    // address governanceProposal;
    // Spigot spigot;
    address spigot;
    address lineOfCredit;

    // 0 - deploy spigot
    // 1 - take owner ship of revenue contract from governance
    // 2 - transfer ownership of revenue to spigot
    // 3 - test revenue can be claimed
    // TODO: should probably pass in the multisig address
    constructor(
        address revenueContract_,
        address debtDaoDeployer_,
        address oracle_,
        address borrower_,
        uint256 ttl_
    ) {
        owner = msg.sender; // presumably Idle Deployer
        debtDaoDeployer = debtDaoDeployer_;
        feeCollector = revenueContract_;
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

        lineOfCredit = lineFactory.deploySecuredLineWithConfig(coreParams);
    }

    // can only be called once the multisig has called replacedOwner with this contract
    // should check that this contract has admin priviliges for fee Collector

    function migrate() external onlyOwner {
        require(
            IFeeCollector(feeCollector).hasRole(
                DEFAULT_ADMIN_ROLE,
                address(this)
            ),
            "Migration contract is not an admin"
        );
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Migration: Unauthorized");
        _;
    }
}
