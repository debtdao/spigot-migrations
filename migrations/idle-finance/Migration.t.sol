// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {Spigot} from "Line-of-Credit/modules/spigot/Spigot.sol";
import {Oracle} from "Line-of-Credit/modules/oracle/Oracle.sol";
import {MockRegistry} from "Line-of-Credit/mock/MockRegistry.sol";
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

interface IFeeCollector {
    function hasRole(bytes32 role, address account) external returns (bool);
    function isAddressAdmin(address _address) external view returns (bool);
    function replaceAdmin(address _newAdmin) external;
    function getDepositTokens() external view returns (address[] memory);
    function deposit(bool[] memory _depositTokensEnabled, uint256[] memory _minTokenOut, uint256 _minPoolAmountOut)
        external;
    function getNumTokensInDepositList() external view returns (uint256);
    function addAddressToWhiteList(address _addressToAdd) external;
    function removeAddressFromWhiteList(address _addressToRemove) external;
    function registerTokenToDepositList(address _tokenAddress) external;
    function removeTokenFromDepositList(address _tokenAddress) external;
    function withdraw(address _token, address _toAddress, uint256 _amount) external;
    function withdrawUnderlying(address _toAddress, uint256 _amount, uint256[] calldata minTokenOut) external;
    function getSplitAllocation() external view returns (uint256[] memory);
    function getBeneficiaries() external view returns (address[] memory);
    function setSplitAllocation(uint256[] calldata _allocations) external;
    function replaceBeneficiaryAt(uint256 _index, address _newBeneficiary, uint256[] calldata _newAllocation)
        external;
    function addBeneficiaryAddress(address _newBeneficiary, uint256[] calldata _newAllocation) external;
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
    MockRegistry mockRegistry;

    // Oracle ( price feeds )
    address constant chainlinkFeedRegistry = 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf;

    // Ox protocol (token swaps)
    address constant zeroExSwapTarget = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;

    // debt dao
    address debtDaoDeployer = makeAddr("debtDaoDeployer");

    // Idle
    address constant idleFeeCollector = 0xBecC659Bfc6EDcA552fa1A67451cC6b38a0108E4;

    address constant idleFeeTreasury = 0x69a62C24F16d4914a48919613e8eE330641Bcb94;

    address constant idleSmartTreasury = 0x859E4D219E83204a2ea389DAc11048CC880B6AA8;

    address constant idleTreasuryLeagueMultiSig = 0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814; // borrower

    address constant idleDeveloperLeagueMultisig = 0xe8eA8bAE250028a8709A3841E0Ae1a44820d677b; // Fee collector admin

    address constant idleTimelock = 0xD6dABBc2b275114a2366555d6C481EF08FDC2556;

    address constant idleStakingFeeSwapper = 0x1594375Eee2481Ca5C1d2F6cE15034816794E8a3;

    address constant idleGovernanceBravo = 0x3D5Fc645320be0A085A32885F078F7121e5E5375;

    address constant idleRebalancer = 0xB3C8e5534F0063545CBbb7Ce86854Bf42dB8872B;

    uint256 constant idleVotingDelay = 1; // in blocks

    uint256 constant idleVotingPeriod = 17280; // in blocks

    uint256 constant idleTimelockDelay = 172800; // in seconds

    uint256 constant idleTimelockDelayBlocks = idleTimelockDelay / 12; // in blocks

    mapping(address => uint256) idleDepositTokensToBalance;

    // $IDLE holders (voters)
    address constant idleCommunityMultisig = 0xb08696Efcf019A6128ED96067b55dD7D0aB23CE4; // 1,203,859 votes
    address constant idleVoterOne = 0x645090dc32eB0950D7C558515cFCDC63D5B4eA6c; // 654,386
    address constant idleVoterTwo = 0xe8eA8bAE250028a8709A3841E0Ae1a44820d677b; // 374,775

    // idle deposit tokens
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // lender
    address daiWhale = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;

    // migration
    address idleSpigotAddress;
    address idleEscrowAddress;
    address idleLineOfCredit;
    string constant dummyProposal =
        "IIP-33: Allow DebtDAO migration contract to take admin control of the Fee Collector https://gov.idle.finance/t/debtdao-migration-for-loan/1056";

