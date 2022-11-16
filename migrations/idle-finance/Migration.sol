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

    function replaceBeneficiaryAt(
        uint256 _index,
        address _newBeneficiary,
        uint256[] calldata _newAllocation
    ) external;

    function deposit(
        bool[] memory _depositTokensEnabled,
        uint256[] memory _minTokenOut,
        uint256 _minPoolAmountOut
    ) external;

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
    address private constant idleFeeCollector = 0xBecC659Bfc6EDcA552fa1A67451cC6b38a0108E4;

    address private constant idleTimelock = 0xD6dABBc2b275114a2366555d6C481EF08FDC2556;

    address private constant idleTreasuryLeagueMultisig = 0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814;

    address private constant idleSmartTreasury = 0x859E4D219E83204a2ea389DAc11048CC880B6AA8; // multisig

    address private constant idleFeeTreausry = 0x69a62C24F16d4914a48919613e8eE330641Bcb94;

    address private constant idleRebalancer = 0xB3C8e5534F0063545CBbb7Ce86854Bf42dB8872B;

    address private constant idleStakingFeeSwapper = 0x1594375Eee2481Ca5C1d2F6cE15034816794E8a3;

    // migration
    address public immutable spigot;

    address public immutable escrow;

    address public immutable securedLine;

    bool migrationSucceeded;

    uint256 deployedAt;

    uint256 private constant cooldownPeriod = 30 days;

    /*//////////////////////////////////////////////////////////////
                            E V E N T S
    //////////////////////////////////////////////////////////////*/

    event MigrationSucceeded();

    event MigrationDeployed(address indexed spigot, address indexed escrow, address indexed line);

    event ReplacedBeneficiary(uint256 index, address contractAddress, uint256 allocation);

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
            idleTreasuryLeagueMultisig, // treasury - Treasury Multisig
            idleTreasuryLeagueMultisig // operator - Treasury Multisig
        );
        iSpigot = ISpigot(spigot);

        // deploy escrow
        escrow = ILineFactory(lineFactory_).deployEscrow(
            0, // min credit ratio
            address(this), // owner
            idleTreasuryLeagueMultisig // borrower
        );

        ILineFactory.CoreLineParams memory coreParams = ILineFactory.CoreLineParams({
            borrower: idleTreasuryLeagueMultisig,
            ttl: ttl_,
            cratio: 0, //uint32(creditRatio),
            revenueSplit: 100 //uint8(revenueSplit)
        });

        // deoloy the line of credit
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
            bytes4(0), // no claim fn, therefore just a push payment
            _getSelector("replaceAdmin(address)") // transferOwnerFn // gets transferred to operator
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

        // require spigot is admin on fee collector
        if (!iFeeCollector.isAddressAdmin(spigot)) {
            revert SpigotNotAdmin();
        }

        emit MigrationSucceeded();
    }

    /*//////////////////////////////////////////////////////
                       R E D U N D A N C Y                  
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

        iFeeCollector.replaceAdmin(idleTimelock);
        if (!iFeeCollector.isAddressAdmin(idleTimelock)) {
            revert ReplaceAdminFailed();
        }

        iSpigot.updateOwner(idleTreasuryLeagueMultisig);
        if (iSpigot.owner() != idleTreasuryLeagueMultisig) {
            revert SpigotOwnershipTransferFailed();
        }
    }

    /*//////////////////////////////////////////////////////
                        I N T E R N A L                    
    //////////////////////////////////////////////////////*/

    // TODO: this could fail if an existing benficiary is at the wrong index and it tries to add a duplicate
    /// @dev This function is a safeguard against the protocol switching beneficiaries
    ///      or changing allocations between the deployment of the migration contract and the migration
    function _setBeneficiariesAndAllocations() internal {
        /*
            note: this is for reference, remove before deploying 

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
        address[] memory existingBeneficiaries = iFeeCollector.getBeneficiaries();

        uint256[] memory newAllocations = new uint256[](existingBeneficiaries.length);

        newAllocations[0] = 0; // smart treasury
        newAllocations[1] = 70000; // spigot
        newAllocations[2] = 10000; // rebalancer
        newAllocations[3] = 20000; // staking

        // zero-out any additional beneficiary allocations
        for (uint256 i = 4; i < existingBeneficiaries.length; ) {
            newAllocations[i] = 0;
            unchecked {
                ++i;
            }
        }

        // check if index 0 is smart treasury
        if (existingBeneficiaries[0] != idleSmartTreasury) {
            iFeeCollector.setSmartTreasuryAddress(idleSmartTreasury);
            emit ReplacedBeneficiary(0, idleSmartTreasury, newAllocations[0]);
        }

        // add the spigot as a beneficiary
        iFeeCollector.replaceBeneficiaryAt(1, spigot, newAllocations);
        emit ReplacedBeneficiary(1, spigot, newAllocations[1]);

        // replace the rebalancer if necessary
        if (existingBeneficiaries[2] != idleRebalancer) {
            iFeeCollector.replaceBeneficiaryAt(2, idleRebalancer, newAllocations);
            emit ReplacedBeneficiary(2, idleRebalancer, newAllocations[2]);
        }

        // replace the staking fee swapper if necessary
        if (existingBeneficiaries[3] != idleStakingFeeSwapper) {
            iFeeCollector.replaceBeneficiaryAt(3, idleStakingFeeSwapper, newAllocations);
            emit ReplacedBeneficiary(3, idleRebalancer, newAllocations[3]);
        }
    }

    /*//////////////////////////////////////////////////////
                            U T I L S                    
    //////////////////////////////////////////////////////*/

    /// @notice Gets a function selector from its signature
    /// @dev    The signature includes only the argument types, and omits the names
    /// @param  signature The function's signature
    /// @return The 4-byte function selector of the signature provided in `signature`
    function _getSelector(string memory signature) internal pure returns (bytes4) {
        return bytes4(keccak256(bytes(signature)));
    }
}
