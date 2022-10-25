// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "ds-test/test.sol";

import {Spigot} from "Line-of-Credit/modules/spigot/Spigot.sol";
import {Oracle} from "Line-of-Credit/modules/oracle/Oracle.sol";
import {ModuleFactory} from "Line-of-Credit/modules/factories/ModuleFactory.sol";
import {LineFactory} from "Line-of-Credit/modules/factories/LineFactory.sol";
import {ILineFactory} from "Line-of-Credit/interfaces/ILineFactory.sol";
import {IEscrow} from "Line-of-Credit/interfaces/IEscrow.sol";
import {ISpigot} from "Line-of-Credit/interfaces/ISpigot.sol";

import {Migration} from "../../src/idle-finance/Migration.sol";

interface IFeeCollector {
    function hasRole(bytes32 role, address account) external returns (bool);

    function isAddressAdmin(address _address) external view returns (bool);

    function replaceAdmin(address _newAdmin) external;
}

contract IdleMigrationTest is Test {
    /*
        1 - Deploy Spigot
        2 - Deploy Migration
        3 - Transfer ownership of spigot to migration

        1. Deploy spigot and escrow from factory contract on their own, no secured line
        1. Owner is IDLE Finance (or debtDaoDeployer) multisig
        2. deploy SecuredLine with config using Spigot and escrow with IDLE as borrower
        3. Deploy migration contract with spigot address, custom logic for idle integration, and completion checks
        4. IDLE give call `[replaceAdmin` on FeeCollector](https://github.com/Idle-Finance/idle-smart-treasury/blob/56067fff948e33e4dd1050841683554caa8532a4/contracts/FeeCollector.sol#L491-L494) replacing multisig with Migration Contract migration contract DEFAULT_ADMIN_ROLE on Fee Collector
        1. ***ASK:*** ***Might have to be an onchain proposal instead of multisig tx***
    */

    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

    ModuleFactory moduleFactory;
    LineFactory lineFactory;
    Oracle oracle;

    // Oracle
    address chainlinkFeedRegistry = 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf;

    // Spigot
    address idleFeeCollector = 0xBecC659Bfc6EDcA552fa1A67451cC6b38a0108E4;
    address idleFeeTreasury = 0x69a62C24F16d4914a48919613e8eE330641Bcb94;
    address idleTreasuryLeagueMultiSig =
        0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814; // borrower
    address idleDeveloperLeagueMultisig =
        0xe8eA8bAE250028a8709A3841E0Ae1a44820d677b; // Fee collector admin
    address idleTimelock = 0xD6dABBc2b275114a2366555d6C481EF08FDC2556;

    address zeroExSwapTarget = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;

    address debtDaoDeployer = makeAddr("debtDaoDeployer");

    address idleSpigotAddress;
    address idleEscrowAddress;
    address idleLineOfCredit;

    uint256 ttl = 90 days;
    uint256 creditRatio = 0;
    uint256 revenueSplit = 100;

    constructor() {
        emit log_named_address("debtDaoDeployer", debtDaoDeployer);

        vm.prank(debtDaoDeployer);
        oracle = new Oracle(chainlinkFeedRegistry);
        moduleFactory = new ModuleFactory();

        lineFactory = new LineFactory(
            address(moduleFactory), // module factory
            debtDaoDeployer, // arbiter
            address(oracle), // oracle
            zeroExSwapTarget // swapTarget
        );
    }

    function test_returning_admin_to_multisig() external {
        Migration migration = new Migration(
            address(moduleFactory),
            address(lineFactory),
            idleFeeCollector,
            debtDaoDeployer,
            address(oracle),
            idleTreasuryLeagueMultiSig, // borrower
            90 days //ttl
        );

        vm.prank(idleTimelock);
        IFeeCollector(idleFeeCollector).replaceAdmin(address(migration));

        assertTrue(
            IFeeCollector(idleFeeCollector).isAddressAdmin(address(migration))
        );

        migration.returnAdmin(idleTimelock);

        assertTrue(
            IFeeCollector(idleFeeCollector).isAddressAdmin(idleTimelock)
        );
    }

    function test_migrate_when_not_admin() external {
        Migration migration = new Migration(
            address(moduleFactory),
            address(lineFactory),
            idleFeeCollector,
            debtDaoDeployer,
            address(oracle),
            idleTreasuryLeagueMultiSig, // borrower
            90 days //ttl
        );

        vm.startPrank(makeAddr("random1"));
        vm.expectRevert(bytes("Migration: Unauthorized"));
        migration.migrate();
        vm.stopPrank();

        vm.expectRevert(Migration.NotFeeCollectorAdmin.selector);
        migration.migrate();
    }

    function test_migrateToSpigot() external {
        // the migration contract deploys the line of credit, along with spigot and escrow
        Migration migration = new Migration(
            address(moduleFactory),
            address(lineFactory),
            idleFeeCollector,
            debtDaoDeployer,
            address(oracle),
            idleTreasuryLeagueMultiSig, // borrower
            90 days //ttl
        );

        // change admin user to migration
        vm.prank(idleDeveloperLeagueMultisig);
        IFeeCollector(idleFeeCollector).replaceAdmin(address(migration));

        assertTrue(
            IFeeCollector(idleFeeCollector).isAddressAdmin(address(migration))
        );

        // IFeeCollector(idleFeeCollector).replaceAdmin(address(migration));
    }

    // function _deployLineOfCredit() internal returns (address line) {
    //     // deploy the Oracle

    //     emit log_named_address("Oracle", address(oracle));

    //     // deploy the Spigot contract
    //     idleSpigotAddress = moduleFactory.deploySpigot(
    //         debtDaoDeployer, // owner (will be transferred to lender)
    //         idleFeeTreasury, // operator (borrower, ie owner of the revenue contract)
    //         idleFeeTreasury // treasury (multisig)
    //     );
    //     emit log_named_address("Spigot", idleSpigotAddress);

    //     // deploy the escrow contract
    //     idleEscrowAddress = moduleFactory.deployEscrow(
    //         0, // minCRatio (0 means you don't have to look after collatoral)
    //         address(oracle), // oracle
    //         debtDaoDeployer, // owner ( TODO: this will be updated to the Line of Credit)
    //         idleFeeTreasury // borrower (TODO: this )
    //     );
    //     emit log_named_address("Escrow", idleEscrowAddress);

    //     // deploy the Line of Credit

    //     lineFactory = new LineFactory(
    //         address(address(moduleFactory)),
    //         debtDaoDeployer,
    //         address(oracle),
    //         zeroExSwapTarget
    //     );

    //     ILineFactory.CoreLineParams memory coreParams = ILineFactory
    //         .CoreLineParams({
    //             borrower: idleTreasuryLeagueMultiSig,
    //             ttl: ttl,
    //             cratio: uint32(creditRatio),
    //             revenueSplit: uint8(revenueSplit)
    //         });

    //     line = lineFactory.deploySecuredLineWithModules(
    //         coreParams,
    //         idleSpigotAddress,
    //         idleEscrowAddress
    //     );

    //     // update owner of escrow and spigot to the line
    //     IEscrow(idleEscrowAddress).updateLine(address(line));
    //     ISpigot(idleSpigotAddress).updateOwner(address(line));

    //     vm.stopPrank();

    //     emit log_named_address("Idle Credit Line", idleLineOfCredit);
    // }
}