    uint256 ttl = 360 days;
    uint256 creditRatio = 0;
    uint256 revenueSplit = 100;
    uint256 loanSizeInDai = 60_000 ether; // 60k dai

    uint256 constant FORK_BLOCK_NUMBER = 16_326_881;

    // fork settings
    uint256 ethMainnetFork;

    event log_named_bytes4(string key, bytes4 value);

    constructor() {
        ethMainnetFork = vm.createFork(vm.envString("ETH_RPC_URL"), FORK_BLOCK_NUMBER);
        vm.selectFork(ethMainnetFork);

        emit log_named_string("rpc", vm.envString("ETH_RPC_URL"));

        emit log_named_address("debtDaoDeployer", debtDaoDeployer);

        vm.startPrank(debtDaoDeployer);

        // create a mock registry for pricing
        mockRegistry = new MockRegistry();
        mockRegistry.addToken(DAI, 1 * 10 ** 18); // $1.00012050
        mockRegistry.addToken(WETH, 12005 * 10 ** 18); // $12005.03050320

        // deploy the oracle with a mock feed registry - chainlink returns
        // a stale price when we roll the fork's block number forward
        oracle = new Oracle(address(mockRegistry));

        // deploy the module factory
        moduleFactory = new ModuleFactory();

        // deploy the line factory
        lineFactory = new LineFactory(
            address(moduleFactory),     // module factory
            debtDaoDeployer,            // arbiter
            address(oracle),            // oracle
            payable(zeroExSwapTarget)   // dex
        );
        vm.stopPrank();
    }

    function setUp() public {
        // perform the tests on the mainnet fork
        vm.selectFork(ethMainnetFork);
    }

    ///////////////////////////////////////////////////////
    //                      T E S T S                    //
    ///////////////////////////////////////////////////////

    // select a specific fork
    function test_can_select_fork() public {
        vm.selectFork(ethMainnetFork);
        assertEq(vm.activeFork(), ethMainnetFork);
        assertEq(block.number, FORK_BLOCK_NUMBER);
    }

    function test_returning_admin_to_timelock() external {
        IdleMigration migration = _deployMigration();

        // incomplete proposal will transfer admin privileges, but won't call `migrate()`
        uint256 proposalId = _submitIncompleteProposal(address(migration));
        _voteAndPassProposal(proposalId, address(migration));

        assert(IFeeCollector(idleFeeCollector).isAddressAdmin(address(migration)));

        vm.expectRevert(IdleMigration.NotIdleMultisig.selector);
        migration.recoverAdmin();

        vm.startPrank(idleTreasuryLeagueMultiSig);

        vm.expectRevert(IdleMigration.CooldownPeriodStillActive.selector);
        migration.recoverAdmin();

        vm.warp(block.timestamp + 31 days);
        migration.recoverAdmin();

        vm.stopPrank();

        assertTrue(IFeeCollector(idleFeeCollector).isAddressAdmin(idleTimelock));
    }

    function test_cannot_migrate_when_not_admin() external {
        IdleMigration migration = _deployMigration();

        vm.startPrank(makeAddr("random1"));
        vm.expectRevert(IdleMigration.TimelockOnly.selector);
        migration.migrate();
        vm.stopPrank();
    }

    function test_can_migrate_when_vote_passes() external {
        IdleMigration migration = _deployMigration();

        // Simulate the governance process, which replaces the admin and performs the migration
        uint256 proposalId = _submitProposal(address(migration));
        _voteAndPassProposal(proposalId, address(migration));

        // simulate the fee collector generating revenue
        uint256 _revenueGenerated = _simulateRevenueGeneration(5 ether);
        uint256 _expectedRevenueDistribution = (_revenueGenerated * 7000) / 10000;

        // Test the spigot's `operate()` method.
        _operatorCallDeposit(migration.spigot());

        _claimRevenueOnBehalfOfSpigot(migration.spigot(), _expectedRevenueDistribution);
    }

