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
}

enum VerificationType {
    NONE,
    SELF
}

contract RondaProtocol is SelfVerificationRoot {

    /* -------------------------------------------------------------------------- */
    /*                                BASIC STORAGE                               */
    /* -------------------------------------------------------------------------- */

    IERC20 public usdc;
    address public creator;

    uint256 public groupId;
    bool public groupCreated;
    bool private initialized;

    // membership
    mapping(address => bool) public invited;
    mapping(address => bool) public members;

    // verification
    VerificationType public verificationType;
    mapping(address => bool) public verifiedUsers;

    // SELF verification config
    SelfStructs.VerificationConfigV2 public verificationConfig;
    bytes32 public verificationConfigId;

    /* -------------------------------------------------------------------------- */
    /*                               ROUND STRUCTURE                              */
    /* -------------------------------------------------------------------------- */

    uint256 public currentRound;
    uint256 public totalPool; // total USDC in contract

    mapping(uint256 => mapping(address => uint256)) public roundDeposits;
    mapping(address => uint256) public totalDepositedByUser;

    /* -------------------------------------------------------------------------- */
    /*                                    EVENTS                                  */
    /* -------------------------------------------------------------------------- */

    event GroupCreated(uint256 groupId, address creator);
    event UserInvited(address);
    event UserJoined(address);
    event Verified(address);

    event Deposit(address indexed user, uint256 amount, uint256 round);
    event WinnerSelected(address indexed winner, uint256 amount, uint256 round);

    /* -------------------------------------------------------------------------- */
    /*                                 CONSTRUCTOR                                */
    /* -------------------------------------------------------------------------- */

    constructor()
        SelfVerificationRoot(
            0xe57F4773bd9c9d8b6Cd70431117d353298B9f5BF, 
            "ronda-stage2"
        )
    {}

    /* -------------------------------------------------------------------------- */
    /*                                  INITIALIZE                                */
    /* -------------------------------------------------------------------------- */

    function initialize(
        uint256 _groupId,
        address _usdc,
        address identityVerificationHubV2Address,
        SelfUtils.UnformattedVerificationConfigV2 memory _verificationConfig
    ) external {
        require(!initialized, "Already initialized");

        groupId = _groupId;
        usdc = IERC20(_usdc);
        initialized = true;

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
        address[] memory _invites
    ) external {
        require(initialized, "Not initialized");
        require(!groupCreated, "Already created");

        creator = _creator;
        verificationType = _verificationType;
        groupCreated = true;

        members[_creator] = true;

        for (uint256 i = 0; i < _invites.length; i++) {
            invited[_invites[i]] = true;
            emit UserInvited(_invites[i]);
        }

        emit GroupCreated(groupId, _creator);
    }

    /* -------------------------------------------------------------------------- */
    /*                                JOIN GROUP                                  */
    /* -------------------------------------------------------------------------- */

    function joinGroup() external {
        require(groupCreated, "Group not created");
        require(invited[msg.sender], "Not invited");
        require(!members[msg.sender], "Already member");

        invited[msg.sender] = false;
        members[msg.sender] = true;

        emit UserJoined(msg.sender);
    }

    /* -------------------------------------------------------------------------- */
    /*                              SIMPLE DEPOSIT                                */
    /* -------------------------------------------------------------------------- */

    function deposit(uint256 amount) external {
        require(members[msg.sender], "Not a member");

        if (verificationType == VerificationType.SELF) {
            require(verifiedUsers[msg.sender], "Not verified");
        }

        require(usdc.transferFrom(msg.sender, address(this), amount));

        roundDeposits[currentRound][msg.sender] += amount;
        totalDepositedByUser[msg.sender] += amount;
        totalPool += amount;

        emit Deposit(msg.sender, amount, currentRound);
    }

    /* -------------------------------------------------------------------------- */
    /*                          SIMPLE ROUND PAYOUT                                */
    /* -------------------------------------------------------------------------- */

    function payout(address[] calldata memberList) external {
        require(groupCreated, "Group not created");
        require(memberList.length > 0, "No members");

        require(totalPool > 0, "No funds");

        // very primitive randomness — will improve later
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

        address winner = memberList[random % memberList.length];

        require(usdc.transfer(winner, totalPool));

        emit WinnerSelected(winner, totalPool, currentRound);

        // reset pool and move to next round
        totalPool = 0;
        currentRound += 1;
    }

    /* -------------------------------------------------------------------------- */
    /*                          SELF VERIFICATION HOOK                            */
    /* -------------------------------------------------------------------------- */

    function customVerificationHook(
        ISelfVerificationRoot.GenericDiscloseOutputV2 memory output,
        bytes memory
    ) internal override {
        address user = address(uint160(output.userIdentifier));
        if (!members[user]) return;

        verifiedUsers[user] = true;
        emit Verified(user);
    }

    function getConfigId(
        bytes32,
        bytes32,
        bytes memory
    ) public view override returns (bytes32) {
        return verificationConfigId;
    }
}
