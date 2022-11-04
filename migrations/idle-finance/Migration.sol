// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {ISpigot} from "Line-of-Credit/interfaces/ISpigot.sol";
import {Spigot} from "Line-of-Credit/modules/spigot/Spigot.sol";
import {SecuredLine} from "Line-of-Credit/modules/credit/SecuredLine.sol";
import {ISecuredLine} from "Line-of-Credit/interfaces/ISecuredLine.sol";
import {ILineOfCredit} from "Line-of-Credit/interfaces/ILineOfCredit.sol";
import {ISpigot} from "Line-of-Credit/interfaces/ISpigot.sol";
import {LineLib} from "Line-of-Credit/utils/LineLib.sol";
import {IEscrow} from "Line-of-Credit/interfaces/IEscrow.sol";
import {ISpigotedLine} from "Line-of-Credit/interfaces/ISpigotedLine.sol";
import {IModuleFactory} from "Line-of-Credit/interfaces/IModuleFactory.sol";
import {SpigotedLine} from "Line-of-Credit/modules/credit/SpigotedLine.sol";
import {ModuleFactory} from "Line-of-Credit/modules/factories/ModuleFactory.sol";
import {LineFactory} from "Line-of-Credit/modules/factories/LineFactory.sol";
import {ILineFactory} from "Line-of-Credit/interfaces/ILineFactory.sol";

// import {FeeCollector} from "idle-smart-treasury/FeeCollector.sol";

interface IFeeCollector {
    function hasRole(bytes32 role, address account) external returns (bool);

    function isAddressAdmin(address _address) external view returns (bool);

    function replaceAdmin(address _newAdmin) external;

    function replaceBeneficiaryAt(
        uint256 _index,
        address _newBeneficiary,
        uint256[] calldata _newAllocation
    ) external;

    function addAddressToWhiteList(address _addressToAdd) external;

    function getBeneficiaries() external view returns (address[] memory);

    function setSmartTreasuryAddress(address _smartTreasuryAddress) external;
}