    function test_can_migrate_and_repay_loan() external {
        IdleMigration migration = _deployMigration();
        SpigotedLine line = SpigotedLine(payable(migration.securedLine()));

        // Simulate the governance process, which replaces the admin and performs the migration
        uint256 proposalId = _submitProposal(address(migration));
        _voteAndPassProposal(proposalId, address(migration));

        assert(IFeeCollector(idleFeeCollector).isAddressAdmin(migration.spigot()));

        bytes32 id = _lenderFundLoan(migration.securedLine());

        uint256 amountToBorrow = loanSizeInDai;

        // borrow some of the available funds
        vm.startPrank(idleTreasuryLeagueMultiSig);
        ILineOfCredit(migration.securedLine()).borrow(id, amountToBorrow);

        uint256 borrowerDaiBalance = IERC20(DAI).balanceOf(idleTreasuryLeagueMultiSig);

        vm.stopPrank();

        // note: 216_000 blocks in a 30 day period ( at 12s / block )
        // vm.roll(block.number + 216_000);
        vm.warp(block.timestamp + 180 days);

        // update amount of interest accrued
        line.updateOutstandingDebt();

        (, uint256 principal, uint256 interest, uint256 interestRepaid,,,,) = line.credits(id);

        uint256 revenueToSimulate = 100 ether;

        // transfer WETH to the feeCollector, but we still need to distribute funds separately to simulate `deposit()`
        uint256 _revenueGenerated = _simulateRevenueGeneration(revenueToSimulate);

        _operatorCallDeposit(migration.spigot());

        // call claimRevenue
        uint256 expected = (revenueToSimulate * 7000) / 10000;
        _claimRevenueOnBehalfOfSpigot(migration.spigot(), expected);

        assertEq(expected, 70 ether); // expected revenue should be 70*10^18 WETH

        // use trade data generated by 0x API to sell 70 ether worth of ETH for DAI
        // API call: https://api.0x.org/swap/v1/quote?buyToken=DAI&sellToken=WETH&sellAmount=70000000000000000000
        bytes memory tradeData =
            hex"415565b0000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000006b175474e89094c44da98b954eedeac495271d0f000000000000000000000000000000000000000000000003cb71f51fc55800000000000000000000000000000000000000000000000011b465f06f12b111540000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000740000000000000000000000000000000000000000000000000000000000000001a0000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000034000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000002c0000000000000000000000000000000000000000000000003cb71f51fc5580000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000012556e6973776170563300000000000000000000000000000000000000000000000000000000000003cb71f51fc55800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000e592427a0aece92de3edee1f18e0157c058615640000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000002bc02aaa39b223fe8d0a0e5c4f27ead9083c756cc20001f4a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000002e000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000006b175474e89094c44da98b954eedeac495271d0f000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000002a000000000000000000000000000000000000000000000000000000000000002a00000000000000000000000000000000000000000000000000000000000000260ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002a000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000104d616b657250736d0000000000000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0000000000000000000000000000000000000000000011b465f06f12b11154000000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000004000000000000000000000000089b78cfa322f6c5de0abceecab66aee45393cc5a000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000003000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000000000000000000869584cd000000000000000000000000100000000000000000000000000000000000001100000000000000000000000000000000000000000000005d1b7ef56863b4787c";

        // Only the arbiter can call claim and repay
        vm.startPrank(debtDaoDeployer);

        // this calls getOwnerTokens (claims revenue for the owner, ie the spigot)
        ISpigotedLine(migration.securedLine()).claimAndRepay(WETH, tradeData); // swap is performed internally
        vm.stopPrank();

        (, principal, interest, interestRepaid,,,,) = line.credits(id);

        // lender withdraw on line of credit
        vm.startPrank(daiWhale);
        uint256 lenderBalanceBeforeWithdrawl = IERC20(DAI).balanceOf(daiWhale);
        ILineOfCredit(migration.securedLine()).withdraw(id, loanSizeInDai + interestRepaid); // interestRepaid + deposit
        assertEq(IERC20(DAI).balanceOf(daiWhale), lenderBalanceBeforeWithdrawl + loanSizeInDai + interestRepaid);
        vm.stopPrank();

        // principal on position must be zero to close
        // only Borrower can call `close()`
        vm.startPrank(idleTreasuryLeagueMultiSig);
        line.close(id);
        vm.stopPrank();

        (,,,,,,, bool isOpen) = line.credits(id);
        assertTrue(!isOpen);

        emit log_named_uint("status", uint256(line.status()));

        vm.startPrank(idleTreasuryLeagueMultiSig);
        
        // release the spigot (called by the borrow as the line is interestRepaid)
        // Line status must be REPAID or LIQUIDATABLE
        line.releaseSpigot(idleTreasuryLeagueMultiSig);
        ISpigot(migration.spigot()).removeSpigot(idleFeeCollector);
        assertTrue(IFeeCollector(idleFeeCollector).isAddressAdmin(idleTreasuryLeagueMultiSig));

        // replace the admin back to the timelock
        IFeeCollector(idleFeeCollector).replaceAdmin(idleTimelock);
        assertTrue(IFeeCollector(idleFeeCollector).isAddressAdmin(idleTimelock));

        vm.stopPrank();

        // The borrower can call sweep to return their unused tokens
        vm.startPrank(idleTreasuryLeagueMultiSig);
        uint256 claimableUnusedDai = line.unused(DAI);
        // emit log_named_uint("unused DAI", claimableUnusedDai);
        uint256 borrowerDaiBalanceBeforeSweep = IERC20(DAI).balanceOf(idleTreasuryLeagueMultiSig);

        // sweep the unused DAI to return it to the borrower
        line.sweep(idleTreasuryLeagueMultiSig, DAI, claimableUnusedDai);
        assertEq(
            IERC20(DAI).balanceOf(idleTreasuryLeagueMultiSig),
            borrowerDaiBalanceBeforeSweep + claimableUnusedDai,
            "balance should have increased after sweep"
        );

        // unused tokens should be empty
        claimableUnusedDai = line.unused(DAI);
        assertEq(claimableUnusedDai, 0);
        vm.stopPrank();
    }

