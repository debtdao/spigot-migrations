// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

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

    function replaceBeneficiaryAt(
        uint256 _index,
        address _newBeneficiary,
        uint256[] calldata _newAllocation
    ) external;

    function removeBeneficiaryAt(uint256 _index, uint256[] calldata _newAllocation) external;

    function deposit(
        bool[] memory _depositTokensEnabled,
        uint256[] memory _minTokenOut,
        uint256 _minPoolAmountOut
    ) external;

    function addAddressToWhiteList(address _addressToAdd) external;

    function getBeneficiaries() external view returns (address[] memory);

    function setSmartTreasuryAddress(address _smartTreasuryAddress) external;

    function addBeneficiaryAddress(address _newBeneficiary, uint256[] calldata _newAllocation) external;
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

    bool migrationSucceeded;

    uint256 immutable deployedAt;

    address public immutable securedLine;

    address public immutable spigot;

    address public immutable escrow;

    uint256 private constant COOLDOWN_PERIOD = 30 days;

    uint256 private constant TARGET_BENEFICIARIES_LENGTH = 4;

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

    /// @notice Initializes the migration contract
    /// @dev Sets the LineFactory address, Time-to-live (ttl) and `deployedAt` time
    /// @dev Deploys the Spigot and Escrow contracts via the LineFactory
    /// @dev Deploys a Secured Line of Credit for the FeeCollector
    /// @param lineFactory_ The deployed LineFactory address
    /// @param ttl_ Time-to-live for the loan
    constructor(address lineFactory_, uint256 ttl_, uint32 minCreditRatio_, uint32 creditRatio_) {
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
            minCreditRatio_, // min credit ratio
            address(this), // owner
            idleTreasuryLeagueMultisig // borrower
        );

        // note:    The Fee Collector distributes revenue to multiple beneficiaries, we want 100% of the
        //          revenue sent to the spigot to go to paying back the loan, therefore revenueSplit = 100%
        ILineFactory.CoreLineParams memory coreParams = ILineFactory.CoreLineParams({
            borrower: idleTreasuryLeagueMultisig,
            ttl: ttl_,              // time to live
            cratio: creditRatio_,   // uint32(creditRatio),
            revenueSplit: 100         // uint8(revenueSplit) - 100% to spigot
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

    /// @dev    For functions that can only be called by the Idle Treasury League Multisig
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
    /// @dev    Adds the Spigot as a whitelisted address on the FeeCollector and sets the `deposit()` fn
    ///         as a whitelist function on the Spigot.
    /// @dev    Transfers ownership of the Spigot and Escrow to the SecuredLine, then initializes the Line
    /// @dev    Sets the list of beneficiaries and their allocations, and sets the Spigot as the FeeCollector's admin
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
            100, // 100% to owner (spigot)
            bytes4(0), // no claim fn, indicating push payments only
            _getSelector("replaceAdmin(address)") // transferOwnerFn (gets transferred to operator)
        );

        // add a revenue stream
        iSpigot.addSpigot(idleFeeCollector, spigotSettings);

        // we need to whitelist the spigot in order for it to call `deposit` on behalf of the operator
        iFeeCollector.addAddressToWhiteList(spigot);

        // add `deposit()` as a whitelisted fn so the operator can call it
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

        if (block.timestamp < deployedAt + COOLDOWN_PERIOD) {
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

    /// @notice Sets the list of beneficiaries for the FeeCollector and their corresponding allocation values
    /// @dev This function includes a safeguard against the protocol switching beneficiaries
    ///      or changing allocations between the deployment of the migration contract and the migration occurring
    ///      by replacing any duplicate beneficiary addresses.
    /// @dev Updating the beneficiaries list is inherently gas-inefficient as there is no way to batch set
    ///      addresses, and the allocations are set with every change, making this function extremely gas-heavy
    ///      to do in a safe and secure way
    /// @dev The behaviour of this function, and therefore cost to execute, will vary based on the number of existing
    ///      beneficiaries present in the FeeCollector, as determiend by `MIN_BENEFICIARIES and `MAX_BENEFICIARIES` on
    ///      the FeeCollector, as a new uint256[] needs to be dynamically created in memory for every step over, or
    ///      above, an array length of `TARGET_BENEFICIARIES_LENGTH`.
    function _setBeneficiariesAndAllocations() internal {
        address[] memory existingBeneficiaries = iFeeCollector.getBeneficiaries();
        uint256 numBeneficiaries = existingBeneficiaries.length; // gas-saving

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
        3   20%     Staking Fee Swapper
        */

        // set the target beneficiaries
        address[] memory targetBeneficiaries = new address[](TARGET_BENEFICIARIES_LENGTH);
        targetBeneficiaries[0] = idleSmartTreasury;
        targetBeneficiaries[1] = spigot;
        targetBeneficiaries[2] = idleRebalancer;
        targetBeneficiaries[3] = idleStakingFeeSwapper;

        // set the target allocations
        uint256[] memory targetAllocations = new uint256[](
            numBeneficiaries < TARGET_BENEFICIARIES_LENGTH ? TARGET_BENEFICIARIES_LENGTH : numBeneficiaries
        );
        targetAllocations[0] = 0; // smart treasury
        targetAllocations[1] = 70000; // spigot
        targetAllocations[2] = 10000; // rebalancer
        targetAllocations[3] = 20000; // staking

        if (numBeneficiaries < TARGET_BENEFICIARIES_LENGTH) {
            // add target beneficiaries if the existing beneficiaries list has a length less than `TARGET_BENEFICIARIES_LENGTH`
            _fillBeneficiaries(numBeneficiaries, targetBeneficiaries);

            // fetch the updated list of beneficiaries from the fee collector
            existingBeneficiaries = iFeeCollector.getBeneficiaries();
        } else if (numBeneficiaries > TARGET_BENEFICIARIES_LENGTH) {
            // zero-out any additional beneficiary allocations (therefore no need to worry about removing unused addresses)
            targetAllocations[4] = 0;
        }



        /// @dev We know that the spigot is not a pre-existing beneficiary, so we can simply add it without checking for a duplicate
        iFeeCollector.replaceBeneficiaryAt(1, spigot, targetAllocations);
        existingBeneficiaries[1] = spigot;
        emit ReplacedBeneficiary(1, spigot, targetAllocations[1]);

        /// @dev we don't care about the value of the targetAllocations allocations  just yet as we set the correct
        ///      values at the final step
        /// @dev only care that they add up to 100000 so as not to revert
        for (uint256 i = 2; i < TARGET_BENEFICIARIES_LENGTH; ) {
            if (existingBeneficiaries[i] != targetBeneficiaries[i]) {
                existingBeneficiaries = _findAndReplace(
                    existingBeneficiaries,
                    targetBeneficiaries[i],
                    targetAllocations,
                    i
                );
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Adds beneficiaries until the list length is equal to `TARGET_BENEFICIARIES_LENGTH`.
    /// @dev    This function is only invoked if the existing list of beneficiaries on the external FeeCollector has a
    ///         length shorter than `TARGET_BENEFICIARIES_LENGTH`. In order to add new beneficiaries, the length
    ///         of the corresponding allocations array needs to match.  This results im both the beneficiaries and allocations
    ///         arrays on the external FeeCollector being updated for each additional beneficiary.
    /// @dev    The allocation values are temporary, as the final values will be set after this function has been invoked.
    /// @dev    A new temporary allocations array needs to be created for each benecificiary that's added, as the length
    ///         length of the allocations array needs to match the length of the beneficiaries array
    /// @param  numBeneficiaries The number of existing beneficiaries
    /// @param  _targetBeneficiaries The list of required beneficiaries
    function _fillBeneficiaries(uint256 numBeneficiaries, address[] memory _targetBeneficiaries) internal {
        for (uint256 i = numBeneficiaries; i < TARGET_BENEFICIARIES_LENGTH; ) {
            uint256[] memory tempAllocations = new uint256[](i + 1);
            tempAllocations[0] = 100000; // 100%

            uint256 tempAllocationsLength = tempAllocations.length;

            // fill the temp allocations array, which we need in order to add a beneficiary
            for (uint256 j = 1; j < tempAllocationsLength; ) {
                tempAllocations[j] = 0;
                unchecked {
                    ++j;
                }
            }

            iFeeCollector.addBeneficiaryAddress(_targetBeneficiaries[i], tempAllocations);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Adds an address as a beneficiary and sets the corresponding allocation
    /// @dev    If the array contains a duplicate address, the duplicate is replaced with a temporary address
    ///         that will ultimately be replaced.
    /// @param  _existingBeneficiaries The list of existing beneficiaries
    /// @param  target The address to add as a beneficiary
    /// @param  newAllocations The updated allocations array containing the allocation for the `target`
    /// @param  targetIndex The position in the beneficiaries array to update
    /// @return The updated list of existing beneficiaries containing the `target` address
    function _findAndReplace(
        address[] memory _existingBeneficiaries,
        address target,
        uint256[] memory newAllocations,
        uint256 targetIndex
    ) internal returns (address[] memory) {
        (bool hasDuplicate, uint256 duplicateIdx) = _hasDuplicate(_existingBeneficiaries, target);
        if (hasDuplicate && duplicateIdx != targetIndex) {
            address temp = address(uint160(targetIndex * block.timestamp));
            iFeeCollector.replaceBeneficiaryAt(duplicateIdx, temp, newAllocations);
            _existingBeneficiaries[duplicateIdx] = temp;
            emit ReplacedBeneficiary(duplicateIdx, temp, 0);
        }
        iFeeCollector.replaceBeneficiaryAt(targetIndex, target, newAllocations);
        _existingBeneficiaries[targetIndex] = target;
        emit ReplacedBeneficiary(targetIndex, target, newAllocations[targetIndex]);
        return _existingBeneficiaries;
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
        for (uint256 i; i < beneficiaries.length; ) {
            if (beneficiaries[i] == addressToCheck) return (true, i);
            unchecked {
                ++i;
            }
        }
        return (false, 0);
    }
}
