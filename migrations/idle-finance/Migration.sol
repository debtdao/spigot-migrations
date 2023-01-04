// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {ISpigot} from "Line-of-Credit/interfaces/ISpigot.sol";
import {ILineOfCredit} from "Line-of-Credit/interfaces/ILineOfCredit.sol";
import {ISpigot} from "Line-of-Credit/interfaces/ISpigot.sol";
import {LineLib} from "Line-of-Credit/utils/LineLib.sol";
import {IEscrow} from "Line-of-Credit/interfaces/IEscrow.sol";
import {ISpigotedLine} from "Line-of-Credit/interfaces/ISpigotedLine.sol";
import {IModuleFactory} from "Line-of-Credit/interfaces/IModuleFactory.sol";
import {ILineFactory} from "Line-of-Credit/interfaces/ILineFactory.sol";

/// @dev    We define our own interface to avoid Solidity version conflicts
///         that would occur by importing Idle Contracts as a lib.
interface IFeeCollector {
    function hasRole(bytes32 role, address account) external returns (bool);

    function isAddressAdmin(address _address) external view returns (bool);

    function replaceAdmin(address _newAdmin) external;

    function replaceBeneficiaryAt(uint256 _index, address _newBeneficiary, uint256[] calldata _newAllocation)
        external;

    function removeBeneficiaryAt(uint256 _index, uint256[] calldata _newAllocation) external;

    function deposit(bool[] memory _depositTokensEnabled, uint256[] memory _minTokenOut, uint256 _minPoolAmountOut)
        external;

    function addAddressToWhiteList(address _addressToAdd) external;

    function getBeneficiaries() external view returns (address[] memory);

    function setSmartTreasuryAddress(address _smartTreasuryAddress) external;
}

