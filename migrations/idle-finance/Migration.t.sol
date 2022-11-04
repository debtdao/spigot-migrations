// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {Spigot} from "Line-of-Credit/modules/spigot/Spigot.sol";
import {Oracle} from "Line-of-Credit/modules/oracle/Oracle.sol";
import {ModuleFactory} from "Line-of-Credit/modules/factories/ModuleFactory.sol";
import {LineFactory} from "Line-of-Credit/modules/factories/LineFactory.sol";
import {ILineFactory} from "Line-of-Credit/interfaces/ILineFactory.sol";
import {LineOfCredit} from "Line-of-Credit/modules/credit/LineOfCredit.sol";

import {SpigotedLine} from "Line-of-Credit/modules/credit/SpigotedLine.sol";

import {SecuredLine} from "Line-of-Credit/modules/credit/SecuredLine.sol";
import {ZeroEx} from "Line-of-Credit/mock/ZeroEx.sol";
import {ISpigotedLine} from "Line-of-Credit/interfaces/ISpigotedLine.sol";
import {IEscrow} from "Line-of-Credit/interfaces/IEscrow.sol";
import {ISpigot} from "Line-of-Credit/interfaces/ISpigot.sol";
import {ILineOfCredit} from "Line-of-Credit/interfaces/ILineOfCredit.sol";

import {IdleMigration} from "./Migration.sol";

// TODO: test internal function with assertEQ failing

interface IFeeCollector {
    function hasRole(bytes32 role, address account) external returns (bool);

    function isAddressAdmin(address _address) external view returns (bool);

    function replaceAdmin(address _newAdmin) external;

    function getDepositTokens() external view returns (address[] memory);

    function deposit(
        bool[] memory _depositTokensEnabled,
        uint256[] memory _minTokenOut,
        uint256 _minPoolAmountOut
    ) external;

    function getNumTokensInDepositList() external view returns (uint256);
}

interface IWeth {
    function deposit() external payable;
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
        Quorum: 4% of the total IDLE supply (~520,000 IDLE) voting the pool
        Timeline: 3 days of voting
    */

    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

    ModuleFactory moduleFactory;
    LineFactory lineFactory;
    Oracle oracle;
    ZeroEx dex;

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
    address idleRebalancer = 0xB3C8e5534F0063545CBbb7Ce86854Bf42dB8872B;

    uint256 idleVotingDelay = 1; // in blocks
    uint256 idleVotingPeriod = 17280; // in blocks
    uint256 idleTimelockDelay = 172800; // in seconds

    mapping(address => uint256) idleDepositTokensToBalance;

    // $IDLE holders (voters)
    address idleCommunityMultisig = 0xb08696Efcf019A6128ED96067b55dD7D0aB23CE4; // 1,203,859 votes
    address idleVoterOne = 0x645090dc32eB0950D7C558515cFCDC63D5B4eA6c; // 654,386
    address idleVoterTwo = 0xe8eA8bAE250028a8709A3841E0Ae1a44820d677b; // 374,775

    // idle deposit tokens
    address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // lender
    address daiWhale = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;

    // migration
    address idleSpigotAddress;
    address idleEscrowAddress;
    address idleLineOfCredit;

    uint256 ttl = 90 days;
    uint256 creditRatio = 0;
    uint256 revenueSplit = 100;
    uint256 loanSizeInDai = 10e6;

    // fork settings
    uint256 ethMainnetFork;

    event log_named_bytes4(string key, bytes4 value);

    constructor() {
        emit log_named_address("debtDaoDeployer", debtDaoDeployer);

        vm.prank(debtDaoDeployer);
        oracle = new Oracle(chainlinkFeedRegistry);
        moduleFactory = new ModuleFactory();
        dex = new ZeroEx();

        lineFactory = new LineFactory(
            address(moduleFactory), // module factory
            debtDaoDeployer, // arbiter
            address(oracle), // oracle
            address(dex) // zeroExSwapTarget // swapTarget
        );
    }

