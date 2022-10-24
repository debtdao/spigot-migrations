// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {ISpigot} from "Line-of-Credit/interfaces/ISpigot.sol";
import {Spigot} from "Line-of-Credit/modules/spigot/Spigot.sol";
import {SecuredLine} from "Line-of-Credit/modules/credit/SecuredLine.sol";
import {ISecuredLine} from "Line-of-Credit/interfaces/ISecuredLine.sol";
import {ISpigotedLine} from "Line-of-Credit/interfaces/ISpigotedLine.sol";
import {SpigotedLine} from "Line-of-Credit/modules/credit/SpigotedLine.sol";
import {ModuleFactory} from "Line-of-Credit/modules/factories/ModuleFactory.sol";
import {LineFactory} from "Line-of-Credit/modules/factories/LineFactory.sol";

import {ILineFactory} from "Line-of-Credit/interfaces/ILineFactory.sol";

interface IFeeCollector {
    function hasRole(bytes32 role, address account) external returns (bool);

    function isAddressAdmin(address _address) external view returns (bool);

    function replaceAdmin(address _newAdmin) external;

    function replaceBeneficiaryAt(
        uint256 _index,
        address _newBeneficiary,
        uint256[] calldata _newAllocation
    ) external;
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

    bool migrationComplete;

    event MigrationComplete();

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

    /*
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
    function migrate() external onlyOwner {
        require(
            IFeeCollector(feeCollector).isAddressAdmin(address(this)),
            "Migration contract is not an admin"
        );
        require(!migrationComplete, "Migration is complete");
        migrationComplete = true;

        // add the revenue contract
        ISpigot.Setting memory spigotSettings = ISpigot.Setting(
            100, // 100% to owner
            _getSelector(
                "withdraw(address _token, address _toAddress, uint256 _amount)"
            ), // claim fn
            _getSelector("replaceAdmin(address _newAdmin)") // transferOwnerFn
        );

        // add the spigot to the line
        ISpigotedLine(lineOfCredit).addSpigot(feeCollector, spigotSettings);

        ISpigotedLine spigotedLine = ISpigotedLine(lineOfCredit);

        // retrieve the spigot and cast to address
        address spigotAddress = address(spigotedLine.spigot());

        // update the beneficiaries by replacing the Fee Treasury at index 1
        IFeeCollector(feeCollector).replaceBeneficiaryAt(
            1,
            spigotAddress, // spgiot address
            [
                0, // smart treasury
                70000, // spigot
                10000, // rebalancer
                20000 // staking
            ]
        );

        // transfer ownership to spigot
        // TODO: can spigot call "replaceAdmin" on feeCollector?
        IFeeCollector(feeCollector).replaceAdmin(spigotAddress);

        emit MigrationComplete();
    }

    function returnAdmin(address newAdmin_) external onlyOwner {
        require(!migrationComplete, "Migration hsa been completed");
        IFeeCollector(feeCollector).replaceAdmin(newAdmin_);
    }

    // ===================== Internal

    function _getSelector(string memory _func) internal pure returns (bytes4) {
        return bytes4(keccak256(bytes(_func)));
    }

    // ===================== Modifiers

    modifier onlyOwner() {
        require(msg.sender == owner, "Migration: Unauthorized");
        _;
    }
}