    /*
        note: this shows the beneficiaries and allocations as they are before and should be after

        Beneficiaries Before:
        0   0x859E4D219E83204a2ea389DAc11048CC880B6AA8  0%      Smart Treasury
        1   0x69a62C24F16d4914a48919613e8eE330641Bcb94  20%     Fee Treasury
        2   0xB3C8e5534F0063545CBbb7Ce86854Bf42dB8872B  30%     Rebalancer
        3   0x1594375Eee2481Ca5C1d2F6cE15034816794E8a3  50%     Staking Fee Swapper


        Beneficiaries After:
        0   0%      Smart Treasury
        1   70%     Spigot
        2   10%     Rebalancer
        3   20%     Staking
    */

    function test_fee_collector_has_correct_beneficiaries_and_allocations_after_migration() public {
        IdleMigration migration = _deployMigration();

        // Simulate the governance process, which replaces the admin and performs the migration
        uint256 proposalId = _submitProposal(address(migration));
        _voteAndPassProposal(proposalId, address(migration));

        assertTrue(IFeeCollector(idleFeeCollector).isAddressAdmin(migration.spigot()));

        _checkAllocationsAndBeneficiaries(migration);
    }

    function test_fee_collector_has_correct_beneficiaries_and_allocations_after_changes_before_migration() public {
        IdleMigration migration = _deployMigration();
        address[] memory feeCollectorBeneficiariesBefore = IFeeCollector(idleFeeCollector).getBeneficiaries();
        uint256[] memory feeCollectorAllocationsBefore = IFeeCollector(idleFeeCollector).getSplitAllocation();

        uint256[] memory newAllocations = new uint256[](5);

        assertTrue(IFeeCollector(idleFeeCollector).isAddressAdmin(idleTimelock));

        vm.startPrank(idleTimelock);

        emit log_named_uint("num beneficiaires", feeCollectorBeneficiariesBefore.length);
        for (uint256 i; i < feeCollectorBeneficiariesBefore.length; ++i) {
            newAllocations[i] = feeCollectorAllocationsBefore[i];
        }

        // add an extra benefificary so we can mix up the order
        newAllocations[4] = 0;
        IFeeCollector(idleFeeCollector).addBeneficiaryAddress(makeAddr("beneficiary5"), newAllocations);

        // fetch beneficiares again so it includes the new "user"
        feeCollectorBeneficiariesBefore = IFeeCollector(idleFeeCollector).getBeneficiaries();

        // zero out the addresses to prevent revert for duplicates
        IFeeCollector(idleFeeCollector).replaceBeneficiaryAt(2, makeAddr("beef1"), newAllocations);
        IFeeCollector(idleFeeCollector).replaceBeneficiaryAt(4, makeAddr("beef3"), newAllocations);
        IFeeCollector(idleFeeCollector).replaceBeneficiaryAt(2, feeCollectorBeneficiariesBefore[4], newAllocations);
        IFeeCollector(idleFeeCollector).replaceBeneficiaryAt(4, feeCollectorBeneficiariesBefore[2], newAllocations);
        (newAllocations[2], newAllocations[4]) = (newAllocations[4], newAllocations[2]);

        IFeeCollector(idleFeeCollector).setSplitAllocation(newAllocations);

        vm.stopPrank();

        // Simulate the governance process, which replaces the admin and performs the migration
        uint256 proposalId = _submitProposal(address(migration));
        _voteAndPassProposal(proposalId, address(migration));

        assertTrue(IFeeCollector(idleFeeCollector).isAddressAdmin(migration.spigot()));

        _checkAllocationsAndBeneficiaries(migration);
    }

