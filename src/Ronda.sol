// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {SelfVerificationRoot} from "@selfxyz/contracts/abstract/SelfVerificationRoot.sol";
import {ISelfVerificationRoot} from "@selfxyz/contracts/interfaces/ISelfVerificationRoot.sol";
import {SelfStructs} from "@selfxyz/contracts/libraries/SelfStructs.sol";
import {SelfUtils} from "@selfxyz/contracts/libraries/SelfUtils.sol";
import {IIdentityVerificationHubV2} from "@selfxyz/contracts/interfaces/IIdentityVerificationHubV2.sol";

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

/**
 * Minimal subset of Aave v3 Pool interface used here.
 * This is intentionally small — only supply & withdraw functions we need.
 */
interface IPool {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
}

enum VerificationType {
    NONE,
    SELF_BASE,        // proof of personhood only
    SELF_AGE,         // proof of personhood + age requirement
    SELF_NATIONALITY  // proof of personhood + nationality requirement
}

contract RondaProtocol is SelfVerificationRoot {
    /* -------------------------------------------------------------------------- */
    /*                                   STORAGE                                  */
    /* -------------------------------------------------------------------------- */

    IERC20 public usdc;
    IPool public aavePool;
    IERC20 public aaveUsdc; // aUSDC token (interest bearing)

    address public creator;

    uint256 public groupId;
    bool public groupCreated;
    bool public initialized;

    VerificationType public verificationType;
    uint256 public recurringAmount;     // per round deposit amount

    struct MemberInfo {
        bool exists;
        bool verified;
        bool hasWonThisCycle;
    }

    mapping(address => MemberInfo) public memberInfo;
    address[] public memberList;

    // SELF config
    SelfStructs.VerificationConfigV2 public verificationConfig;
    bytes32 public verificationConfigId;

    /* ------------------------- Round deposit tracking ------------------------- */

    uint256 public currentRound;
    uint256 public totalPool;
    uint256 public depositsThisRound;  // count of deposit completions

    mapping(uint256 => mapping(address => bool)) public depositedInRound;

    /* --------------------------------- Events -------------------------------- */

    event GroupCreated(uint256 groupId, address creator);
    event UserJoined(address);
    event Verified(address);
    event Deposit(address indexed user, uint256 round);
    event Winner(address indexed user, uint256 amount, uint256 round);

    /* -------------------------------------------------------------------------- */
    /*                                 CONSTRUCTOR                                */
    /* -------------------------------------------------------------------------- */

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
     * @notice Initialize contract with group id, USDC, identity hub and Aave addresses.
     * @dev This is an evolution over the original initialize: adds Aave wiring so deposits can earn interest.
     */
    function initialize(
        uint256 _groupId,
        address _usdc,
        address identityVerificationHubV2Address,
        address _aavePool,
        address _aaveUsdc,
        SelfUtils.UnformattedVerificationConfigV2 memory _verificationConfig
    ) external {
        require(!initialized, "Already initialized");
        initialized = true;

        groupId = _groupId;
        usdc = IERC20(_usdc);

        // Aave integration (can be address(0) for deployments that don't use Aave yet)
        if (_aavePool != address(0)) {
            aavePool = IPool(_aavePool);
        }
        if (_aaveUsdc != address(0)) {
            aaveUsdc = IERC20(_aaveUsdc);
        }

        verificationConfig = SelfUtils.formatVerificationConfigV2(_verificationConfig);
        verificationConfigId =
            IIdentityVerificationHubV2(identityVerificationHubV2Address)
            .setVerificationConfigV2(verificationConfig);
    }

    /* -------------------------------------------------------------------------- */
    /*                               GROUP CREATION                               */
    /* -------------------------------------------------------------------------- */

    function createGroup(
        address _creator,
        VerificationType _verificationType,
        uint256 _recurringAmount,
        address[] memory _members
    ) external {
        require(initialized, "Not initialized");
        require(!groupCreated, "Already created");
        require(_recurringAmount > 0, "Invalid amount");
        require(_members.length > 0, "No members");

        creator = _creator;
        verificationType = _verificationType;
        recurringAmount = _recurringAmount;
        groupCreated = true;

        for (uint256 i = 0; i < _members.length; i++) {
            address m = _members[i];
            memberInfo[m] = MemberInfo({ exists: true, verified: false, hasWonThisCycle: false });
            memberList.push(m);
            emit UserJoined(m);
        }

        // creator must be included
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
     * @notice Deposit recurringAmount of USDC for the current round.
     * @dev New in this intermediate commit: deposits are auto-supplied to Aave if pool is configured.
     */
    function deposit() external {
        require(memberInfo[msg.sender].exists, "Not member");
        require(!depositedInRound[currentRound][msg.sender], "Already deposited");

        if (verificationType == VerificationType.SELF_BASE ||
            verificationType == VerificationType.SELF_AGE ||
            verificationType == VerificationType.SELF_NATIONALITY
        ) {
            require(memberInfo[msg.sender].verified, "Not verified");
        }

        // Transfer USDC from user to contract
        require(usdc.transferFrom(msg.sender, address(this), recurringAmount), "USDC transfer failed");

        // If Aave pool configured, approve & supply to Aave to earn interest
        if (address(aavePool) != address(0)) {
            require(usdc.approve(address(aavePool), recurringAmount), "Approve to Aave failed");
            // supply will send aUSDC to this contract on success; we don't need to track aUSDC balance here
            aavePool.supply(address(usdc), recurringAmount, address(this), 0);
        }

        depositedInRound[currentRound][msg.sender] = true;
        depositsThisRound += 1;
        totalPool += recurringAmount;

        emit Deposit(msg.sender, currentRound);
    }

    /* -------------------------------------------------------------------------- */
    /*                             ROUND COMPLETION                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Picks winner and pays out totalPool.
     * @dev Intermediate commit: before paying, withdraws from Aave (if configured) to ensure liquidity.
     *      This commit does not yet add feeRecipient/operator logic or advanced distribution of interest.
     */
    function payout() external {
        require(groupCreated, "Not created");
        require(depositsThisRound == memberList.length, "Round incomplete");
        require(totalPool > 0, "Empty pool");

        // build eligible list (members who haven't won this cycle)
        address[] memory eligible = _eligibleMembers();
        require(eligible.length > 0, "All have won");

        // random pick among eligible (same PRNG as before)
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

        // If we used Aave, withdraw the required amount back to this contract
        if (address(aavePool) != address(0)) {
            // withdraw returns amount actually withdrawn; send to this contract and then forward
            uint256 withdrawn = aavePool.withdraw(address(usdc), totalPool, address(this));
            require(withdrawn >= totalPool, "Aave withdraw short");
        }

        // transfer winnings
        require(usdc.transfer(winner, totalPool), "USDC transfer to winner failed");

        emit Winner(winner, totalPool, currentRound);

        // mark winner
        memberInfo[winner].hasWonThisCycle = true;

        // reset if everyone has won
        if (_everyoneHasWon()) {
            _resetWinCycle();
        }

        // prepare next round
        totalPool = 0;
        depositsThisRound = 0;
        currentRound += 1;
    }

    /* -------------------------------------------------------------------------- */
    /*                              HELPER FUNCTIONS                               */
    /* -------------------------------------------------------------------------- */

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

    function _everyoneHasWon() internal view returns (bool) {
        for (uint256 i = 0; i < memberList.length; i++) {
            if (!memberInfo[memberList[i]].hasWonThisCycle) return false;
        }
        return true;
    }

    function _resetWinCycle() internal {
        for (uint256 i = 0; i < memberList.length; i++) {
            memberInfo[memberList[i]].hasWonThisCycle = false;
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                          SELF VERIFICATION HOOK                            */
    /* -------------------------------------------------------------------------- */

    function customVerificationHook(
        ISelfVerificationRoot.GenericDiscloseOutputV2 memory output,
        bytes memory
    ) internal override {
        address user = address(uint160(output.userIdentifier));

        if (!memberInfo[user].exists) return;

        // In this intermediate commit we simply set verified=true on successful disclosure.
        // Future commits will validate age/nationality fields depending on verificationType.
        memberInfo[user].verified = true;
        emit Verified(user);
    }

    function getConfigId(bytes32, bytes32, bytes memory) public view override returns (bytes32) {
        return verificationConfigId;
    }

    /* -------------------------------------------------------------------------- */
    /*                                  UTIL / VIEW                                */
    /* -------------------------------------------------------------------------- */

    function membersCount() external view returns (uint256) {
        return memberList.length;
    }
}
