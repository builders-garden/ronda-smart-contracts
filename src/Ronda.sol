// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {SelfVerificationRoot} from "@selfxyz/contracts/abstract/SelfVerificationRoot.sol";
import {ISelfVerificationRoot} from "@selfxyz/contracts/interfaces/ISelfVerificationRoot.sol";
import {SelfStructs} from "@selfxyz/contracts/libraries/SelfStructs.sol";
import {SelfUtils} from "@selfxyz/contracts/libraries/SelfUtils.sol";
import {IIdentityVerificationHubV2} from "@selfxyz/contracts/interfaces/IIdentityVerificationHubV2.sol";

/// @notice Minimal ERC20 interface used in this contract
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @notice Minimal subset of Aave v3 Pool interface used here.
interface IPool {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
}

/// @notice Verification requirements for groups (kept small in this intermediate commit)
enum VerificationType {
    NONE,
    SELF_BASE,        // proof of personhood only
    SELF_AGE,         // proof of personhood + age requirement
    SELF_NATIONALITY  // proof of personhood + nationality requirement
}

/**
 * @title RondaProtocol
 * @notice Group-based rotating savings contract with optional SELF verification and optional Aave supply integration.
 *   This is an incremental, well-documented commit: deposits can be auto-supplied to Aave (if configured) and payouts
 *   will withdraw from Aave when necessary. Verification hook marks members as verified. Comments and validation restored.
 */
