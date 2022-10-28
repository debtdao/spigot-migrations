// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {ISpigot} from "Line-of-Credit/interfaces/ISpigot.sol";
import {Spigot} from "Line-of-Credit/modules/spigot/Spigot.sol";
import {SecuredLine} from "Line-of-Credit/modules/credit/SecuredLine.sol";
import {ISecuredLine} from "Line-of-Credit/interfaces/ISecuredLine.sol";

import {ISpigot} from "Line-of-Credit/interfaces/ISpigot.sol";

import {IEscrow} from "Line-of-Credit/interfaces/IEscrow.sol";
import {ISpigotedLine} from "Line-of-Credit/interfaces/ISpigotedLine.sol";

import {IModuleFactory} from "Line-of-Credit/interfaces/IModuleFactory.sol";
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
    // admin
    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
    address private immutable owner;

    // trusted 3rd-parties
    address private constant zeroExSwapTarget =
        0xDef1C0ded9bec7F1a1670819833240f027b25EfF;

    // debtdao
    address private immutable debtDaoDeployer;
    address private immutable oracle;
    address private immutable moduleFactory;

    // Idle
    address private immutable feeCollector;
    address private immutable idleTreasuryMultisig;
    address private immutable idleTimelock;

    // migration
    address public immutable spigot;
    address immutable escrow;
    address immutable securedLine;

    bool migrationComplete;

    event MigrationComplete();

    error NotFeeCollectorAdmin();
    error MigrationFailed();

    // 0 - deploy spigot
    // 1 - take owner ship of revenue contract from governance
    // 2 - transfer ownership of revenue to spigot
    // 3 - test revenue can be claimed
    // TODO: determine which addresses to save
    // TODO: add deadmans switch with timestamp + duration ( in case migration fails )
    // TODO: if the migration contract is still the owner of the spigot and escrow, and not owned by line
    // should be transferred back
    constructor(
        address moduleFactory_,
        address lineFactory_,
        address revenueContract_,
        address idleTreasuryMultisig_,
        address timelock_,
        address debtDaoDeployer_,
        address oracle_,
        address borrower_,
        uint256 ttl_
    ) {
        owner = msg.sender; // presumably Idle Deployer
        moduleFactory = moduleFactory_;
        debtDaoDeployer = debtDaoDeployer_;
        feeCollector = revenueContract_;
        idleTreasuryMultisig = idleTreasuryMultisig_;
        idleTimelock = timelock_;
        oracle = oracle_;

        // deploy spigot
        spigot = IModuleFactory(moduleFactory_).deploySpigot(
            address(this), // owner - debtdaoMultisig // TODO: change this to multisig
            idleTreasuryMultisig_, // treasury - Treasury Multisig
            idleTreasuryMultisig_ // operator - Treasury Multisig
        );

        // deploy escrow
        escrow = IModuleFactory(moduleFactory_).deployEscrow(
            0, // min credit ratio
            oracle_, // oracle
            address(this), // owner
            idleTreasuryMultisig_ // borrower
        );

        ILineFactory.CoreLineParams memory coreParams = ILineFactory
            .CoreLineParams({
                borrower: borrower_, // idleTreasuryLeagueMultiSig,
                ttl: ttl_,
                cratio: 0, //uint32(creditRatio),
                revenueSplit: 100 //uint8(revenueSplit)
            });

        // lineOfCredit = ILineFactory(lineFactory_).deploySecuredLineWithConfig(
        //     coreParams
        // );

        securedLine = ILineFactory(lineFactory_).deploySecuredLineWithModules(
            coreParams,
            spigot,
            escrow
        );
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
    function migrate() external onlyAuthorized {
        if (!IFeeCollector(feeCollector).isAddressAdmin(address(this))) {
            revert NotFeeCollectorAdmin();
        }

        require(!migrationComplete, "Migration is complete");
        migrationComplete = true;

        // add the revenue contract
        // programs the function into the spigot which gets called when remove Spigot
        // the operator is the entity to whom the spigot is returned when loan is repaid
        /// @dev abi.encodeWithSignature/selector gives the full calldata, not the fn selector
        ISpigot.Setting memory spigotSettings = ISpigot.Setting(
            100, // 100% to owner
            _getSelector("withdraw(address,address,uint256)"), // claim fn
            _getSelector("replaceAdmin(address)") // transferOwnerFn // gets transferred to operator
        );

        // add the spigot to the line
        // ISpigotedLine(lineOfCredit).addSpigot(feeCollector, spigotSettings);

        // add a revenue stream
        ISpigot(spigot).addSpigot(feeCollector, spigotSettings);

        // transfer ownership of spigot and escrow to line
        // TODO: test these
        ISpigot(spigot).updateOwner(securedLine);
        IEscrow(escrow).updateLine(securedLine);

        require(
            ISpigot(spigot).owner() == securedLine,
            "Migration: Spigot owner transfer failed"
        );
        require(
            IEscrow(escrow).line() == securedLine,
            "Migration: Escrow line transfer failed"
        );

        // update the beneficiaries by replacing the Fee Treasury at index 1
        uint256[] memory newAllocations = new uint256[](4);
        newAllocations[0] = 0; // smart treasury
        newAllocations[1] = 70000; // spigot
        newAllocations[2] = 10000; // rebalancer
        newAllocations[3] = 20000; // staking

        IFeeCollector(feeCollector).replaceBeneficiaryAt(
            1,
            spigot, // spgiot address
            newAllocations
        );

        // transfer ownership to spigot
        // TODO: can spigot call "replaceAdmin" on feeCollector?
        // IFeeCollector(feeCollector).replaceAdmin(spigotAddress);
        IFeeCollector(feeCollector).replaceAdmin(spigot);

        // require spigot is admin on fee collector
        require(
            IFeeCollector(feeCollector).isAddressAdmin(spigot),
            "Migration: Spigot is not the feeCollector admin"
        );

        emit MigrationComplete();
    }

    function returnAdmin(address newAdmin_) external onlyAuthorized {
        require(!migrationComplete, "Migration has been completed");
        IFeeCollector(feeCollector).replaceAdmin(newAdmin_);
    }

    // ===================== Internal

    function _getSelector(string memory _func) internal pure returns (bytes4) {
        return bytes4(keccak256(bytes(_func))); //TODO: use abi encode with selector
    }

    // ===================== Modifiers

    modifier onlyAuthorized() {
        // TODO: improve error messages
        require(
            msg.sender == owner || msg.sender == idleTimelock,
            "Migration: Unauthorized user"
        );
        _;
    }
}