    function test_cannot_perform_admin_functions_as_borrower_after_migration() public {
        IdleMigration migration = _deployMigration();

        // Simulate the governance process, which replaces the admin and performs the migration
        uint256 proposalId = _submitProposal(address(migration));
        _voteAndPassProposal(proposalId, address(migration));

        assertTrue(IFeeCollector(idleFeeCollector).isAddressAdmin(migration.spigot()));

        vm.startPrank(idleTreasuryLeagueMultiSig);

        // attempt to replace admin
        vm.expectRevert(bytes("Unauthorised"));
        IFeeCollector(idleFeeCollector).replaceAdmin(idleTreasuryLeagueMultiSig);

        // attempt to call deposit directly
        uint256 _depositTokensLength = IFeeCollector(idleFeeCollector).getNumTokensInDepositList();
        bool[] memory _tokensEnabled = new bool[](_depositTokensLength);
        uint256[] memory _minTokensOut = new uint256[](_depositTokensLength);

        for (uint256 i; i < _tokensEnabled.length;) {
            _tokensEnabled[i] = false;
            unchecked {
                ++i;
            }
        }
        bytes memory data = abi.encodeWithSelector(IFeeCollector.deposit.selector, _tokensEnabled, _minTokensOut, 0);
        vm.expectRevert(bytes("Unauthorised"));
        IFeeCollector(idleFeeCollector).deposit(_tokensEnabled, _minTokensOut, 0);

        // attemp to withdraw
        vm.expectRevert(bytes("Unauthorised"));
        IFeeCollector(idleFeeCollector).withdraw(DAI, idleTreasuryLeagueMultiSig, 1000);

        // attempt to replace admin
        vm.expectRevert(bytes("Unauthorised"));
        IFeeCollector(idleFeeCollector).replaceAdmin(idleTreasuryLeagueMultiSig);

        // attempt to withdraw underlying
        vm.expectRevert(bytes("Unauthorised"));
        IFeeCollector(idleFeeCollector).withdrawUnderlying(idleTreasuryLeagueMultiSig, 10000, _minTokensOut);

        // attempt to remove Token from deposit list
        vm.expectRevert(bytes("Unauthorised"));
        IFeeCollector(idleFeeCollector).removeTokenFromDepositList(DAI);

        // attempt to register token to deposit list
        vm.expectRevert(bytes("Unauthorised"));
        IFeeCollector(idleFeeCollector).registerTokenToDepositList(DAI);

        vm.stopPrank();

        vm.startPrank(idleTimelock);

        vm.expectRevert(bytes("Unauthorised"));
        IFeeCollector(idleFeeCollector).replaceAdmin(idleTimelock);

        vm.expectRevert(bytes("Unauthorised"));
        IFeeCollector(idleFeeCollector).deposit(_tokensEnabled, _minTokensOut, 0);

        vm.stopPrank();
    }