contract RondaProtocol is SelfVerificationRoot {
    /* -------------------------------------------------------------------------- */
    /*                                   STORAGE                                  */
    /* -------------------------------------------------------------------------- */

    /// @notice USDC token contract (6 decimals)
    IERC20 public usdc;

    /// @notice Optional Aave Pool to supply/withdraw USDC
    IPool public aavePool;

    /// @notice Optional aUSDC token address (interest-bearing counterpart)
    IERC20 public aaveUsdc;

    /// @notice Group creator (original deployer/creator assigned when createGroup is called)
    address public creator;

    /// @notice Unique group id assigned by factory / controller
    uint256 public groupId;

    /// @notice Whether group was created
    bool public groupCreated;

    /// @notice Whether initialize() was called
    bool public initialized;

    /// @notice Verification rules for this group
    VerificationType public verificationType;

    /// @notice Per-member deposit amount for each round
    uint256 public recurringAmount;

    /// @notice Information tracked per member
    struct MemberInfo {
        bool exists;           // is in group
        bool verified;         // passed SELF verification
        bool hasWonThisCycle;  // has already won in current cycle
    }

    /// @notice Mapping from member address to info
    mapping(address => MemberInfo) public memberInfo;

    /// @notice Ordered list of members (used for round completion)
    address[] public memberList;

    /// @notice SELF verification configuration stored after initialize
    SelfStructs.VerificationConfigV2 public verificationConfig;
    bytes32 public verificationConfigId;

    /* ------------------------- Round deposit tracking ------------------------- */

    /// @notice Current round index (0-based)
    uint256 public currentRound;

    /// @notice Total amount currently pooled (in USDC) for the round
    uint256 public totalPool;

    /// @notice Count of completed deposits this round
    uint256 public depositsThisRound;

    /// @notice Per-round deposit flag: round -> user -> deposited?
    mapping(uint256 => mapping(address => bool)) public depositedInRound;

    /* --------------------------------- Events -------------------------------- */

    event GroupCreated(uint256 indexed groupId, address indexed creator);
    event UserJoined(address indexed user);
    event Verified(address indexed user);
    event DepositMade(address indexed user, uint256 indexed round, uint256 amount);
    event Winner(address indexed user, uint256 amount, uint256 round);

    /* -------------------------------------------------------------------------- */
    /*                                 CONSTRUCTOR                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @dev Calls SelfVerificationRoot constructor with a default hub and namespace.
     *      Values may be replaced by initialize() in factory deployments.
     */
    constructor()
        SelfVerificationRoot(
            0xe57F4773bd9c9d8b6Cd70431117d353298B9f5BF,
            "ronda"
        )
    {}

    /* -------------------------------------------------------------------------- */
    /*                                  INITIALIZE                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Initializes contract configuration that cannot be set in constructor (factory-friendly)
     * @param _groupId Group id assigned by factory/controller
     * @param _usdc Address of USDC token
     * @param identityVerificationHubV2Address Address of IdentityVerificationHubV2 (used to register verification config)
     * @param _aavePool Optional Aave Pool address (address(0) to disable Aave integration)
     * @param _aaveUsdc Optional aUSDC token address (address(0) if not used)
     * @param _verificationConfig SELF unformatted verification config (will be formatted and set in hub)
     */
    function initialize(
        uint256 _groupId,
        address _usdc,
        address identityVerificationHubV2Address,
        address _aavePool,
        address _aaveUsdc,
        SelfUtils.UnformattedVerificationConfigV2 memory _verificationConfig
    ) external {
        require(!initialized, "Ronda: already initialized");
        require(_usdc != address(0), "Ronda: usdc zero address");
        require(identityVerificationHubV2Address != address(0), "Ronda: hub zero address");

        initialized = true;
        groupId = _groupId;
        usdc = IERC20(_usdc);

        // optional Aave wiring; allow deployments that don't use Aave (address(0))
        if (_aavePool != address(0)) {
            aavePool = IPool(_aavePool);
        }
        if (_aaveUsdc != address(0)) {
            aaveUsdc = IERC20(_aaveUsdc);
        }

        // format and set verification config in the IdentityVerificationHubV2
        verificationConfig = SelfUtils.formatVerificationConfigV2(_verificationConfig);
        verificationConfigId =
            IIdentityVerificationHubV2(identityVerificationHubV2Address)
            .setVerificationConfigV2(verificationConfig);
    }

    /* -------------------------------------------------------------------------- */
    /*                               GROUP CREATION                               */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Create a new group and register its members.
     * @dev This function is intentionally simple and requires the factory/controller
     *      to call it after initialize(). Member list must be non-empty.
     * @param _creator Creator address (is included as a member if not present)
     * @param _verificationType Which verification requirements to enforce for deposits
     * @param _recurringAmount Amount each member deposits per round (USDC smallest unit)
     * @param _members Initial list of member addresses
     */
    function createGroup(
        address _creator,
        VerificationType _verificationType,
        uint256 _recurringAmount,
        address[] memory _members
    ) external {
        require(initialized, "Ronda: not initialized");
        require(!groupCreated, "Ronda: already created");
        require(_creator != address(0), "Ronda: creator zero address");
        require(_members.length > 0, "Ronda: no members");
        require(_recurringAmount > 0, "Ronda: recurring amount zero");

        creator = _creator;
        verificationType = _verificationType;
        recurringAmount = _recurringAmount;
        groupCreated = true;

        // add members; guard against duplicates in provided array
        for (uint256 i = 0; i < _members.length; i++) {
            address m = _members[i];
            require(m != address(0), "Ronda: member zero address");
            if (!memberInfo[m].exists) {
                memberInfo[m] = MemberInfo({ exists: true, verified: false, hasWonThisCycle: false });
                memberList.push(m);
                emit UserJoined(m);
            }
        }

        // ensure creator is included
        if (!memberInfo[_creator].exists) {
            memberInfo[_creator] = MemberInfo({ exists: true, verified: false, hasWonThisCycle: false });
            memberList.push(_creator);
            emit UserJoined(_creator);
        }

        emit GroupCreated(groupId, _creator);
    }

    /* -------------------------------------------------------------------------- */
    /*                                 DEPOSIT                                    */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Deposits the fixed recurringAmount for the current round.
     * @dev If Aave Pool is configured, the contract will approve and supply the USDC to Aave to earn interest.
     *      Depositors must be registered members and, if verification is enabled, must be verified.
     */
    function deposit() external {
        require(groupCreated, "Ronda: group not created");
        require(memberInfo[msg.sender].exists, "Ronda: not a member");
        require(!depositedInRound[currentRound][msg.sender], "Ronda: already deposited this round");

        // If any verification is required, member must be verified
        if (verificationType != VerificationType.NONE) {
            require(memberInfo[msg.sender].verified, "Ronda: member not verified");
        }

        // Pull USDC from user
        bool ok = usdc.transferFrom(msg.sender, address(this), recurringAmount);
        require(ok, "Ronda: usdc transferFrom failed");

        // Supply to Aave if configured to earn interest
        if (address(aavePool) != address(0)) {
            // Note: some ERC20s require approve(0) before changing allowance; keep simple here.
            ok = usdc.approve(address(aavePool), recurringAmount);
            require(ok, "Ronda: approve to aave failed");
            aavePool.supply(address(usdc), recurringAmount, address(this), 0);
            // aUSDC will be minted to this contract by Aave
        }

        depositedInRound[currentRound][msg.sender] = true;
        depositsThisRound += 1;
        totalPool += recurringAmount;

        emit DepositMade(msg.sender, currentRound, recurringAmount);
    }

    /* -------------------------------------------------------------------------- */
    /*                             ROUND COMPLETION                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Finalize the round: pick a winner and pay out the pooled principal.
     * @dev Withdraws principal from Aave if necessary. This commit intentionally does not
     *      split interest or route fees — that is left for a following commit.
     */
    function payout() external {
        require(groupCreated, "Ronda: group not created");
        require(depositsThisRound == memberList.length, "Ronda: round incomplete");
        require(totalPool > 0, "Ronda: nothing to pay");

        address[] memory eligible = _eligibleMembers();
        require(eligible.length > 0, "Ronda: no eligible members");

        // Pseudorandom selection (not secure for high-value randomness; okay for this incremental commit)
        uint256 random = uint256(
            keccak256(
                abi.encodePacked(
                    blockhash(block.number - 1),
                    block.timestamp,
                    currentRound,
                    totalPool
                )
            )
        );
        address winner = eligible[random % eligible.length];

        // If funds are in Aave, withdraw exact principal to this contract
        if (address(aavePool) != address(0)) {
            uint256 withdrawn = aavePool.withdraw(address(usdc), totalPool, address(this));
            require(withdrawn >= totalPool, "Ronda: aave withdraw short");
        }

        // Transfer pooled principal to the winner
        bool sent = usdc.transfer(winner, totalPool);
        require(sent, "Ronda: usdc transfer to winner failed");

        emit Winner(winner, totalPool, currentRound);

        // Mark winner for this cycle and rotate if everyone has won
        memberInfo[winner].hasWonThisCycle = true;
        if (_everyoneHasWon()) {
            _resetWinCycle();
        }

        // Reset round bookkeeping
        totalPool = 0;
        depositsThisRound = 0;
        currentRound += 1;
    }

    /* -------------------------------------------------------------------------- */
    /*                              HELPER FUNCTIONS                               */
    /* -------------------------------------------------------------------------- */

    /// @notice Returns members who have not yet won in the current cycle
    function _eligibleMembers() internal view returns (address[] memory arr) {
        uint256 count;
        for (uint256 i = 0; i < memberList.length; i++) {
            if (!memberInfo[memberList[i]].hasWonThisCycle) {
                count++;
            }
        }

        arr = new address[](count);
        uint256 idx;
        for (uint256 i = 0; i < memberList.length; i++) {
            if (!memberInfo[memberList[i]].hasWonThisCycle) {
                arr[idx++] = memberList[i];
            }
        }
    }

    /// @notice Returns true if every member has won at least once in current cycle
    function _everyoneHasWon() internal view returns (bool) {
        for (uint256 i = 0; i < memberList.length; i++) {
            if (!memberInfo[memberList[i]].hasWonThisCycle) return false;
        }
        return true;
    }

    /// @notice Resets per-cycle winner tracking for all members.
    function _resetWinCycle() internal {
        for (uint256 i = 0; i < memberList.length; i++) {
            memberInfo[memberList[i]].hasWonThisCycle = false;
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                          SELF VERIFICATION HOOK                            */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Hook called by SelfVerificationRoot on successful verification.
     * @dev This intermediate commit keeps the behavior simple: mark the member as verified.
     *      Future commits will enforce age/nationality checks depending on verificationType.
     */
    function customVerificationHook(
        ISelfVerificationRoot.GenericDiscloseOutputV2 memory output,
        bytes memory
    ) internal override {
        address user = address(uint160(output.userIdentifier));

        // Only mark known members
        if (!memberInfo[user].exists) {
            return;
        }

        memberInfo[user].verified = true;
        emit Verified(user);
    }

    /**
     * @notice Return the verification config id previously set in initialize().
     * @dev Required override for SelfVerificationRoot.
     */
    function getConfigId(bytes32, bytes32, bytes memory) public view override returns (bytes32) {
        return verificationConfigId;
    }

    /* -------------------------------------------------------------------------- */
    /*                                  UTIL / VIEW                                */
    /* -------------------------------------------------------------------------- */

    /// @notice Returns the number of members in the group
    function membersCount() external view returns (uint256) {
        return memberList.length;
    }
}
