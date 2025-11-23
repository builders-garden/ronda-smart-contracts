// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import {SelfVerificationRoot} from "@selfxyz/contracts/abstract/SelfVerificationRoot.sol";
import {ISelfVerificationRoot} from "@selfxyz/contracts/interfaces/ISelfVerificationRoot.sol";
import {SelfStructs} from "@selfxyz/contracts/libraries/SelfStructs.sol";
import {SelfUtils} from "@selfxyz/contracts/libraries/SelfUtils.sol";
import {IIdentityVerificationHubV2} from "@selfxyz/contracts/interfaces/IIdentityVerificationHubV2.sol";
import {IPool} from "@aave/core-v3/interfaces/IPool.sol";

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

/**
 * @notice Enum defining verification requirements for groups
 */
enum VerificationType {
    NONE,                    // No verification required
    SELF_BASE,              // Proof of personhood only
    SELF_AGE,               // Proof of personhood + age verification
    SELF_NATIONALITY,        // Proof of personhood + nationality verification
    SELF_GENDER,            // Proof of personhood + gender verification
    SELF_AGE_NATIONALITY,    // Proof of personhood + age + nationality
    SELF_AGE_GENDER,        // Proof of personhood + age + gender
    SELF_NATIONALITY_GENDER, // Proof of personhood + nationality + gender
    SELF_ALL                // Proof of personhood + age + nationality + gender
}