contract IdleMigration {
    // interfaces
    IFeeCollector iFeeCollector;
    ISpigot iSpigot;

    // admin
    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
    address private immutable owner;

    // trusted 3rd-parties
    address private constant zeroExSwapTarget =
        0xDef1C0ded9bec7F1a1670819833240f027b25EfF;

    // debtdao
    address private immutable debtDaoDeployer;

    // Idle
    address private immutable feeCollector;
    address private immutable idleTimelock;

    // TODO: confirm these
    address private constant idleSmartTreasury =
        0x859E4D219E83204a2ea389DAc11048CC880B6AA8;
    address private constant idleFeeTreausry =
        0x69a62C24F16d4914a48919613e8eE330641Bcb94;
    address private constant idleRebalancer =
        0xB3C8e5534F0063545CBbb7Ce86854Bf42dB8872B;
    address private constant idleStakingFeeSwapper =
        0x1594375Eee2481Ca5C1d2F6cE15034816794E8a3;

    // migration
    address public immutable spigot;
    address public immutable escrow;
    address public immutable securedLine;

    bool migrationSucceeded;
    uint256 deployedAt;

    event Status(LineLib.STATUS s);

    event MigrationComplete();
    event ReplacedBeneficiary(
        uint256 index,
        address contractAddress,
        uint256 allocation
    );

    event log_named_uint(string key, uint256 val);
    event log_named_string(string key, string val);
    event log_named_address(string key, address val);

    error NotFeeCollectorAdmin();
    error MigrationFailed();

    // TODO: if the migration contract is still the owner of the spigot and escrow, and not owned by line
    // should be transferred back
    // TODO: deadman's switch: return ownership to timelock if migration fails, transfer the spigot and escrow to multisig
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
        debtDaoDeployer = debtDaoDeployer_;
        feeCollector = revenueContract_;
        idleTimelock = timelock_;
        deployedAt = block.timestamp;

        iFeeCollector = IFeeCollector(revenueContract_);

        // deploy spigot
        spigot = IModuleFactory(moduleFactory_).deploySpigot(
            address(this), // owner - debtdaoMultisig // TODO: change this to multisig
            idleTreasuryMultisig_, // treasury - Treasury Multisig
            idleTreasuryMultisig_ // operator - Treasury Multisig
        );

        iSpigot = ISpigot(spigot);

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

        securedLine = ILineFactory(lineFactory_).deploySecuredLineWithModules(
            coreParams,
            spigot,
            escrow
        );
    }

    function migrate() external onlyAuthorized {
        if (!iFeeCollector.isAddressAdmin(address(this))) {
            revert NotFeeCollectorAdmin();
        }
        require(!migrationSucceeded, "Migration is complete");
        migrationSucceeded = true;

        // add the revenue contract
        // programs the function into the spigot which gets called when remove Spigot
        // the operator is the entity to whom the spigot is returned when loan is repaid
        /// @dev abi.encodeWithSignature/selector gives the full calldata, not the fn selector
        ISpigot.Setting memory spigotSettings = ISpigot.Setting(
            100, // 100% to owner
            _getSelector("deposit(bool[],uint256[],uint256)"), // claim fn // TODO: change to bytes("") so its only a push payment
            _getSelector("replaceAdmin(address)") // transferOwnerFn // gets transferred to operator
        );

        // add a revenue stream
        iSpigot.addSpigot(feeCollector, spigotSettings);

        // we need to whitelist the spigot in order for it to call `deposit` via
        // it's own `claimRevenue` fn
        iFeeCollector.addAddressToWhiteList(spigot);

        // TODO: idle finance is in charge of making trades (they can call deposit as operator)
        // TODO: we probably don't want to give them access to this
        // add address to whitelist fn as a function the operator can call
        bytes4 addAddressSelector = _getSelector(
            "addAddressToWhiteList(address)"
        );
        iSpigot.updateWhitelistedFunction(
            addAddressSelector, // selector
            true
        );

        require(
            iSpigot.isWhitelisted(addAddressSelector),
            "Migration: add address not whitelisted"
        );

        // transfer ownership of spigot and escrow to line
        // TODO: test these
        iSpigot.updateOwner(securedLine);
        IEscrow(escrow).updateLine(securedLine);

        require(
            iSpigot.owner() == securedLine,
            "Migration: Spigot owner transfer failed"
        );
        require(
            IEscrow(escrow).line() == securedLine,
            "Migration: Escrow line transfer failed"
        );

        LineLib.STATUS status = ILineOfCredit(securedLine).init();

        require(status == LineLib.STATUS.ACTIVE, "Migration: Line not active");

        _setBeneficiariesAndAllocations();

        // transfer ownership (admin priviliges) to spigot
        iFeeCollector.replaceAdmin(spigot);

        // require spigot is admin on fee collector
        require(
            iFeeCollector.isAddressAdmin(spigot),
            "Migration: Spigot is not the feeCollector admin"
        );

        emit MigrationComplete();
    }

    // TODO: test this
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
        address[] memory existingBeneficiaries = iFeeCollector
            .getBeneficiaries();

        uint256[] memory newAllocations = new uint256[](
            existingBeneficiaries.length
        );

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
            iFeeCollector.replaceBeneficiaryAt(
                2,
                idleRebalancer,
                newAllocations
            );
            emit ReplacedBeneficiary(2, idleRebalancer, newAllocations[2]);
        }

        // replace the staking fee swapper if necessary
        if (existingBeneficiaries[3] != idleStakingFeeSwapper) {
            iFeeCollector.replaceBeneficiaryAt(
                3,
                idleStakingFeeSwapper,
                newAllocations
            );
            emit ReplacedBeneficiary(3, idleRebalancer, newAllocations[3]);
        }
    }

    function recoverAdmin(address newAdmin_) external {
        require(!migrationSucceeded, "Migration has not been completed");
        require(
            block.timestamp > deployedAt + 30 days,
            "Cooldown still active"
        );
        iFeeCollector.replaceAdmin(idleTimelock);
    }

    // ===================== Internal

    function _getSelector(string memory _func) internal pure returns (bytes4) {
        return bytes4(keccak256(bytes(_func))); //TODO: use abi encode with selector
    }

    // ===================== Modifiers

    /// @dev    should only be callable by the timelock contract
    modifier onlyAuthorized() {
        // TODO: improve error messages
        require(msg.sender == idleTimelock, "Migration: Unauthorized user");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Migration: Not owner");
        _;
    }
}