    function test_chainlink_price_feed() external {
        int256 daiPrice = oracle.getLatestAnswer(DAI);
        emit log_named_int("DAI price", daiPrice);
        assert(daiPrice > 0);
    }

    function test_migration_vote_not_passed() external {
        IdleMigration migration = _deployMigration();

        // governance
        _proposeAndVoteToFail(address(migration));
    }

    function test_migration_vote_but_no_quorum() external {
        IdleMigration migration = _deployMigration();

        // governance
        _proposeAndNoQuorum(address(migration));
    }

    ///////////////////////////////////////////////////////
    //          I N T E R N A L   H E L P E R S          //
    ///////////////////////////////////////////////////////

    // deploy the migration contract
    function _deployMigration() internal returns (IdleMigration migration) {
        migration = new IdleMigration(
            address(lineFactory),   // line factory
            90 days                 // ttl
        );
    }

    // fund a loan as a lender
    function _lenderFundLoan(address _lineOfCredit) internal returns (bytes32 id) {
        assertEq(vm.activeFork(), ethMainnetFork, "mainnet fork is not active");

        // vm.roll(block.number + 5000);

        vm.startPrank(idleTreasuryLeagueMultiSig);
        ILineOfCredit(_lineOfCredit).addCredit(
            1000, // drate
            1000, // frate
            loanSizeInDai, // amount
            DAI, // token
            daiWhale // lender
        );
        vm.stopPrank();

        vm.startPrank(daiWhale);
        IERC20(DAI).approve(_lineOfCredit, loanSizeInDai);
        id = ILineOfCredit(_lineOfCredit).addCredit(
            1000, // drate
            1000, // frate
            loanSizeInDai, // amount
            DAI, // token
            daiWhale // lender
        );
        vm.stopPrank();

        assertEq(IERC20(DAI).balanceOf(address(_lineOfCredit)), loanSizeInDai, "LoC balance doesn't match");

        emit log_named_bytes32("credit id", id);
    }

    function _simulateRevenueGeneration(uint256 amt) internal returns (uint256 revenue) {
        vm.deal(idleFeeCollector, amt + 0.5 ether); // add a bit to cover gas

        vm.prank(idleFeeCollector);
        revenue = amt;
        IWeth(WETH).deposit{value: revenue}();

        assertEq(IERC20(WETH).balanceOf(idleFeeCollector), revenue, "fee collector balance should match revenue");
    }

    /// @dev    Because they claim function is not set in the spigot, this will be a push payment only
    /// @dev    We need to call `deposit()` manually before claiming revenue, or there will be no revenue
    ///         to claim (because calling `deposit()` distribute revenue to beneficiaires,of which the spigot is one)
    function _claimRevenueOnBehalfOfSpigot(address _spigot, uint256 _expectedRevenue) internal {
        bytes memory data = abi.encodePacked("");
        ISpigot(_spigot).claimRevenue(idleFeeCollector, WETH, data);
        assertEq(_expectedRevenue, IERC20(WETH).balanceOf(_spigot), "balance of spigot should match expected revenue");
    }

    function _operatorCallDeposit(address _spigot) internal {
        uint256 _depositTokensLength = IFeeCollector(idleFeeCollector).getNumTokensInDepositList();
        bool[] memory _tokensEnabled = new bool[](_depositTokensLength);
        uint256[] memory _minTokensOut = new uint256[](_depositTokensLength);

        // we'll skip the swapping and just send the Weth directly to the contract,
        // so all deposit tokens can be disabled
        for (uint256 i; i < _tokensEnabled.length;) {
            _tokensEnabled[i] = false;
            unchecked {
                ++i;
            }
        }

        bytes memory data = abi.encodeWithSelector(IFeeCollector.deposit.selector, _tokensEnabled, _minTokensOut, 0);

        assertEq(IFeeCollector.deposit.selector, bytes4(data), "deposit selector should match first 4 bytes of data");

        require(ISpigot(_spigot).isWhitelisted(bytes4(data)), "Not Whitelisted");

        // test the function that was whitelisted in the migration contract
        vm.startPrank(idleTreasuryLeagueMultiSig);
        assertEq(idleTreasuryLeagueMultiSig, ISpigot(_spigot).operator(), "treasury multisig should be operator");
        ISpigot(_spigot).operate(idleFeeCollector, data);
        vm.stopPrank();
    }