contract RondaProtocol is SelfVerificationRoot {
    // ============================================================================
    // STATE VARIABLES
    // ============================================================================
    
    /// @notice USDC token contract
    IERC20 public usdc;
    
    /// @notice Aave Pool contract for lending/borrowing
    IPool public aavePool;
    
    /// @notice Aave USDC aToken (interest-bearing token)
    IERC20 public aaveUsdc;
    
    /// @notice Address to receive excess funds from interest
    address public feeRecipient;
    
    /// @notice Operator address authorized to call distributeFunds
    address public operator;
    
    /// @notice Group ID assigned by factory
    uint256 public groupId;
    
    /// @notice Full ENS subdomain name (e.g., "mygroup.ronda.eth")
    string public groupEnsName;
    
    /// @notice Verification configuration for Self Protocol
    SelfStructs.VerificationConfigV2 public verificationConfig;
    
    /// @notice Verification config ID from Identity Verification Hub
    bytes32 public verificationConfigId;
    
    /// @notice Initialization flag
    bool private initialized;
    
    /// @notice Group creation flag
    bool private groupCreated;
    
    /// @notice Mapping to track verified users (address => bool)
    mapping(address => bool) public verifiedUsers;
    
    // ============================================================================
    // CUSTOM ERRORS
    // ============================================================================
    
    /// @notice Thrown when USDC address is invalid
    error InvalidUSDCAddress();
    
    /// @notice Thrown when Aave Pool address is invalid
    error InvalidAavePoolAddress();
    
    /// @notice Thrown when Aave USDC address is invalid
    error InvalidAaveUSDCAddress();
    
    /// @notice Thrown when fee recipient address is invalid
    error InvalidFeeRecipient();
    
    /// @notice Thrown when operator address is invalid
    error InvalidOperatorAddress();
    
    /// @notice Thrown when Aave supply operation fails
    error AaveSupplyFailed();
    
    /// @notice Thrown when Aave withdraw operation fails
    error AaveWithdrawFailed();
    
    /// @notice Thrown when Aave USDC transfer fails
    error AaveUSDCTransferFailed();
    
    /// @notice Thrown when contract is already initialized
    error AlreadyInitialized();
    
    /// @notice Thrown when contract is not initialized
    error NotInitialized();
    
    /// @notice Thrown when address is not verified
    error AddressNotVerified();
    
    /// @notice Thrown when verification type is invalid
    error InvalidVerificationType();
    
    /// @notice Thrown when verification requirements are not met
    error VerificationRequirementsNotMet();
    
    /// @notice Thrown when deposit frequency is zero
    error DepositFrequencyMustBeGreaterThanZero();
    
    /// @notice Thrown when borrow frequency is zero
    error BorrowFrequencyMustBeGreaterThanZero();
    
    /// @notice Thrown when recurring amount is zero
    error RecurringAmountMustBeGreaterThanZero();
    
    /// @notice Thrown when operation counter is zero
    error OperationCounterMustBeGreaterThanZero();
    
    /// @notice Thrown when group is already created
    error GroupAlreadyCreated();
    
    /// @notice Thrown when group is not created
    error GroupNotCreated();
    
    /// @notice Thrown when only creator can invite
    error OnlyCreatorCanInvite();
    
    /// @notice Thrown when user address is invalid
    error InvalidUserAddress();
    
    /// @notice Thrown when user is already a member
    error UserAlreadyMember();
    
    /// @notice Thrown when user is not invited
    error UserNotInvited();
    
    /// @notice Thrown when address is not a member
    error NotAMember();
    
    /// @notice Thrown when all operations are completed
    error AllOperationsCompleted();
    
    /// @notice Thrown when user already deposited in this period
    error AlreadyDepositedInThisPeriod();
    
    /// @notice Thrown when USDC transfer fails
    error USDCTransferFailed();
    
    /// @notice Thrown when borrow frequency is not reached
    error BorrowFrequencyNotReached();
    
    /// @notice Thrown when no members are provided
    error NoMembersProvided();
    
    /// @notice Thrown when member is invalid
    error InvalidMember();
    
    /// @notice Thrown when there are no funds to distribute
    error NoFundsToDistribute();
    
    /// @notice Thrown when there are no members
    error NoMembers();
    
    /// @notice Thrown when caller is not the operator
    error OnlyOperator();
    
    // ============================================================================
    // GROUP DATA (Contract represents a single group)
    // ============================================================================
    
    /// @notice Address of the group creator
    address public creator;
    
    /// @notice Mapping to track group members (address => bool)
    mapping(address => bool) public members;
    
    /// @notice Mapping to track invited users (address => bool)
    mapping(address => bool) public invitedUsers;
    
    /// @notice Verification type required for this group
    VerificationType public verificationType;
    
    /// @notice Time between deposit periods (in seconds)
    uint256 public depositFrequency;
    
    /// @notice Time between borrow/distribution periods (in seconds)
    uint256 public borrowFrequency;
    
    /// @notice Amount each user should deposit per period (in USDC, 6 decimals)
    uint256 public recurringAmount;
    
    /// @notice Total number of times the operation must be run (set by creator)
    uint256 public operationCounter;
    
    /// @notice Current index of operation (0 to operationCounter-1)
    uint256 public currentOperationIndex;
    
    /// @notice Mapping to track deposits per period (operationIndex => user => hasDeposited)
    mapping(uint256 => mapping(address => bool)) public hasDeposited;
    
    /// @notice Mapping to track total deposits per period (operationIndex => total deposits)
    mapping(uint256 => uint256) public periodDeposits;
    
    /// @notice Timestamp of last deposit
    uint256 public lastDepositTime;
    
    /// @notice Timestamp of last borrow/distribution
    uint256 public lastBorrowTime;
    
    // Optional verification parameters
    /// @notice Minimum age requirement (if age verification is required)
    uint256 public minAge;
    
    /// @notice List of allowed nationalities (if nationality verification is required, empty array means no restriction)
    string[] public allowedNationalities;
    
    /// @notice Required gender (if gender verification is required)
    string public requiredGender;
    
    // ============================================================================
    // EVENTS
    // ============================================================================
    
    /// @notice Emitted when a group is created
    /// @param groupId The ID of the group
    /// @param creator The address of the creator
    /// @param depositFrequency Time between deposit periods (in seconds)
    /// @param borrowFrequency Time between borrow/distribution periods (in seconds)
    /// @param recurringAmount Amount each user should deposit per period
    /// @param operationCounter Total number of operations
    /// @param verificationType The verification type required
    event GroupCreated(
        uint256 indexed groupId, 
        address indexed creator, 
        uint256 depositFrequency, 
        uint256 borrowFrequency, 
        uint256 recurringAmount, 
        uint256 operationCounter,
        VerificationType verificationType
    );
    
    /// @notice Emitted when a user is invited to join the group
    /// @param groupId The ID of the group
    /// @param user The address of the invited user
    event UserInvited(uint256 indexed groupId, address indexed user);
    
    /// @notice Emitted when a user joins the group
    /// @param groupId The ID of the group
    /// @param user The address of the user who joined
    event UserJoined(uint256 indexed groupId, address indexed user);
    
    /// @notice Emitted when a user makes a deposit
    /// @param groupId The ID of the group
    /// @param user The address of the user who deposited
    /// @param amount The amount deposited
    /// @param period The period index
    event DepositMade(uint256 indexed groupId, address indexed user, uint256 amount, uint256 period);
    
    /// @notice Emitted when funds are distributed to a winner
    /// @param groupId The ID of the group
    /// @param winner The address of the winner
    /// @param amount The amount distributed
    /// @param period The period index
    event FundsDistributed(uint256 indexed groupId, address indexed winner, uint256 amount, uint256 period);
    
    /// @notice Emitted when verification is completed successfully
    /// @param groupId The ID of the group
    /// @param verifiedAddress The address that was verified
    /// @param output The verification output from the hub
    event VerificationCompleted(
        uint256 indexed groupId,
        address indexed verifiedAddress,
        ISelfVerificationRoot.GenericDiscloseOutputV2 output
    );
    
    /// @notice Emitted when verification fails
    /// @param groupId The ID of the group
    /// @param addressAttempted The address that attempted verification
    /// @param reason The reason for failure
    event VerificationFailed(
        uint256 indexed groupId,
        address indexed addressAttempted,
        string reason
    );

    /// @notice Thrown when verification fails
    error VerificationFailedError(uint256 groupId, address addressAttempted, string reason);
    
    // ============================================================================
    // MODIFIERS
    // ============================================================================
    
    /// @notice Modifier to ensure contract is initialized
    modifier onlyInitialized() {
        if (!initialized) revert NotInitialized();
        _;
    }
    
    /// @notice Modifier to ensure only operator can call
    modifier onlyOperator() {
        if (msg.sender != operator) revert OnlyOperator();
        _;
    }
    
    // ============================================================================
    // CONSTRUCTOR
    // ============================================================================
    
    /**
     * @notice Constructor for RondaProtocol (minimal for CREATE2 compatibility)
     * @dev The contract must be initialized after deployment using initialize()
     */
    constructor() SelfVerificationRoot(0xe57F4773bd9c9d8b6Cd70431117d353298B9f5BF, "ronda-test") {
        // Empty constructor for CREATE2 compatibility
        // Contract must be initialized via initialize() function
    }
    
    // ============================================================================
    // INITIALIZATION
    // ============================================================================
    
    /**
     * @notice Initializes the RondaProtocol contract
     * @param _groupId The group ID assigned by the factory
     * @param _ensSubdomain The full ENS subdomain name (e.g., "mygroup.ronda.eth")
     * @param _usdcAddress The address of the USDC token
     * @param identityVerificationHubV2Address The address of the Identity Verification Hub V2
     * @param _aavePoolAddress The address of the Aave Pool
     * @param _aaveUsdcAddress The address of the Aave USDC aToken
     * @param _feeRecipient The address to receive excess funds
     * @param _operator The address authorized to call distributeFunds
     * @param scopeSeed The scope seed string for verification
     * @param _verificationConfig The verification configuration
     */
    function initialize(
        uint256 _groupId,
        string memory _ensSubdomain,
        address _usdcAddress,
        address identityVerificationHubV2Address,
        address _aavePoolAddress,
        address _aaveUsdcAddress,
        address _feeRecipient,
        address _operator,
        string memory scopeSeed,
        SelfUtils.UnformattedVerificationConfigV2 memory _verificationConfig
    ) external {
        if (initialized) revert AlreadyInitialized();
        if (_usdcAddress == address(0)) revert InvalidUSDCAddress();
        if (_aavePoolAddress == address(0)) revert InvalidAavePoolAddress();
        if (_aaveUsdcAddress == address(0)) revert InvalidAaveUSDCAddress();
        if (_feeRecipient == address(0)) revert InvalidFeeRecipient();
        if (_operator == address(0)) revert InvalidOperatorAddress();
        if (identityVerificationHubV2Address == address(0)) revert InvalidUSDCAddress();
        
        initialized = true;
        groupId = _groupId;
        groupEnsName = _ensSubdomain;
        usdc = IERC20(_usdcAddress);
        aavePool = IPool(_aavePoolAddress);
        aaveUsdc = IERC20(_aaveUsdcAddress);
        feeRecipient = _feeRecipient;
        operator = _operator;
        
        // Initialize the parent contract's verification config
        verificationConfig = SelfUtils.formatVerificationConfigV2(_verificationConfig);
        verificationConfigId = IIdentityVerificationHubV2(identityVerificationHubV2Address)
            .setVerificationConfigV2(verificationConfig);
    }
    
    // ============================================================================
    // GROUP MANAGEMENT
    // ============================================================================
    
    /**
     * @notice Creates the group (called by factory after initialization)
     * @param _creator The address of the group creator
     * @param _depositFrequency Time between deposit periods (in seconds)
     * @param _borrowFrequency Time between borrow/distribution periods (in seconds)
     * @param _recurringAmount Amount each user should deposit per period (in USDC, 6 decimals)
     * @param _operationCounter Total number of times the operation must be run
     * @param _verificationType The type of verification required for this group
     * @param _minAge Minimum age requirement (only used if age verification is required, 0 otherwise)
     * @param _allowedNationalities List of allowed nationalities (only used if nationality verification is required, empty array means no restriction)
     * @param _requiredGender Required gender (only used if gender verification is required, empty string otherwise)
     * @param _usersToInvite Array of user addresses to invite when creating the group
     */
    function createGroup(
        address _creator,
        uint256 _depositFrequency,
        uint256 _borrowFrequency,
        uint256 _recurringAmount,
        uint256 _operationCounter,
        VerificationType _verificationType,
        uint256 _minAge,
        string[] memory _allowedNationalities,
        string memory _requiredGender,
        address[] memory _usersToInvite
    ) external onlyInitialized {
        if (groupCreated) revert GroupAlreadyCreated();
        if (_depositFrequency == 0) revert DepositFrequencyMustBeGreaterThanZero();
        if (_borrowFrequency == 0) revert BorrowFrequencyMustBeGreaterThanZero();
        if (_recurringAmount == 0) revert RecurringAmountMustBeGreaterThanZero();
        if (_operationCounter == 0) revert OperationCounterMustBeGreaterThanZero();
        if (uint256(_verificationType) > uint256(VerificationType.SELF_ALL)) revert InvalidVerificationType();
        
        groupCreated = true;
        creator = _creator;
        verificationType = _verificationType;
        depositFrequency = _depositFrequency;
        borrowFrequency = _borrowFrequency;
        recurringAmount = _recurringAmount;
        operationCounter = _operationCounter;
        currentOperationIndex = 0;
        lastDepositTime = block.timestamp;
        lastBorrowTime = block.timestamp;
        members[_creator] = true;
        
        // Set verification parameters if needed
        if (_verificationType != VerificationType.NONE) {
            // If age verification is required, minAge must be set
            if (_verificationType == VerificationType.SELF_AGE || 
                _verificationType == VerificationType.SELF_AGE_NATIONALITY ||
                _verificationType == VerificationType.SELF_AGE_GENDER ||
                _verificationType == VerificationType.SELF_ALL) {
                minAge = _minAge;
            }
            
            // If nationality verification is required, store allowed nationalities list
            if (_verificationType == VerificationType.SELF_NATIONALITY ||
                _verificationType == VerificationType.SELF_AGE_NATIONALITY ||
                _verificationType == VerificationType.SELF_NATIONALITY_GENDER ||
                _verificationType == VerificationType.SELF_ALL) {
                allowedNationalities = _allowedNationalities;
            }
            
            // If gender verification is required, requiredGender must be set
            if (_verificationType == VerificationType.SELF_GENDER ||
                _verificationType == VerificationType.SELF_AGE_GENDER ||
                _verificationType == VerificationType.SELF_NATIONALITY_GENDER ||
                _verificationType == VerificationType.SELF_ALL) {
                requiredGender = _requiredGender;
            }
        }
        
        // Invite users during group creation
        for (uint256 i = 0; i < _usersToInvite.length; i++) {
            address user = _usersToInvite[i];
            if (user == address(0)) revert InvalidUserAddress();
            if (user == _creator) continue; // Creator is already a member
            if (members[user]) continue; // Already a member, skip
            if (invitedUsers[user]) continue; // Already invited, skip
            
            invitedUsers[user] = true;
            emit UserInvited(groupId, user);
        }
        
        emit GroupCreated(groupId, _creator, _depositFrequency, _borrowFrequency, _recurringAmount, _operationCounter, _verificationType);
    }
    
    /**
     * @notice Allows an invited user to join the group
     * @dev Users can join without verification, but must verify before depositing
     * @dev Emits UserJoined event
     */
    function joinGroup() external {
        if (!groupCreated) revert GroupNotCreated();
        if (!invitedUsers[msg.sender]) revert UserNotInvited();
        if (members[msg.sender]) revert UserAlreadyMember();
        
        members[msg.sender] = true;
        invitedUsers[msg.sender] = false; // Remove from invited list
        
        emit UserJoined(groupId, msg.sender);
    }
    
    // ============================================================================
    // DEPOSITS
    // ============================================================================
    
    /**
     * @notice Allows a member to deposit the recurring amount during the current deposit period
     * @dev Requires verification if the group has verification requirements
     * @dev Automatically supplies USDC to Aave Pool to earn interest
     * @dev Emits DepositMade event
     */
    function deposit() external onlyInitialized {
        if (!groupCreated) revert GroupNotCreated();
        if (!members[msg.sender]) revert NotAMember();
        
        // Check verification requirements if group requires it
        if (verificationType != VerificationType.NONE) {
            if (!verifiedUsers[msg.sender]) {
                revert AddressNotVerified();
            }
        }
        
        // Check if we need to start a new period
        if (block.timestamp >= lastDepositTime + depositFrequency) {
            // Move to next operation index
            currentOperationIndex++;
            lastDepositTime = block.timestamp;
        }
        
        if (currentOperationIndex >= operationCounter) revert AllOperationsCompleted();
        if (hasDeposited[currentOperationIndex][msg.sender]) revert AlreadyDepositedInThisPeriod();
        
        // Transfer USDC from user to contract
        if (!usdc.transferFrom(msg.sender, address(this), recurringAmount)) {
            revert USDCTransferFailed();
        }
        
        // Approve Aave Pool to spend USDC
        if (!usdc.approve(address(aavePool), recurringAmount)) {
            revert USDCTransferFailed();
        }
        
        // Supply USDC to Aave Pool
        aavePool.supply(address(usdc), recurringAmount, address(this), 0);
        
        hasDeposited[currentOperationIndex][msg.sender] = true;
        periodDeposits[currentOperationIndex] += recurringAmount;
        
        emit DepositMade(groupId, msg.sender, recurringAmount, currentOperationIndex);
    }
    
    // ============================================================================
    // FUND DISTRIBUTION
    // ============================================================================
    
    /**
     * @notice Distributes funds to a randomly selected member when borrow frequency is reached
     * @dev Only the operator can call this function
     * @dev Withdraws funds from Aave and sends excess interest to fee recipient
     * @param _members Array of member addresses for random selection
     * @dev Emits FundsDistributed event
     */
    function distributeFunds(address[] calldata _members) external onlyInitialized onlyOperator {
        if (!groupCreated) revert GroupNotCreated();
        if (block.timestamp < lastBorrowTime + borrowFrequency) {
            revert BorrowFrequencyNotReached();
        }
        if (_members.length == 0) revert NoMembersProvided();
        
        // Verify all provided addresses are members
        for (uint256 i = 0; i < _members.length; i++) {
            if (!members[_members[i]]) revert InvalidMember();
        }
        
        // Get the period to distribute (current operation index)
        uint256 periodToDistribute = currentOperationIndex;
        uint256 amountToDistribute = periodDeposits[periodToDistribute];
        
        if (amountToDistribute == 0) revert NoFundsToDistribute();
        
        // Select a random member using pseudorandomity
        address winner = _selectRandomMember(_members);
        
        // Update last borrow time
        lastBorrowTime = block.timestamp;
        
        // Withdraw the exact amount needed for the winner
        uint256 withdrawnAmount = aavePool.withdraw(address(usdc), amountToDistribute, winner);
        
        if (withdrawnAmount < amountToDistribute) {
            revert AaveWithdrawFailed();
        }
        
        // Check if there's any excess aUSDC in the contract (from interest)
        uint256 contractBalance = aaveUsdc.balanceOf(address(this));
        if (contractBalance > 0) {
            // Send excess to fee recipient
            if (!aaveUsdc.transfer(feeRecipient, contractBalance)) {
                revert AaveUSDCTransferFailed();
            }
        }
        
        // Clear the period deposits
        periodDeposits[periodToDistribute] = 0;
        
        emit FundsDistributed(groupId, winner, amountToDistribute, periodToDistribute);
    }
    
    // ============================================================================
    // INTERNAL HELPERS
    // ============================================================================
    
    /**
     * @notice Selects a random member using pseudorandomity
     * @param _members Array of member addresses
     * @return The selected member address
     * @dev Uses blockhash, timestamp, and group data for randomness
     */
    function _selectRandomMember(address[] calldata _members) internal view returns (address) {
        if (_members.length == 0) revert NoMembers();
        
        // Use blockhash, timestamp, and group data for pseudorandomity
        uint256 randomSeed = uint256(
            keccak256(
                abi.encodePacked(
                    blockhash(block.number - 1),
                    block.timestamp,
                    block.number,
                    groupId,
                    currentOperationIndex,
                    _members.length
                )
            )
        );
        
        uint256 randomIndex = randomSeed % _members.length;
        return _members[randomIndex];
    }
    
    // ============================================================================
    // VIEW FUNCTIONS - MEMBERSHIP
    // ============================================================================
    
    /**
     * @notice Checks if an address is a member of the group
     * @param _user The address to check
     * @return True if the user is a member
     */
    function isMember(address _user) external view returns (bool) {
        return members[_user];
    }
    
    /**
     * @notice Checks if an address is invited to the group
     * @param _user The address to check
     * @return True if the user is invited
     */
    function isInvited(address _user) external view returns (bool) {
        return invitedUsers[_user];
    }
    
    // ============================================================================
    // VIEW FUNCTIONS - GROUP INFO
    // ============================================================================
    
    /**
     * @notice Gets basic group information
     * @return _creator The creator address
     * @return _verificationType The verification type required
     * @return _depositFrequency The deposit frequency in seconds
     * @return _borrowFrequency The borrow frequency in seconds
     * @return _recurringAmount The recurring deposit amount
     * @return _operationCounter The total number of operations
     * @return _currentOperationIndex The current operation index
     * @return _lastDepositTime The timestamp of last deposit
     * @return _lastBorrowTime The timestamp of last borrow
     * @return _minAge Minimum age requirement
     * @return _allowedNationalities List of allowed nationalities
     * @return _requiredGender Required gender
     */
    function getGroupInfo() external view returns (
        address _creator,
        VerificationType _verificationType,
        uint256 _depositFrequency,
        uint256 _borrowFrequency,
        uint256 _recurringAmount,
        uint256 _operationCounter,
        uint256 _currentOperationIndex,
        uint256 _lastDepositTime,
        uint256 _lastBorrowTime,
        uint256 _minAge,
        string[] memory _allowedNationalities,
        string memory _requiredGender
    ) {
        return (
            creator,
            verificationType,
            depositFrequency,
            borrowFrequency,
            recurringAmount,
            operationCounter,
            currentOperationIndex,
            lastDepositTime,
            lastBorrowTime,
            minAge,
            allowedNationalities,
            requiredGender
        );
    }
    
    // ============================================================================
    // VIEW FUNCTIONS - DEPOSIT STATUS
    // ============================================================================
    
    /**
     * @notice Gets the deposit status for a user in a specific operation period
     * @param _operationIndex The operation index to check
     * @param _user The address to check
     * @return True if the user has deposited in that operation period
     */
    function hasUserDeposited(uint256 _operationIndex, address _user) external view returns (bool) {
        return hasDeposited[_operationIndex][_user];
    }
    
    /**
     * @notice Gets the deposit status for a user in a specific or current operation period
     * @param _user The address to check
     * @param _operationIndex The operation index to check (use type(uint256).max to check current period)
     * @return True if the user has deposited in that period
     */
    function hasUserDepositedInPeriod(address _user, uint256 _operationIndex) external view returns (bool) {
        uint256 periodIndex = _operationIndex == type(uint256).max ? currentOperationIndex : _operationIndex;
        return hasDeposited[periodIndex][_user];
    }
    
    /**
     * @notice Gets the deposit status for a user in the current operation period
     * @param _user The address to check
     * @return True if the user has deposited in the current period
     */
    function hasUserDepositedCurrentPeriod(address _user) external view returns (bool) {
        return hasDeposited[currentOperationIndex][_user];
    }
    
    /**
     * @notice Gets deposit status for a user across all periods
     * @param _user The address to check
     * @return depositedPeriods Array of booleans indicating if user deposited in each period (index = period)
     * @return totalPeriods Total number of periods (operationCounter)
     */
    function getUserDepositStatusForAllPeriods(address _user) external view returns (
        bool[] memory depositedPeriods,
        uint256 totalPeriods
    ) {
        totalPeriods = operationCounter;
        depositedPeriods = new bool[](totalPeriods);
        
        for (uint256 i = 0; i < totalPeriods; i++) {
            depositedPeriods[i] = hasDeposited[i][_user];
        }
        
        return (depositedPeriods, totalPeriods);
    }
    
    /**
     * @notice Gets the total deposits for a specific operation period
     * @param _operationIndex The operation index
     * @return The total amount deposited in that period
     */
    function getPeriodDeposits(uint256 _operationIndex) external view returns (uint256) {
        return periodDeposits[_operationIndex];
    }
    
    /**
     * @notice Gets comprehensive information about the group including current period deposits
     * @return _creator The creator address
     * @return _verificationType The verification type required
     * @return _depositFrequency The deposit frequency in seconds
     * @return _borrowFrequency The borrow frequency in seconds
     * @return _recurringAmount The recurring deposit amount
     * @return _operationCounter The total number of operations
     * @return _currentOperationIndex The current operation index
     * @return _lastDepositTime The timestamp of last deposit
     * @return _lastBorrowTime The timestamp of last borrow
     * @return _minAge Minimum age requirement
     * @return _allowedNationalities List of allowed nationalities
     * @return _requiredGender Required gender
     * @return _currentPeriodDeposits Total deposits in current period
     * @return _exists Whether the group exists
     */
    function getGroupInfoDetailed() external view returns (
        address _creator,
        VerificationType _verificationType,
        uint256 _depositFrequency,
        uint256 _borrowFrequency,
        uint256 _recurringAmount,
        uint256 _operationCounter,
        uint256 _currentOperationIndex,
        uint256 _lastDepositTime,
        uint256 _lastBorrowTime,
        uint256 _minAge,
        string[] memory _allowedNationalities,
        string memory _requiredGender,
        uint256 _currentPeriodDeposits,
        bool _exists
    ) {
        _exists = groupCreated;
        return (
            creator,
            verificationType,
            depositFrequency,
            borrowFrequency,
            recurringAmount,
            operationCounter,
            currentOperationIndex,
            lastDepositTime,
            lastBorrowTime,
            minAge,
            allowedNationalities,
            requiredGender,
            periodDeposits[currentOperationIndex],
            _exists
        );
    }
    
    // ============================================================================
    // VERIFICATION
    // ============================================================================
    
    /**
     * @notice Implementation of customVerificationHook
     * @dev Called by onVerificationSuccess after hub address validation
     * @param output The verification output from the hub
     * @dev Validates verification requirements based on group's verification type
     * @dev Emits VerificationCompleted or VerificationFailed event
     */
    function customVerificationHook(
        ISelfVerificationRoot.GenericDiscloseOutputV2 memory output,
        bytes memory /* userData */
    ) internal override {
        if (!groupCreated) {
            emit VerificationFailed(groupId, address(0), "Group not created");
            revert VerificationFailedError(groupId, address(0), "Group not created");
        }
    
        address verifiedAddress = address(uint160((output.userIdentifier)));
        
        // Verify the address is a member of the group
        if (!members[verifiedAddress]) {
            emit VerificationFailed(groupId, verifiedAddress, "Address is not a group member");
            revert VerificationFailedError(groupId, verifiedAddress, "Address is not a group member");
        }
        
        // Check if verification is required for this group
        if (verificationType == VerificationType.NONE || verificationType == VerificationType.SELF_BASE) {
            // No verification needed or simple proof of personhood
            verifiedUsers[verifiedAddress] = true;
            emit VerificationCompleted(groupId, verifiedAddress, output);
            return;
        }
        // Validate verification requirements based on group type
        bool requirementsMet = true;
        string memory failureReason = "";
        
        // Check age requirement if needed
        if (verificationType == VerificationType.SELF_AGE ||
            verificationType == VerificationType.SELF_AGE_NATIONALITY ||
            verificationType == VerificationType.SELF_AGE_GENDER ||
            verificationType == VerificationType.SELF_ALL) {
            if (output.olderThan < minAge) {
                requirementsMet = false;
                failureReason = "Age requirement not met";
            }
        }
        
        // Check nationality requirement if needed
        if (requirementsMet && (
            verificationType == VerificationType.SELF_NATIONALITY ||
            verificationType == VerificationType.SELF_AGE_NATIONALITY ||
            verificationType == VerificationType.SELF_NATIONALITY_GENDER ||
            verificationType == VerificationType.SELF_ALL)) {
            // If allowed nationalities list is empty, no restriction
            if (allowedNationalities.length > 0) {
                bool nationalityFound = false;
                for (uint256 i = 0; i < allowedNationalities.length; i++) {
                    if (keccak256(bytes(output.nationality)) == keccak256(bytes(allowedNationalities[i]))) {
                        nationalityFound = true;
                        break;
                    }
                }
                if (!nationalityFound) {
                    requirementsMet = false;
                    failureReason = "Nationality requirement not met";
                }
            }
        }
        
        // Check gender requirement if needed
        if (requirementsMet && (
            verificationType == VerificationType.SELF_GENDER ||
            verificationType == VerificationType.SELF_AGE_GENDER ||
            verificationType == VerificationType.SELF_NATIONALITY_GENDER ||
            verificationType == VerificationType.SELF_ALL)) {
            if (keccak256(bytes(output.gender)) != keccak256(bytes(requiredGender))) {
                requirementsMet = false;
                failureReason = "Gender requirement not met";
            }
        }
        
        if (requirementsMet) {
            // Mark user as verified
            verifiedUsers[verifiedAddress] = true;
            emit VerificationCompleted(groupId, verifiedAddress, output);
        } else {
            revert VerificationFailedError(groupId, verifiedAddress, failureReason);
        }
    }
    
    /**
     * @notice Returns the verification config ID
     * @return The verification config ID
     */
    function getConfigId(
        bytes32 /* destinationChainId */,
        bytes32 /* userIdentifier */,
        bytes memory /* userDefinedData */
    ) public view override returns (bytes32) {
        return verificationConfigId;
    }
    
    /**
     * @notice Checks if a user is verified
     * @param _user The address to check
     * @return True if the user is verified
     */
    function isUserVerified(address _user) external view returns (bool) {
        return verifiedUsers[_user];
    }
}