/// @title  Idle Migration Contract
/// @author DebtDAO
/// @notice Deploys the Line of Credit and assosciated contracts, and
///         facilitates the transfer of admin privileges to the Spigot
/// @dev    A Secured Line Of Credit is deployed during contract creation.
/// @dev    In order to successfully facilitate the migration, this contract
///         requires admin privileges on the Idle Fee Collector.  This privilige
///         escalation takes place in the first step of the governance proposal
///         executed by the Idle Timelock.
contract IdleMigration {
    // interfaces
    IFeeCollector iFeeCollector;
    ISpigot iSpigot;

    // DEX
    address private constant zeroExSwapTarget = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;

    // Idle Contracts

    address private constant idleTreasuryLeagueMultisig = 0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814;

    address private constant idleStakingFeeSwapper = 0x1594375Eee2481Ca5C1d2F6cE15034816794E8a3;

    address private constant idleSmartTreasury = 0x859E4D219E83204a2ea389DAc11048CC880B6AA8; // multisig

    address private constant idleFeeCollector = 0xBecC659Bfc6EDcA552fa1A67451cC6b38a0108E4;

    address private constant idleFeeTreausry = 0x69a62C24F16d4914a48919613e8eE330641Bcb94;

    address private constant idleRebalancer = 0xB3C8e5534F0063545CBbb7Ce86854Bf42dB8872B;

    address private constant idleTimelock = 0xD6dABBc2b275114a2366555d6C481EF08FDC2556;

    // migration

    address public immutable securedLine;

    address public immutable spigot;

    address public immutable escrow;

    bool migrationSucceeded;

    uint256 deployedAt;

    uint256 private constant cooldownPeriod = 30 days;

    /*//////////////////////////////////////////////////////////////
                            E V E N T S
    //////////////////////////////////////////////////////////////*/

    event MigrationDeployed(address indexed spigot, address indexed escrow, address indexed line);

    event ReplacedBeneficiary(uint256 index, address contractAddress, uint256 allocation);

    event MigrationSucceeded();

    /*//////////////////////////////////////////////////////////////
                            E R R O R S
    //////////////////////////////////////////////////////////////*/

    error NoRecoverAfterSuccessfulMigration();

    error SpigotOwnershipTransferFailed();

    error EscrowOwnershipTransferFailed();

    error CooldownPeriodStillActive();

    error MigrationAlreadyComplete();

    error NotFeeCollectorAdmin();

    error ReplaceAdminFailed();

    error MigrationFailed();

    error NotIdleMultisig();

    error SpigotNotAdmin();

    error LineNotActive();

    error TimelockOnly();

    /*//////////////////////////////////////////////////////////////
                        C O N S T R U C T O R
    //////////////////////////////////////////////////////////////*/

    constructor(address lineFactory_, uint256 ttl_) {
        deployedAt = block.timestamp;

        iFeeCollector = IFeeCollector(idleFeeCollector);

        // deploy spigot
        spigot = ILineFactory(lineFactory_).deploySpigot(
            address(this), // owner
            idleTreasuryLeagueMultisig // operator - Treasury Multisig
        );
        iSpigot = ISpigot(spigot);

        // deploy escrow
        escrow = ILineFactory(lineFactory_).deployEscrow(
            0, // min credit ratio
            address(this), // owner
            idleTreasuryLeagueMultisig // borrower
        );

        // note:    The Fee Collector distributes revenue to multiple beneficiaries, we want 100% of the
        //          revenue sent to the spigot to go to paying back the loan, therefore revenueSplit = 100%
        ILineFactory.CoreLineParams memory coreParams = ILineFactory.CoreLineParams({
            borrower: idleTreasuryLeagueMultisig,
            ttl: ttl_, // time to live
            cratio: 0, // uint32(creditRatio),
            revenueSplit: 100 // uint8(revenueSplit) - 100% to spigot
        });

        // deploy the line of credit
        securedLine = ILineFactory(lineFactory_).deploySecuredLineWithModules(coreParams, spigot, escrow);

        emit MigrationDeployed(spigot, escrow, securedLine);
    }

    /*//////////////////////////////////////////////////////
                        M O D I F I E R S                  
    //////////////////////////////////////////////////////*/

    /// @dev    should only be callable by the timelock contract
    modifier onlyAuthorized() {
        if (msg.sender != idleTimelock) revert TimelockOnly();
        _;
    }

    modifier onlyIdle() {
        if (msg.sender != idleTreasuryLeagueMultisig) revert NotIdleMultisig();
        _;
    }

    /*//////////////////////////////////////////////////////
                    M I G R A T I O N   L O G I C                  
    //////////////////////////////////////////////////////*/

    /// @notice Performs the migration
    /// @dev    Can only be called my an authorized user, ie the governance Timelock
    /// @dev    Adds a revenue stream to the Spigot, and makes the Line of Credit the owner
    ///         of the Spigot and Escrow contracts
    function migrate() external onlyAuthorized {
        if (!iFeeCollector.isAddressAdmin(address(this))) {
            revert NotFeeCollectorAdmin();
        }
        if (migrationSucceeded) {
            revert MigrationAlreadyComplete();
        }

        migrationSucceeded = true;

        // programs the function into the spigot which gets called when Spigot is removed
        // the operator is the entity to whom the spigot is returned when loan is repaid
        ISpigot.Setting memory spigotSettings = ISpigot.Setting(
            100, // 100% to owner
            bytes4(0), // no claim fn, indicating push payments only
            _getSelector("replaceAdmin(address)") // transferOwnerFn (gets transferred to operator)
        );

        // add a revenue stream
        iSpigot.addSpigot(idleFeeCollector, spigotSettings);

        // we need to whitelist the spigot in order for it to call `deposit` on behalf of the operator
        iFeeCollector.addAddressToWhiteList(spigot);

        // add `desposit()` as a whitelisted fn so the operator can call it
        bytes4 depositSelector = IFeeCollector.deposit.selector;
        iSpigot.updateWhitelistedFunction(
            depositSelector, // selector
            true
        );

        require(iSpigot.isWhitelisted(depositSelector), "Migration: deposit not whitelisted for operator");

        // transfer ownership of spigot and escrow to line of credit
        iSpigot.updateOwner(securedLine);
        if (iSpigot.owner() != securedLine) {
            revert SpigotOwnershipTransferFailed();
        }

        IEscrow(escrow).updateLine(securedLine);
        if (IEscrow(escrow).line() != securedLine) {
            revert EscrowOwnershipTransferFailed();
        }

        // initialize the line
        LineLib.STATUS status = ILineOfCredit(securedLine).init();

        if (status != LineLib.STATUS.ACTIVE) {
            revert LineNotActive();
        }

        // add the spigot as beneficiary and update allocations
        _setBeneficiariesAndAllocations();

        // transfer ownership (admin priviliges) to spigot
        iFeeCollector.replaceAdmin(spigot);

        // ensure spigot is admin on fee collector
        if (!iFeeCollector.isAddressAdmin(spigot)) {
            revert SpigotNotAdmin();
        }

        emit MigrationSucceeded();
    }

    /*//////////////////////////////////////////////////////
                       R E C O V E R Y                 
    //////////////////////////////////////////////////////*/

    /// @notice Recovers ownership of the revenue contract in the event of a failed migration
    /// @dev    predicated on the migration contract being a priviliged admin
    function recoverAdmin() external onlyIdle {
        if (migrationSucceeded) {
            revert NoRecoverAfterSuccessfulMigration();
        }

        if (block.timestamp < deployedAt + cooldownPeriod) {
            revert CooldownPeriodStillActive();
        }

        // return ownership from the migration contract to the Timelock
        iFeeCollector.replaceAdmin(idleTimelock);
        if (!iFeeCollector.isAddressAdmin(idleTimelock)) {
            revert ReplaceAdminFailed();
        }

        // transfer ownership of the spigot to the Idle Treasury League Multisig
        iSpigot.updateOwner(idleTreasuryLeagueMultisig);
        if (iSpigot.owner() != idleTreasuryLeagueMultisig) {
            revert SpigotOwnershipTransferFailed();
        }
    }

    /*//////////////////////////////////////////////////////
                        I N T E R N A L                    
    //////////////////////////////////////////////////////*/

    /// @dev This function is a safeguard against the protocol switching beneficiaries
    ///      or changing allocations between the deployment of the migration contract and the migration
    ///      itself by replacing any duplicate beneficiary addresses.
    function _setBeneficiariesAndAllocations() internal {
        address[] memory existingBeneficiaries = iFeeCollector.getBeneficiaries();

        // we need the number of beneficiaries to be at minimum 4
        uint256 numBeneficiaries = existingBeneficiaries.length < 4 ? 4 : existingBeneficiaries.length;

        uint256[] memory newAllocations = new uint256[](numBeneficiaries);

        newAllocations[0] = 0; // smart treasury
        newAllocations[1] = 70000; // spigot
        newAllocations[2] = 10000; // rebalancer
        newAllocations[3] = 20000; // staking

        // zero-out any additional beneficiary allocations (therefore no need to worry about addresses)
        if (numBeneficiaries > 4) {
            for (uint256 i = 4; i < numBeneficiaries;) {
                newAllocations[i] = 0;
                unchecked {
                    ++i;
                }
            }
        }

        // check if index 0 is smart treasury and replace if need be
        if (existingBeneficiaries[0] != idleSmartTreasury) {
            iFeeCollector.setSmartTreasuryAddress(idleSmartTreasury);
            existingBeneficiaries[0] = idleSmartTreasury;
            emit ReplacedBeneficiary(0, idleSmartTreasury, newAllocations[0]);
        }

        // add the spigot as a beneficiary at index 1
        iFeeCollector.replaceBeneficiaryAt(1, spigot, newAllocations);
        existingBeneficiaries[1] = spigot;
        emit ReplacedBeneficiary(1, spigot, newAllocations[1]);

        // memory variables to be reused
        address temp;
        bool hasDuplicate;
        uint256 idx;

        // replace the address at index 2 with the rebalancer if it isn't at this index
        if (existingBeneficiaries[2] != idleRebalancer) {
            (hasDuplicate, idx) = _hasDuplicate(existingBeneficiaries, idleRebalancer);
            if (hasDuplicate && idx != 2) {
                temp = address(uint160(2 * block.timestamp));
                iFeeCollector.replaceBeneficiaryAt(idx, temp, newAllocations);
                existingBeneficiaries[idx] = temp;
                emit ReplacedBeneficiary(idx, temp, 0);
            } 
            iFeeCollector.replaceBeneficiaryAt(2, idleRebalancer, newAllocations);
            existingBeneficiaries[2] = idleRebalancer;
            emit ReplacedBeneficiary(2, idleRebalancer, newAllocations[2]);
        }

        // replace the address at index 3 with the fee swapper if it isn't at this index
        if (existingBeneficiaries[3] != idleStakingFeeSwapper) {
            (hasDuplicate, idx) = _hasDuplicate(existingBeneficiaries, idleRebalancer);
            if (hasDuplicate && idx != 3) {
                temp = address(uint160(2 * block.timestamp));
                iFeeCollector.replaceBeneficiaryAt(idx, temp, newAllocations);
                existingBeneficiaries[idx] = temp;
                emit ReplacedBeneficiary(idx, temp, 0);
            }
            iFeeCollector.replaceBeneficiaryAt(3, idleStakingFeeSwapper, newAllocations);
            emit ReplacedBeneficiary(3, idleStakingFeeSwapper, newAllocations[3]);
        }
    }

    /*//////////////////////////////////////////////////////
                            U T I L S                    
    //////////////////////////////////////////////////////*/

    /// @notice Generates and returns the function selector from the signature provided
    /// @dev    The signature includes only the argument types, and omits the names
    /// @param  signature The function's signature
    /// @return The 4-byte function selector of the signature provided in `signature`
    function _getSelector(string memory signature) internal pure returns (bytes4) {
        return bytes4(keccak256(bytes(signature)));
    }

    /// @notice Checks if the beneficiaries array contains a duplicate address in a different position
    /// @dev    We know that the smartTreasury address will always be at index 0, so we can return 0 as null
    /// @param  beneficiaries List of the existing beneficiary addresses
    /// @param  addressToCheck The address to check against for duplicates
    /// @return True if a duplicate exists, along with the index at which the duplicate is located
    function _hasDuplicate(address[] memory beneficiaries, address addressToCheck) internal returns (bool, uint256) {
        for (uint256 i; i < beneficiaries.length;) {
            if (beneficiaries[i] == addressToCheck) return (true, i);
            unchecked {
                ++i;
            }
        }
        return (false, 0);
    }
}