    function _submitIncompleteProposal(address migrationContract) internal returns (uint256 id) {
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
            uint256(IGovernorBravo.ProposalState.Active),
            "state should be active"
        );

        vm.stopPrank();
    }

    function _submitProposal(address migrationContract) internal returns (uint256 id) {
        vm.startPrank(idleDeveloperLeagueMultisig);

        address[] memory targets = new address[](2);
        targets[0] = idleFeeCollector;
        targets[1] = migrationContract;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        string[] memory signatures = new string[](2);
        signatures[0] = "replaceAdmin(address)";
        signatures[1] = "migrate()";

        bytes[] memory calldatas = new bytes[](2);
        calldatas[0] = abi.encode(migrationContract); // instead of using encodePacked which removes padding, calldata expects 32byte chunks
        calldatas[1] = abi.encode("");

        id = IGovernorBravo(idleGovernanceBravo).propose(targets, values, signatures, calldatas, dummyProposal);

        emit log_named_uint("proposal id: ", id);

        // voting can only start after the delay
        vm.roll(block.number + idleVotingDelay + 1);

        assertEq(
            uint256(IGovernorBravo(idleGovernanceBravo).state(id)),
            uint256(IGovernorBravo.ProposalState.Active),
            "governor bravo state should be active"
        );

        vm.stopPrank();
    }

    function _voteAndPassProposal(uint256 id, address migrationContract) internal {
        vm.prank(idleCommunityMultisig);
        IGovernorBravo(idleGovernanceBravo).castVote(id, 1);

        // voting ends once the voting period is over
        vm.roll(block.number + idleVotingPeriod + 1);

        assertEq(
            uint256(IGovernorBravo(idleGovernanceBravo).state(id)),
            uint256(IGovernorBravo.ProposalState.Succeeded),
            "governor bravo state should be succeeded"
        );

        // queue the tx
        IGovernorBravo(idleGovernanceBravo).queue(id);
        assertEq(
            uint256(IGovernorBravo(idleGovernanceBravo).state(id)),
            uint256(IGovernorBravo.ProposalState.Queued),
            "governor bravo state should be queued"
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
            uint256(IGovernorBravo.ProposalState.Defeated),
            "governor bravo state should be defeated"
        );

        // expect the request to queue to be reverted
        vm.expectRevert(bytes("GovernorBravo::queue: proposal can only be queued if it is succeeded"));
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
            uint256(IGovernorBravo.ProposalState.Defeated),
            "governor bravo state should be defeated"
        );

        // expect the request to queue to be reverted
        vm.expectRevert(bytes("GovernorBravo::queue: proposal can only be queued if it is succeeded"));
        IGovernorBravo(idleGovernanceBravo).queue(id);
    }

    function _checkAllocationsAndBeneficiaries(IdleMigration migration) internal {
        address[] memory feeCollectorBeneficiaries = IFeeCollector(idleFeeCollector).getBeneficiaries();
        uint256[] memory feeCollectorAllocations = IFeeCollector(idleFeeCollector).getSplitAllocation();

        assertEq(feeCollectorBeneficiaries[0], idleSmartTreasury);
        assertEq(feeCollectorAllocations[0], 0);

        assertEq(feeCollectorBeneficiaries[1], migration.spigot());
        assertEq(feeCollectorAllocations[1], 70000);

        assertEq(feeCollectorBeneficiaries[2], idleRebalancer);
        assertEq(feeCollectorAllocations[2], 10000);

        assertEq(feeCollectorBeneficiaries[3], idleStakingFeeSwapper);
        assertEq(feeCollectorAllocations[3], 20000);

        for (uint256 i = 4; i < feeCollectorAllocations.length; ++i) {
            assertEq(feeCollectorAllocations[i], 0, "allocation should be zero");
        }
    }

    ///////////////////////////////////////////////////////
    //                      U T I L S                    //
    ///////////////////////////////////////////////////////

    // returns the function selector (first 4 bytes) of the hashed signature
    function _getSelector(string memory _signature) internal pure returns (bytes4) {
        return bytes4(keccak256(bytes(_signature)));
    }
}
