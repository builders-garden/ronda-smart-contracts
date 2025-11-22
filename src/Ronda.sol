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

contract RondaProtocolWIP is SelfVerificationRoot {

    /* -------------------------------------------------------------------------- */
    /*                                BASIC STORAGE                               */
    /* -------------------------------------------------------------------------- */

    IERC20 public usdc;    
    address public creator;

    uint256 public groupId;
    bool public groupCreated;
    bool private initialized;

    // simple membership management
    mapping(address => bool) public invited;
    mapping(address => bool) public members;

    // basic verification
    VerificationType public verificationType;
    mapping(address => bool) public verifiedUsers;

    // SELF verification config
    SelfStructs.VerificationConfigV2 public verificationConfig;
    bytes32 public verificationConfigId;

    /* -------------------------------------------------------------------------- */
    /*                                    EVENTS                                  */
    /* -------------------------------------------------------------------------- */
    event GroupCreated(uint256 groupId, address creator);
    event UserInvited(address user);
    event UserJoined(address user);
    event Deposit(address user, uint256 amount);
    event VerificationCompleted(address user);

    /* -------------------------------------------------------------------------- */
    /*                                  ERRORS                                    */
    /* -------------------------------------------------------------------------- */
    error AlreadyInitialized();
    error GroupNotCreated();
    error NotInvited();
    error AlreadyMember();
    error NotMember();
    error NotVerified();

    /* -------------------------------------------------------------------------- */
    /*                                 CONSTRUCTOR                                */
    /* -------------------------------------------------------------------------- */

    constructor()
        SelfVerificationRoot(
            0xe57F4773bd9c9d8b6Cd70431117d353298B9f5BF, /* hub address */
            "ronda-wip"
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
        if (initialized) revert AlreadyInitialized();

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
        groupCreated = true;
        verificationType = _verificationType;

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
        if (!groupCreated) revert GroupNotCreated();
        if (!invited[msg.sender]) revert NotInvited();
        if (members[msg.sender]) revert AlreadyMember();

        invited[msg.sender] = false;
        members[msg.sender] = true;

        emit UserJoined(msg.sender);
    }

    /* -------------------------------------------------------------------------- */
    /*                              SIMPLE DEPOSIT                                 */
    /* -------------------------------------------------------------------------- */

    function deposit(uint256 amount) external {
        if (!members[msg.sender]) revert NotMember();

        // only require SELF if selected
        if (verificationType == VerificationType.SELF) {
            if (!verifiedUsers[msg.sender]) revert NotVerified();
        }

        require(usdc.transferFrom(msg.sender, address(this), amount));
        emit Deposit(msg.sender, amount);
    }

    /* -------------------------------------------------------------------------- */
    /*                          SELF VERIFICATION HOOK                            */
    /* -------------------------------------------------------------------------- */

    function customVerificationHook(
        ISelfVerificationRoot.GenericDiscloseOutputV2 memory output,
        bytes memory
    ) internal override {
        address user = address(uint160(output.userIdentifier));

        // only members can verify
        if (!members[user]) {
            // do nothing, ignore non-members
            return;
        }

        verifiedUsers[user] = true;
        emit VerificationCompleted(user);
    }

    function getConfigId(
        bytes32, /* destinationChainId */
        bytes32, /* userIdentifier */
        bytes memory /* userDefinedData */
    ) public view override returns (bytes32) {
        return verificationConfigId;
    }
}