    function setUp() public {
        ethMainnetFork = vm.createFork(vm.envString("ETH_RPC_URL"), 15_795_856);
        emit log_named_string("rpc", vm.envString("ETH_RPC_URL"));
    }

    ///////////////////////////////////////////////////////
    //                      T E S T S                    //
    ///////////////////////////////////////////////////////

    // select a specific fork
    function test_can_select_fork() public {
        // select the fork
        vm.selectFork(ethMainnetFork);
        assertEq(vm.activeFork(), ethMainnetFork);
        assertEq(block.number, 15_795_856);
    }

    function test_returning_admin_to_timelock() external {
        IdleMigration migration = new IdleMigration(
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

        // incomplete proposal will transfer admin privileges, but won't call `migrate()`
        uint256 proposalId = _submitIncompleteProposal(address(migration));
        _voteAndPassProposal(proposalId, address(migration));

        assert(
            IFeeCollector(idleFeeCollector).isAddressAdmin(address(migration))
        );

        vm.expectRevert("Cooldown still active");
        migration.recoverAdmin(idleTimelock);

        vm.warp(block.timestamp + 31 days);
        migration.recoverAdmin(idleTimelock);

        assertTrue(
            IFeeCollector(idleFeeCollector).isAddressAdmin(idleTimelock)
        );
    }

    function test_migrate_when_not_admin() external {
        // vm.selectFork(ethMainnetFork);
        // assertEq(vm.activeFork(), ethMainnetFork);

        IdleMigration migration = new IdleMigration(
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

        // vm.expectRevert(IdleMigration.NotFeeCollectorAdmin.selector);
        // migration.migrate();
    }

    function test_migration_vote_passed_and_migration_succeeds() external {
        IdleMigration migration = _deployMigrationContract();

        // Simulate the governance process, which replaces the admin and performs the migration
        uint256 proposalId = _submitProposal(address(migration));
        _voteAndPassProposal(proposalId, address(migration));

        // Test the spigot's `operate()` method.
        _operatorAddAddress(migration.spigot());

        // simulate the fee collector generating revenue
        uint256 _revenueGenerated = _simulateRevenueGeneration(5 ether);
        uint256 _expectedRevenueDistribution = (_revenueGenerated * 7000) /
            10000;

        _claimRevenueOnBehalfOfSpigot(
            migration.spigot(),
            _expectedRevenueDistribution
        );
    }

    function test_migration_with_loan_and_repayment() external {
        IdleMigration migration = _deployMigrationContract();
        SpigotedLine line = SpigotedLine(payable(migration.securedLine()));

        // Simulate the governance process, which replaces the admin and performs the migration
        uint256 proposalId = _submitProposal(address(migration));
        _voteAndPassProposal(proposalId, address(migration));

        assert(
            IFeeCollector(idleFeeCollector).isAddressAdmin(migration.spigot())
        );

        // TODO: should they transfer out
        bytes32 id = _lenderFundLoan(migration.securedLine());

        uint256 amountToBorrow = loanSizeInDai;

        // borrow some of the available funds
        vm.startPrank(idleTreasuryLeagueMultiSig);
        ILineOfCredit(migration.securedLine()).borrow(id, amountToBorrow);

        uint256 borrowerDaiBalance = IERC20(dai).balanceOf(
            idleTreasuryLeagueMultiSig
        );

        vm.stopPrank();

        vm.warp(block.timestamp + 30 days);

        (, uint256 principal, uint256 interest, uint256 repaid, , , ) = line
            .credits(id);

        emit log_named_uint("principal [before]", principal);
        emit log_named_uint("interest [before]", interest);
        emit log_named_uint("repaid [before]", repaid);

        uint256 revenueToSimulate = 10e16;

        uint256 _revenueGenerated = _simulateRevenueGeneration(
            revenueToSimulate
        );

        // call claimRevenue
        uint256 expected = (revenueToSimulate * 7000) / 10000;
        _claimRevenueOnBehalfOfSpigot(migration.spigot(), expected);

        // MockZeroX call to trade WETH to DAI
        bytes memory data = _generateTradeData(
            migration.spigot(),
            amountToBorrow * 2
        );

        vm.startPrank(idleTreasuryLeagueMultiSig);
        // this calls getEscrowed (claims escrow for owner)
        ISpigotedLine(migration.securedLine()).claimAndRepay(weth, data);
        vm.stopPrank();
        (, principal, interest, repaid, , , ) = line.credits(id);

        emit log_named_uint("principal [after]", principal);
        emit log_named_uint("interest [after]", interest);
        emit log_named_uint("repaid [after]", repaid);

        // lender withdraw on line of credit
        vm.startPrank(daiWhale);
        ILineOfCredit(migration.securedLine()).withdraw(id, repaid); // repaid + deposit
        vm.stopPrank();

        // principal on position must be zero to close
        // call depositAndClose; (only borrower);
        vm.startPrank(idleTreasuryLeagueMultiSig);
        line.close(id);
    }

    // TODO: test that idle can't perform any admin functions

    function test_chainlink_price_feed() external {
        int256 daiPrice = oracle.getLatestAnswer(dai);
        emit log_named_int("dai price", daiPrice);
        assert(daiPrice > 0);
    }

    function test_migration_vote_not_passed() external {
        IdleMigration migration = new IdleMigration(
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

        // governance
        _proposeAndVoteToFail(address(migration));
    }

    function test_migration_vote_but_no_quorum() external {
        IdleMigration migration = new IdleMigration(
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

        // governance
        _proposeAndNoQuorum(address(migration));
    }

    ///////////////////////////////////////////////////////
    //          I N T E R N A L   H E L P E R S          //
    ///////////////////////////////////////////////////////

    function _lenderFundLoan(address _lineOfCredit)
        internal
        returns (bytes32 id)
    {
        vm.startPrank(idleTreasuryLeagueMultiSig);
        ILineOfCredit(_lineOfCredit).addCredit(
            1000, // drate
            1000, // frate
            loanSizeInDai, // amount
            dai, // token
            daiWhale // lender
        );
        vm.stopPrank();

        vm.startPrank(daiWhale);
        IERC20(dai).approve(_lineOfCredit, loanSizeInDai);
        id = ILineOfCredit(_lineOfCredit).addCredit(
            1000, // drate
            1000, // frate
            loanSizeInDai, // amount
            dai, // token
            daiWhale // lender
        );
        vm.stopPrank();

        // goes from the line of credit to the borrowers address (once they've called borrow)

        emit log_named_bytes32("credit id", id);
    }

    function _generateTradeData(address _spigot, uint256 repayment)
        internal
        returns (bytes memory tradeData)
    {
        uint256 claimable = ISpigot(_spigot).getEscrowed(weth);

        emit log_named_uint("Claimable WETH", claimable);

        tradeData = abi.encodeWithSignature(
            "trade(address,address,uint256,uint256)",
            weth, // revenue
            dai, // credit
            claimable,
            repayment // min amount out
        );

        // make sure the dex has tokens to trade
        deal(weth, address(dex), 10e18);
        deal(dai, address(dex), 10e18);
    }

    function _deployMigrationContract()
        internal
        returns (IdleMigration migration)
    {
        // the migration contract deploys the line of credit, along with spigot and escrow
        migration = new IdleMigration(
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
    }

    function _simulateRevenueGeneration(uint256 amt)
        internal
        returns (uint256 revenue)
    {
        vm.deal(idleFeeCollector, amt + 0.5 ether); // add a bit to cover gas

        vm.prank(idleFeeCollector);
        revenue = amt;
        IWeth(weth).deposit{value: revenue}();

        assertEq(IERC20(weth).balanceOf(idleFeeCollector), revenue);
    }

    function _claimRevenueOnBehalfOfSpigot(
        address _spigot,
        uint256 _expectedRevenue
    ) internal {
        /*
            function deposit(
                bool[] memory _depositTokensEnabled,
                uint256[] memory _minTokenOut,
                uint256 _minPoolAmountOut
            ) external;
        */
        uint256 _depositTokensLength = IFeeCollector(idleFeeCollector)
            .getNumTokensInDepositList();

        bool[] memory _tokensEnabled = new bool[](_depositTokensLength);

        uint256[] memory _minTokensOut = new uint256[](_depositTokensLength);

        // we'll skip the swapping and just send the Weth in the contract,
        // so all deposit tokens can be disabled
        for (uint256 i; i < _tokensEnabled.length; ) {
            _tokensEnabled[i] = false;
            unchecked {
                ++i;
            }
        }

        bytes memory data = abi.encodeWithSelector(
            IFeeCollector.deposit.selector,
            _tokensEnabled,
            _minTokensOut,
            0
        );

        // All this is doing is triggering the fee collector (revenue contract)
        // to convert tokens to WETH and distribute to beneficiaries (which include spigot)
        // TODO: do we pass "token" as weth, and does it matter?
        ISpigot(_spigot).claimRevenue(idleFeeCollector, weth, data);

        assertEq(_expectedRevenue, IERC20(weth).balanceOf(_spigot));
    }

    // TODO: rename this and/or change the whitelisted fn
    function _operatorAddAddress(address _spigot) internal {
        bytes4 addAddressSelector = _getSelector(
            "addAddressToWhiteList(address)"
        );

        emit log_named_bytes4("add address selector", addAddressSelector);

        bytes memory data = abi.encodeWithSignature(
            "addAddressToWhiteList(address)",
            debtDaoDeployer
        );

        emit log_named_bytes("add address calldata", data);

        assertEq(addAddressSelector, bytes4(data));

        require(
            ISpigot(_spigot).isWhitelisted(bytes4(data)),
            "Not Whitelisted"
        );

        // test the function that was whitelisted in the migration contract
        vm.startPrank(idleTreasuryLeagueMultiSig);
        assertEq(idleTreasuryLeagueMultiSig, ISpigot(_spigot).operator());
        ISpigot(_spigot).operate(idleFeeCollector, data);
        vm.stopPrank();
    }

    function _submitIncompleteProposal(address migrationContract)
        internal
        returns (uint256 id)
    {
        vm.startPrank(idleDeveloperLeagueMultisig);

        address[] memory targets = new address[](1);
        targets[0] = idleFeeCollector;

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        string[] memory signatures = new string[](1);
        signatures[0] = "replaceAdmin(address)"; // "replaceAdmin(address _newAddress)" is wrong, don't include arg name, just hte type

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encode(migrationContract); // instead of using encodePacked which removes padding, calldata expects 32byte chunks

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

    function _submitProposal(address migrationContract)
        internal
        returns (uint256 id)
    {
        vm.startPrank(idleDeveloperLeagueMultisig);

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

    function _voteAndPassProposal(uint256 id, address migrationContract)
        internal
    {
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

        // note: this will call `depositAllTokens()` internally and zero out the balances of all deposited tokens
        IGovernorBravo(idleGovernanceBravo).execute(id);

        vm.stopPrank();
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

    // note: quorum is 4% of total supply, roughly ~520,000 votes
    function _proposeAndNoQuorum(address migrationContract) internal {
        uint256 id = _submitProposal(migrationContract);
        vm.prank(idleVoterTwo); // ~347,000
        IGovernorBravo(idleGovernanceBravo).castVote(id, 1);

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

    ///////////////////////////////////////////////////////
    //                      U T I L S                    //
    ///////////////////////////////////////////////////////

    // returns the function selector (first 4 bytes) of the hashed signature
    function _getSelector(string memory _signature)
        internal
        pure
        returns (bytes4)
    {
        return bytes4(keccak256(bytes(_signature)));
    }
}
