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

import {Migration} from "./Migration.sol";

interface IFeeCollector {
    function hasRole(bytes32 role, address account) external returns (bool);

    function isAddressAdmin(address _address) external view returns (bool);

    function replaceAdmin(address _newAdmin) external;
}

interface IGovernorBravo {
    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256);

    function castVote(uint256 proposalId, uint8 support) external;

    function state(uint256 proposalId) external view returns (ProposalState);

    function queue(uint256 proposalId) external;

    function execute(uint256 proposalId) external payable;
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

    // Oracle ( price feeds )
    address chainlinkFeedRegistry = 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf;

    // Ox protocol (token swaps)
    address zeroExSwapTarget = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;

    // debt dao
    address debtDaoDeployer = makeAddr("debtDaoDeployer");

    // Idle
    address idleFeeCollector = 0xBecC659Bfc6EDcA552fa1A67451cC6b38a0108E4;
    address idleFeeTreasury = 0x69a62C24F16d4914a48919613e8eE330641Bcb94;
    address idleTreasuryLeagueMultiSig =
        0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814; // borrower
    address idleDeveloperLeagueMultisig =
        0xe8eA8bAE250028a8709A3841E0Ae1a44820d677b; // Fee collector admin
    address idleTimelock = 0xD6dABBc2b275114a2366555d6C481EF08FDC2556;
    address idleGovernanceBravo = 0x3D5Fc645320be0A085A32885F078F7121e5E5375;

    uint256 idleVotingDelay = 1; // in blocks
    uint256 idleVotingPeriod = 17280; // in blocks
    uint256 idleTimelockDelay = 172800; // in seconds

    // $IDLE holders (voters)
    address idleCommunityMultisig = 0xb08696Efcf019A6128ED96067b55dD7D0aB23CE4; // 1,203,859 votes
    address idleVoterOne = 0x645090dc32eB0950D7C558515cFCDC63D5B4eA6c; // 654,386
    address idleVoterTwo = 0xe8eA8bAE250028a8709A3841E0Ae1a44820d677b; // 374,775

    // migration
    address idleSpigotAddress;
    address idleEscrowAddress;
    address idleLineOfCredit;

    uint256 ttl = 90 days;
    uint256 creditRatio = 0;
    uint256 revenueSplit = 100;

    uint256 ethMainnetFork;

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

    function setUp() public {
        ethMainnetFork = vm.createFork(vm.envString("ETH_RPC_URL"));
        emit log_named_string("rpc", vm.envString("ETH_RPC_URL"));
    }

    // select a specific fork
    function test_can_select_fork() public {
        // select the fork
        vm.selectFork(ethMainnetFork);
        assertEq(vm.activeFork(), ethMainnetFork);
    }

    function test_returning_admin_to_multisig() external {
        // vm.selectFork(ethMainnetFork);
        // assertEq(vm.activeFork(), ethMainnetFork);

        Migration migration = new Migration(
            address(moduleFactory),
            address(lineFactory),
            idleFeeCollector,
            idleTreasuryLeagueMultiSig,
            idleTimelock,
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
        // vm.selectFork(ethMainnetFork);
        // assertEq(vm.activeFork(), ethMainnetFork);

        Migration migration = new Migration(
            address(moduleFactory),
            address(lineFactory),
            idleFeeCollector,
            idleTreasuryLeagueMultiSig,
            idleTimelock,
            debtDaoDeployer,
            address(oracle),
            idleTreasuryLeagueMultiSig, // borrower
            90 days //ttl
        );

        vm.startPrank(makeAddr("random1"));
        vm.expectRevert(bytes("Migration: Unauthorized user"));
        migration.migrate();
        vm.stopPrank();

        // vm.expectRevert(Migration.NotFeeCollectorAdmin.selector);
        // migration.migrate();
    }

    function test_migration_vote_passed_and_migration_succeeds() external {
        // vm.selectFork(ethMainnetFork);
        // assertEq(vm.activeFork(), ethMainnetFork);

        // the migration contract deploys the line of credit, along with spigot and escrow
        Migration migration = new Migration(
            address(moduleFactory),
            address(lineFactory),
            idleFeeCollector,
            idleTreasuryLeagueMultiSig,
            idleTimelock,
            debtDaoDeployer,
            address(oracle),
            idleTreasuryLeagueMultiSig, // borrower
            90 days //ttl
        );

        // Simulate the governance process, which replaces the admin and performs the migration
        vm.startPrank(idleDeveloperLeagueMultisig);
        _proposeAndVoteToPass(address(migration));
        vm.stopPrank();
    }

    function test_migration_vote_not_passed() external {
        Migration migration = new Migration(
            address(moduleFactory),
            address(lineFactory),
            idleFeeCollector,
            idleTreasuryLeagueMultiSig,
            idleTimelock,
            debtDaoDeployer,
            address(oracle),
            idleTreasuryLeagueMultiSig, // borrower
            90 days //ttl
        );

        // Simulate the governance process, which replaces the admin and performs the migration
        vm.startPrank(idleDeveloperLeagueMultisig);
        _proposeAndVoteToFail(address(migration));
        vm.stopPrank();
    }

    /*
        Quorum: 4% of the total IDLE supply (~520,000 IDLE) voting the pool
        Timeline: 3 days of voting
    */

    // TODO: test sending without the replaceAdmin part of the proposal
    function _submitProposal(address migrationContract)
        internal
        returns (uint256 id)
    {
        address[] memory targets = new address[](2);
        targets[0] = idleFeeCollector;
        targets[1] = migrationContract;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        string[] memory signatures = new string[](2);
        signatures[0] = "replaceAdmin(address)"; // "replaceAdmin(address _newAddress)" is wrong, don't include arg name, just hte type
        signatures[1] = "migrate()";

        bytes[] memory calldatas = new bytes[](2);
        calldatas[0] = abi.encode(migrationContract); // instead of using encodePacked which removes padding, calldata expects 32byte chunks
        calldatas[1] = abi.encode("");

        emit log_named_address("target", targets[0]);
        emit log_named_bytes("calldata", calldatas[0]);
        emit log_named_string("signature", signatures[0]);
        emit log_named_uint("value", values[0]);

        id = IGovernorBravo(idleGovernanceBravo).propose(
            targets,
            values,
            signatures,
            calldatas,
            "IIP-33: Allow DebtDAO migration contract to take admin control of the Fee Collector https://gov.idle.finance/t/debtdao-migration-for-loan/1056"
        );

        emit log_named_uint("proposal id: ", id);

        // voting can only start after the delay
        vm.roll(block.number + idleVotingDelay + 1);

        assertEq(
            uint256(IGovernorBravo(idleGovernanceBravo).state(id)),
            uint256(IGovernorBravo.ProposalState.Active)
        );

        vm.stopPrank();
    }

    function _submitIncompleteProposal(address migrationContract) internal {}

    function _proposeAndVoteToPass(address migrationContract) internal {
        uint256 id = _submitProposal(migrationContract);

        vm.prank(idleCommunityMultisig);
        IGovernorBravo(idleGovernanceBravo).castVote(id, 1);

        // voting ends once the voting period is over
        vm.roll(block.number + idleVotingPeriod + 1);

        assertEq(
            uint256(IGovernorBravo(idleGovernanceBravo).state(id)),
            uint256(IGovernorBravo.ProposalState.Succeeded)
        );

        // queue the tx
        IGovernorBravo(idleGovernanceBravo).queue(id);
        assertEq(
            uint256(IGovernorBravo(idleGovernanceBravo).state(id)),
            uint256(IGovernorBravo.ProposalState.Queued)
        );

        // execute the tx, can only happen after timelock delay has passed
        vm.warp(block.timestamp + idleTimelockDelay);
        IGovernorBravo(idleGovernanceBravo).execute(id);

        assert(
            IFeeCollector(idleFeeCollector).isAddressAdmin(
                Migration(migrationContract).spigot()
            )
        );
    }

    function _proposeAndVoteToFail(address migrationContract) internal {
        uint256 id = _submitProposal(migrationContract);

        vm.prank(idleVoterOne);
        IGovernorBravo(idleGovernanceBravo).castVote(id, 1);

        vm.prank(idleVoterTwo);
        IGovernorBravo(idleGovernanceBravo).castVote(id, 1);

        vm.prank(idleCommunityMultisig);
        IGovernorBravo(idleGovernanceBravo).castVote(id, 0);

        // voting ends once the voting period is over
        vm.roll(block.number + idleVotingPeriod + 1);

        assertEq(
            uint256(IGovernorBravo(idleGovernanceBravo).state(id)),
            uint256(IGovernorBravo.ProposalState.Defeated)
        );

        // expect the request to queue to be reverted
        vm.expectRevert(
            bytes(
                "GovernorBravo::queue: proposal can only be queued if it is succeeded"
            )
        );
        IGovernorBravo(idleGovernanceBravo).queue(id);
    }

    function _proposeAndNoQuorum(address migrationContract) internal {
        uint256 id = _submitProposal(migrationContract);
        vm.prank(idleVoterTwo);
        IGovernorBravo(idleGovernanceBravo).castVote(id, 1);
    }
}
