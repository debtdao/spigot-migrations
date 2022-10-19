// File: contracts/interfaces/IFeeCollector.sol

pragma solidity >=0.6.0 <=0.7.5;

interface IFeeCollector {
    function deposit(
        bool[] calldata _depositTokensEnabled,
        uint256[] calldata _minTokenOut,
        uint256 _minPoolAmountOut
    ) external; // called by whitelisted address

    function setSplitAllocation(uint256[] calldata _allocations) external; // allocation of fees sent SmartTreasury vs FeeTreasury

    // function setFeeTreasuryAddress(address _feeTreasuryAddress) external; // called by admin

    function addBeneficiaryAddress(
        address _newBeneficiary,
        uint256[] calldata _newAllocation
    ) external;

    function removeBeneficiaryAt(
        uint256 _index,
        uint256[] calldata _newAllocation
    ) external;

    function replaceBeneficiaryAt(
        uint256 _index,
        address _newBeneficiary,
        uint256[] calldata _newAllocation
    ) external;

    function setSmartTreasuryAddress(address _smartTreasuryAddress) external; // If for any reason the pool needs to be migrated, call this function. Called by admin

    function addAddressToWhiteList(address _addressToAdd) external; // Whitelist address. Called by admin

    function removeAddressFromWhiteList(address _addressToRemove) external; // Remove from whitelist. Called by admin

    function registerTokenToDepositList(address _tokenAddress) external; // Register a token which can converted to ETH and deposited to smart treasury. Called by admin

    function removeTokenFromDepositList(address _tokenAddress) external; // Unregister a token. Called by admin

    // withdraw arbitrary token to address. Called by admin
    function withdraw(
        address _token,
        address _toAddress,
        uint256 _amount
    ) external;

    // exchange liquidity token for underlying token and withdraw to _toAddress
    function withdrawUnderlying(
        address _toAddress,
        uint256 _amount,
        uint256[] calldata minTokenOut
    ) external;

    function replaceAdmin(address _newAdmin) external; // called by admin
}

// File: contracts/interfaces/BalancerInterface.sol

pragma solidity =0.6.8;
pragma experimental ABIEncoderV2;

interface BPool {
    event LOG_SWAP(
        address indexed caller,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 tokenAmountIn,
        uint256 tokenAmountOut
    );

    event LOG_JOIN(
        address indexed caller,
        address indexed tokenIn,
        uint256 tokenAmountIn
    );

    event LOG_EXIT(
        address indexed caller,
        address indexed tokenOut,
        uint256 tokenAmountOut
    );

    event LOG_CALL(
        bytes4 indexed sig,
        address indexed caller,
        bytes data
    ) anonymous;

    function isPublicSwap() external view returns (bool);

    function isFinalized() external view returns (bool);

    function isBound(address t) external view returns (bool);

    function getNumTokens() external view returns (uint256);

    function getCurrentTokens() external view returns (address[] memory tokens);

    function getFinalTokens() external view returns (address[] memory tokens);

    function getDenormalizedWeight(address token)
        external
        view
        returns (uint256);

    function getTotalDenormalizedWeight() external view returns (uint256);

    function getNormalizedWeight(address token) external view returns (uint256);

    function getBalance(address token) external view returns (uint256);

    function getSwapFee() external view returns (uint256);

    function getController() external view returns (address);

    function setSwapFee(uint256 swapFee) external;

    function setController(address manager) external;

    function setPublicSwap(bool public_) external;

    function finalize() external;

    function bind(
        address token,
        uint256 balance,
        uint256 denorm
    ) external;

    function unbind(address token) external;

    function gulp(address token) external;

    function getSpotPrice(address tokenIn, address tokenOut)
        external
        view
        returns (uint256 spotPrice);

    function getSpotPriceSansFee(address tokenIn, address tokenOut)
        external
        view
        returns (uint256 spotPrice);

    function joinPool(uint256 poolAmountOut, uint256[] calldata maxAmountsIn)
        external;

    function exitPool(uint256 poolAmountIn, uint256[] calldata minAmountsOut)
        external;

    function swapExactAmountIn(
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 maxPrice
    ) external returns (uint256 tokenAmountOut, uint256 spotPriceAfter);

    function swapExactAmountOut(
        address tokenIn,
        uint256 maxAmountIn,
        address tokenOut,
        uint256 tokenAmountOut,
        uint256 maxPrice
    ) external returns (uint256 tokenAmountIn, uint256 spotPriceAfter);

    function joinswapExternAmountIn(
        address tokenIn,
        uint256 tokenAmountIn,
        uint256 minPoolAmountOut
    ) external returns (uint256 poolAmountOut);

    function joinswapPoolAmountOut(
        address tokenIn,
        uint256 poolAmountOut,
        uint256 maxAmountIn
    ) external returns (uint256 tokenAmountIn);

    function exitswapPoolAmountIn(
        address tokenOut,
        uint256 poolAmountIn,
        uint256 minAmountOut
    ) external returns (uint256 tokenAmountOut);

    function exitswapExternAmountOut(
        address tokenOut,
        uint256 tokenAmountOut,
        uint256 maxPoolAmountIn
    ) external returns (uint256 poolAmountIn);

    function totalSupply() external view returns (uint256);

    function balanceOf(address whom) external view returns (uint256);

    function allowance(address src, address dst)
        external
        view
        returns (uint256);

    function approve(address dst, uint256 amt) external returns (bool);

    function transfer(address dst, uint256 amt) external returns (bool);

    function transferFrom(
        address src,
        address dst,
        uint256 amt
    ) external returns (bool);
}

interface ConfigurableRightsPool {
    event LogCall(
        bytes4 indexed sig,
        address indexed caller,
        bytes data
    ) anonymous;

    event LogJoin(
        address indexed caller,
        address indexed tokenIn,
        uint256 tokenAmountIn
    );

    event LogExit(
        address indexed caller,
        address indexed tokenOut,
        uint256 tokenAmountOut
    );

    event CapChanged(address indexed caller, uint256 oldCap, uint256 newCap);

    event NewTokenCommitted(
        address indexed token,
        address indexed pool,
        address indexed caller
    );

    function createPool(
        uint256 initialSupply
        // uint minimumWeightChangeBlockPeriodParam,
        // uint addTokenTimeLockInBlocksParam
    ) external;

    function createPool(
        uint256 initialSupply,
        uint256 minimumWeightChangeBlockPeriodParam,
        uint256 addTokenTimeLockInBlocksParam
    ) external;

    function updateWeightsGradually(
        uint256[] calldata newWeights,
        uint256 startBlock,
        uint256 endBlock
    ) external;

    function joinswapExternAmountIn(
        address tokenIn,
        uint256 tokenAmountIn,
        uint256 minPoolAmountOut
    ) external;

    function whitelistLiquidityProvider(address provider) external;

    function removeWhitelistedLiquidityProvider(address provider) external;

    function canProvideLiquidity(address provider) external returns (bool);

    function getController() external view returns (address);

    function setController(address newOwner) external;

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function balanceOf(address account) external returns (uint256);

    function totalSupply() external returns (uint256);

    function bPool() external view returns (BPool);

    function exitPool(uint256 poolAmountIn, uint256[] calldata minAmountsOut)
        external;
}

interface IBFactory {
    event LOG_NEW_POOL(address indexed caller, address indexed pool);

    event LOG_BLABS(address indexed caller, address indexed blabs);

    function isBPool(address b) external view returns (bool);

    function newBPool() external returns (BPool);
}

interface ICRPFactory {
    event LogNewCrp(address indexed caller, address indexed pool);

    struct PoolParams {
        // Balancer Pool Token (representing shares of the pool)
        string poolTokenSymbol;
        string poolTokenName;
        // Tokens inside the Pool
        address[] constituentTokens;
        uint256[] tokenBalances;
        uint256[] tokenWeights;
        uint256 swapFee;
    }

    struct Rights {
        bool canPauseSwapping;
        bool canChangeSwapFee;
        bool canChangeWeights;
        bool canAddRemoveTokens;
        bool canWhitelistLPs;
        bool canChangeCap;
    }

    function newCrp(
        address factoryAddress,
        PoolParams calldata poolParams,
        Rights calldata rights
    ) external returns (ConfigurableRightsPool);
}

// File: contracts/FeeCollector.sol

pragma solidity =0.6.8;

/**
@title Idle finance Fee collector
@author Asaf Silman
@notice Receives fees from idle strategy tokens and routes to fee treasury and smart treasury
 */
contract FeeCollector is IFeeCollector, AccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IUniswapV2Router02 private constant uniswapRouterV2 =
        IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    address private immutable weth;

    // Need to use openzeppelin enumerableset
    EnumerableSet.AddressSet private depositTokens;

    uint256[] private allocations; // 100000 = 100%. allocation sent to beneficiaries
    address[] private beneficiaries; // Who are the beneficiaries of the fees generated from IDLE. The first beneficiary is always going to be the smart treasury

    uint128 public constant MAX_BENEFICIARIES = 5;
    uint128 public constant MIN_BENEFICIARIES = 2;
    uint256 public constant FULL_ALLOC = 100000;

    uint256 public constant MAX_NUM_FEE_TOKENS = 15; // Cap max tokens to 15
    bytes32 public constant WHITELISTED = keccak256("WHITELISTED_ROLE");

    modifier smartTreasurySet() {
        require(beneficiaries[0] != address(0), "Smart Treasury not set");
        _;
    }

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Unauthorised");
        _;
    }

    modifier onlyWhitelisted() {
        require(hasRole(WHITELISTED, msg.sender), "Unauthorised");
        _;
    }

    /**
  @author Asaf Silman
  @notice Initialise the FeeCollector contract.
  @dev Sets the smartTreasury, weth address, uniswap router, and fee split allocations.
  @dev Also initialises the sender as admin, and whitelists for calling `deposit()`
  @dev At deploy time the smart treasury will not have been deployed yet.
       setSmartTreasuryAddress should be called after the treasury has been deployed.
  @param _weth The wrapped ethereum address.
  @param _feeTreasuryAddress The address of idle's fee treasury.
  @param _idleRebalancer Idle rebalancer address
  @param _multisig The multisig account to transfer ownership to after contract initialised
  @param _initialDepositTokens The initial tokens to register with the fee deposit
   */
    constructor(
        address _weth,
        address _feeTreasuryAddress,
        address _idleRebalancer,
        address _multisig,
        address[] memory _initialDepositTokens
    ) public {
        require(_weth != address(0), "WETH cannot be the 0 address");
        require(
            _feeTreasuryAddress != address(0),
            "Fee Treasury cannot be 0 address"
        );
        require(
            _idleRebalancer != address(0),
            "Rebalancer cannot be 0 address"
        );
        require(_multisig != address(0), "Multisig cannot be 0 address");

        require(_initialDepositTokens.length <= MAX_NUM_FEE_TOKENS);

        _setupRole(DEFAULT_ADMIN_ROLE, _multisig); // setup multisig as admin
        _setupRole(WHITELISTED, _multisig); // setup multisig as whitelisted address
        _setupRole(WHITELISTED, _idleRebalancer); // setup multisig as whitelisted address

        // configure weth address and ERC20 interface
        weth = _weth;

        allocations = new uint256[](3); // setup fee split ratio
        allocations[0] = 80000;
        allocations[1] = 15000;
        allocations[2] = 5000;

        beneficiaries = new address[](3); // setup beneficiaries
        beneficiaries[1] = _feeTreasuryAddress; // setup fee treasury address
        beneficiaries[2] = _idleRebalancer; // setup fee treasury address

        address _depositToken;
        for (uint256 index = 0; index < _initialDepositTokens.length; index++) {
            _depositToken = _initialDepositTokens[index];
            require(_depositToken != address(0), "Token cannot be 0 address");
            require(_depositToken != _weth, "WETH not supported"); // There is no WETH -> WETH pool in uniswap
            require(
                depositTokens.contains(_depositToken) == false,
                "Already exists"
            );

            IERC20(_depositToken).safeIncreaseAllowance(
                address(uniswapRouterV2),
                type(uint256).max
            ); // max approval
            depositTokens.add(_depositToken);
        }
    }

    /**
  @author Asaf Silman
  @notice Converts all registered fee tokens to WETH and deposits to
          fee treasury and smart treasury based on split allocations.
  @dev The fees are swaped using Uniswap simple route. E.g. Token -> WETH.
   */
    function deposit(
        bool[] memory _depositTokensEnabled,
        uint256[] memory _minTokenOut,
        uint256 _minPoolAmountOut
    ) public override smartTreasurySet onlyWhitelisted {
        _deposit(_depositTokensEnabled, _minTokenOut, _minPoolAmountOut);
    }

    /**
  @author Asaf Silman
  @dev implements deposit()
   */
    function _deposit(
        bool[] memory _depositTokensEnabled,
        uint256[] memory _minTokenOut,
        uint256 _minPoolAmountOut
    ) internal {
        uint256 counter = depositTokens.length();
        require(_depositTokensEnabled.length == counter, "Invalid length");
        require(_minTokenOut.length == counter, "Invalid length");

        uint256 _currentBalance;
        IERC20 _tokenInterface;

        uint256 wethBalance;

        address[] memory path = new address[](2);
        path[1] = weth; // output will always be weth

        // iterate through all registered deposit tokens
        for (uint256 index = 0; index < counter; index++) {
            if (_depositTokensEnabled[index] == false) {
                continue;
            }

            _tokenInterface = IERC20(depositTokens.at(index));

            _currentBalance = _tokenInterface.balanceOf(address(this));

            // Only swap if balance > 0
            if (_currentBalance > 0) {
                // create simple route; token->WETH

                path[0] = address(_tokenInterface);

                // swap token
                uniswapRouterV2
                    .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                        _currentBalance,
                        _minTokenOut[index],
                        path,
                        address(this),
                        block.timestamp.add(1800)
                    );
            }
        }

        // deposit all swapped WETH + the already present weth balance
        // to beneficiaries
        // the beneficiary at index 0 is the smart treasury
        wethBalance = IERC20(weth).balanceOf(address(this));
        if (wethBalance > 0) {
            // feeBalances[0] is fee sent to smartTreasury
            uint256[] memory feeBalances = _amountsFromAllocations(
                allocations,
                wethBalance
            );
            uint256 smartTreasuryFee = feeBalances[0];

            if (wethBalance.sub(smartTreasuryFee) > 0) {
                // NOTE: allocation starts at 1, NOT 0, since 0 is reserved for smart treasury
                for (
                    uint256 a_index = 1;
                    a_index < allocations.length;
                    a_index++
                ) {
                    IERC20(weth).safeTransfer(
                        beneficiaries[a_index],
                        feeBalances[a_index]
                    );
                }
            }

            if (smartTreasuryFee > 0) {
                ConfigurableRightsPool crp = ConfigurableRightsPool(
                    beneficiaries[0]
                ); // the smart treasury is at index 0
                crp.joinswapExternAmountIn(
                    weth,
                    smartTreasuryFee,
                    _minPoolAmountOut
                );
            }
        }
    }

    /**
  @author Asaf Silman
  @notice Sets the split allocations of fees to send to fee beneficiaries
  @dev The split allocations must sum to 100000.
  @dev Before the split allocation is updated internally a call to `deposit()` is made
       such that all fee accrued using the previous allocations.
  @dev smartTreasury must be set for this to be called.
  @param _allocations The updated split ratio.
   */
    function setSplitAllocation(uint256[] calldata _allocations)
        external
        override
        smartTreasurySet
        onlyAdmin
    {
        _depositAllTokens();

        _setSplitAllocation(_allocations);
    }

    /**
  @author Asaf Silman
  @notice Internal function to sets the split allocations of fees to send to fee beneficiaries
  @dev The split allocations must sum to 100000.
  @dev smartTreasury must be set for this to be called.
  @param _allocations The updated split ratio.
   */
    function _setSplitAllocation(uint256[] memory _allocations) internal {
        require(_allocations.length == beneficiaries.length, "Invalid length");

        uint256 sum = 0;
        for (uint256 i = 0; i < _allocations.length; i++) {
            sum = sum.add(_allocations[i]);
        }

        require(sum == FULL_ALLOC, "Ratio does not equal 100000");

        allocations = _allocations;
    }

    /**
  @author Andrea @ idle.finance
  @notice Helper function to deposit all tokens
   */
    function _depositAllTokens() internal {
        uint256 numTokens = depositTokens.length();
        bool[] memory depositTokensEnabled = new bool[](numTokens);
        uint256[] memory minTokenOut = new uint256[](numTokens);

        for (uint256 i = 0; i < numTokens; i++) {
            depositTokensEnabled[i] = true;
            minTokenOut[i] = 1;
        }

        _deposit(depositTokensEnabled, minTokenOut, 1);
    }

    /**
  @author Asaf Silman
  @notice Adds an address as a beneficiary to the idle fees
  @dev The new beneficiary will be pushed to the end of the beneficiaries array.
  The new allocations must include the new beneficiary
  @dev There is a maximum of 5 beneficiaries which can be registered with the fee collector
  @param _newBeneficiary The new beneficiary to add
  @param _newAllocation The new allocation of fees including the new beneficiary
   */
    function addBeneficiaryAddress(
        address _newBeneficiary,
        uint256[] calldata _newAllocation
    ) external override smartTreasurySet onlyAdmin {
        require(beneficiaries.length < MAX_BENEFICIARIES, "Max beneficiaries");
        require(
            _newBeneficiary != address(0),
            "beneficiary cannot be 0 address"
        );

        for (uint256 i = 0; i < beneficiaries.length; i++) {
            require(
                beneficiaries[i] != _newBeneficiary,
                "Duplicate beneficiary"
            );
        }

        _depositAllTokens();

        beneficiaries.push(_newBeneficiary);

        _setSplitAllocation(_newAllocation);
    }

    /**
  @author Asaf Silman
  @notice removes a beneficiary at a given index.
  @notice WARNING: when using this method be very careful to note the new allocations
  The beneficiary at the LAST index, will be replaced with the beneficiary at `_index`.
  The new allocations need to reflect this updated array.

  eg.
  if beneficiaries = [a, b, c, d]
  and removeBeneficiaryAt(1, [...]) is called

  the final beneficiaries array will be
  [a, d, c]
  `_newAllocations` should be based off of this final array.

  @dev Cannot remove beneficiary past MIN_BENEFICIARIES. set to 2
  @dev Cannot replace the smart treasury beneficiary at index 0
  @param _index The index of the beneficiary to remove
  @param _newAllocation The new allocation of fees removing the beneficiary. NOTE !! The order of beneficiaries will change !!
   */
    function removeBeneficiaryAt(
        uint256 _index,
        uint256[] calldata _newAllocation
    ) external override smartTreasurySet onlyAdmin {
        require(_index >= 1, "Invalid beneficiary to remove");
        require(_index < beneficiaries.length, "Out of range");
        require(beneficiaries.length > MIN_BENEFICIARIES, "Min beneficiaries");

        _depositAllTokens();

        // replace beneficiary with index with final beneficiary, and call pop
        beneficiaries[_index] = beneficiaries[beneficiaries.length - 1];
        beneficiaries.pop();

        // NOTE THE ORDER OF ALLOCATIONS
        _setSplitAllocation(_newAllocation);
    }

    /**
  @author Asaf Silman
  @notice replaces a beneficiary at a given index with a new one
  @notice a new allocation must be passed for this method
  @dev Cannot replace the smart treasury beneficiary at index 0
  @param _index The index of the beneficiary to replace
  @param _newBeneficiary The new beneficiary address
  @param _newAllocation The new allocation of fees
  */
    function replaceBeneficiaryAt(
        uint256 _index,
        address _newBeneficiary,
        uint256[] calldata _newAllocation
    ) external override smartTreasurySet onlyAdmin {
        require(_index >= 1, "Invalid beneficiary to remove");
        require(
            _newBeneficiary != address(0),
            "Beneficiary cannot be 0 address"
        );

        for (uint256 i = 0; i < beneficiaries.length; i++) {
            require(
                beneficiaries[i] != _newBeneficiary,
                "Duplicate beneficiary"
            );
        }

        _depositAllTokens();

        beneficiaries[_index] = _newBeneficiary;

        _setSplitAllocation(_newAllocation);
    }

    /**
  @author Asaf Silman
  @notice Sets the smart treasury address.
  @dev This needs to be called atleast once to properly initialise the contract
  @dev Sets maximum approval for WETH to the new smart Treasury
  @dev The smart treasury address cannot be the 0 address.
  @param _smartTreasuryAddress The new smart treasury address
   */
    function setSmartTreasuryAddress(address _smartTreasuryAddress)
        external
        override
        onlyAdmin
    {
        require(
            _smartTreasuryAddress != address(0),
            "Smart treasury cannot be 0 address"
        );

        // When contract is initialised, the smart treasury address is not yet set
        // Only call change allowance to 0 if previous smartTreasury was not the 0 address.
        if (beneficiaries[0] != address(0)) {
            IERC20(weth).safeApprove(beneficiaries[0], 0); // set approval for previous fee address to 0
        }
        // max approval for new smartTreasuryAddress
        IERC20(weth).safeIncreaseAllowance(
            _smartTreasuryAddress,
            type(uint256).max
        );
        beneficiaries[0] = _smartTreasuryAddress;
    }

    /**
  @author Asaf Silman
  @notice Gives an address the WHITELISTED role. Used for calling `deposit()`.
  @dev Can only be called by admin.
  @param _addressToAdd The address to grant the role.
   */
    function addAddressToWhiteList(address _addressToAdd)
        external
        override
        onlyAdmin
    {
        grantRole(WHITELISTED, _addressToAdd);
    }

    /**
  @author Asaf Silman
  @notice Removed an address from whitelist.
  @dev Can only be called by admin
  @param _addressToRemove The address to revoke the WHITELISTED role.
   */
    function removeAddressFromWhiteList(address _addressToRemove)
        external
        override
        onlyAdmin
    {
        revokeRole(WHITELISTED, _addressToRemove);
    }

    /**
  @author Asaf Silman
  @notice Registers a fee token to the fee collecter
  @dev There is a maximum of 15 fee tokens than can be registered.
  @dev WETH cannot be accepted as a fee token.
  @dev The token must be a complient ERC20 token.
  @dev The fee token is approved for the uniswap router
  @param _tokenAddress The token address to register
   */
    function registerTokenToDepositList(address _tokenAddress)
        external
        override
        onlyAdmin
    {
        require(depositTokens.length() < MAX_NUM_FEE_TOKENS, "Too many tokens");
        require(_tokenAddress != address(0), "Token cannot be 0 address");
        require(_tokenAddress != weth, "WETH not supported"); // There is no WETH -> WETH pool in uniswap
        require(
            depositTokens.contains(_tokenAddress) == false,
            "Already exists"
        );

        IERC20(_tokenAddress).safeIncreaseAllowance(
            address(uniswapRouterV2),
            type(uint256).max
        ); // max approval
        depositTokens.add(_tokenAddress);
    }

    /**
  @author Asaf Silman
  @notice Removed a fee token from the fee collector.
  @dev Resets uniswap approval to 0.
  @param _tokenAddress The fee token address to remove.
   */
    function removeTokenFromDepositList(address _tokenAddress)
        external
        override
        onlyAdmin
    {
        IERC20(_tokenAddress).safeApprove(address(uniswapRouterV2), 0); // 0 approval for uniswap
        depositTokens.remove(_tokenAddress);
    }

    /**
  @author Asaf Silman
  @notice Withdraws a arbitrarty ERC20 token from feeCollector to an arbitrary address.
  @param _token The ERC20 token address.
  @param _toAddress The destination address.
  @param _amount The amount to transfer.
   */
    function withdraw(
        address _token,
        address _toAddress,
        uint256 _amount
    ) external override onlyAdmin {
        IERC20(_token).safeTransfer(_toAddress, _amount);
    }

    /**
     * Copied from idle.finance IdleTokenGovernance.sol
     *
     * Calculate amounts from percentage allocations (100000 => 100%)
     * @author idle.finance
     * @param _allocations : token allocations percentages
     * @param total : total amount
     * @return newAmounts : array with amounts
     */
    function _amountsFromAllocations(
        uint256[] memory _allocations,
        uint256 total
    ) internal pure returns (uint256[] memory newAmounts) {
        newAmounts = new uint256[](_allocations.length);
        uint256 currBalance;
        uint256 allocatedBalance;

        for (uint256 i = 0; i < _allocations.length; i++) {
            if (i == _allocations.length - 1) {
                newAmounts[i] = total.sub(allocatedBalance);
            } else {
                currBalance = total.mul(_allocations[i]).div(FULL_ALLOC);
                allocatedBalance = allocatedBalance.add(currBalance);
                newAmounts[i] = currBalance;
            }
        }
        return newAmounts;
    }

    /**
  @author Asaf Silman
  @notice Exchanges balancer pool token for the underlying assets and withdraws
  @param _toAddress The address to send the underlying tokens to
  @param _amount The underlying amount of balancer pool tokens to exchange
  */
    function withdrawUnderlying(
        address _toAddress,
        uint256 _amount,
        uint256[] calldata minTokenOut
    ) external override smartTreasurySet onlyAdmin {
        ConfigurableRightsPool crp = ConfigurableRightsPool(beneficiaries[0]);
        BPool smartTreasuryBPool = crp.bPool();

        uint256 numTokensInPool = smartTreasuryBPool.getNumTokens();
        require(minTokenOut.length == numTokensInPool, "Invalid length");

        address[] memory poolTokens = smartTreasuryBPool.getCurrentTokens();
        uint256[] memory feeCollectorTokenBalances = new uint256[](
            numTokensInPool
        );

        for (uint256 i = 0; i < poolTokens.length; i++) {
            // get the balance of a poolToken of the fee collector
            feeCollectorTokenBalances[i] = IERC20(poolTokens[i]).balanceOf(
                address(this)
            );
        }

        // tokens are exitted to feeCollector
        crp.exitPool(_amount, minTokenOut);

        IERC20 tokenInterface;
        uint256 tokenBalanceToTransfer;
        for (uint256 i = 0; i < poolTokens.length; i++) {
            tokenInterface = IERC20(poolTokens[i]);

            tokenBalanceToTransfer = tokenInterface
                .balanceOf(address(this))
                .sub( // get the new balance of token
                feeCollectorTokenBalances[i] // subtract previous balance
            );

            if (tokenBalanceToTransfer > 0) {
                // transfer to `_toAddress` [newBalance - oldBalance]
                tokenInterface.safeTransfer(_toAddress, tokenBalanceToTransfer); // transfer to `_toAddress`
            }
        }
    }

    /**
  @author Asaf Silman
  @notice Replaces the current admin with a new admin.
  @dev The current admin rights are revoked, and given the new address.
  @dev The caller must be admin (see onlyAdmin modifier).
  @param _newAdmin The new admin address.
   */
    function replaceAdmin(address _newAdmin) external override onlyAdmin {
        grantRole(DEFAULT_ADMIN_ROLE, _newAdmin);
        revokeRole(DEFAULT_ADMIN_ROLE, msg.sender); // caller must be admin
    }

    function getSplitAllocation() external view returns (uint256[] memory) {
        return (allocations);
    }

    function isAddressWhitelisted(address _address)
        external
        view
        returns (bool)
    {
        return (hasRole(WHITELISTED, _address));
    }

    function isAddressAdmin(address _address) external view returns (bool) {
        return (hasRole(DEFAULT_ADMIN_ROLE, _address));
    }

    function getBeneficiaries() external view returns (address[] memory) {
        return (beneficiaries);
    }

    function getSmartTreasuryAddress() external view returns (address) {
        return (beneficiaries[0]);
    }

    function isTokenInDespositList(address _tokenAddress)
        external
        view
        returns (bool)
    {
        return (depositTokens.contains(_tokenAddress));
    }

    function getNumTokensInDepositList() external view returns (uint256) {
        return (depositTokens.length());
    }

    function getDepositTokens() external view returns (address[] memory) {
        uint256 numTokens = depositTokens.length();

        address[] memory depositTokenList = new address[](numTokens);
        for (uint256 index = 0; index < numTokens; index++) {
            depositTokenList[index] = depositTokens.at(index);
        }
        return (depositTokenList);
    }
}
