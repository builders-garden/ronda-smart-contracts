// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IENSReverseRegistrar} from "./interfaces/IENSReverseRegistrar.sol";
import {RondaProtocol, VerificationType} from "./RondaProtocol.sol";
import {SelfUtils} from "@selfxyz/contracts/libraries/SelfUtils.sol";

/**
 * @title RondaProtocolFactory
 * @notice Factory contract for deploying RondaProtocol instances using CREATE2 with ENS reverse record support
 * @dev This factory implements IENSReverseRegistrar to act as its own ENS Reverse Registrar
  */
contract RondaProtocolFactory is IENSReverseRegistrar {
    /**
     * @notice Struct to hold deployment parameters
     */
    struct DeploymentParams {
        string name; // Name for the group (used in ENS subdomain)
        string scopeSeed;
        SelfUtils.UnformattedVerificationConfigV2 verificationConfig;
        address creator;
        uint256 depositFrequency;
        uint256 borrowFrequency;
        uint256 recurringAmount;
        uint256 operationCounter;
        VerificationType verificationType;
        uint256 minAge;
        string[] allowedNationalities;
        string requiredGender;
        address[] usersToInvite;
    }
    // Immutable addresses set at deployment
    address public immutable usdcAddress;
    address public immutable identityVerificationHubV2Address;
    address public immutable aavePoolAddress;
    address public immutable aaveUsdcAddress;
    address public immutable feeRecipient;
    address public immutable operator; // Address authorized to call distributeFunds
    
    // ENS configuration
    string public mainEnsName; // e.g., "ronda.eth"
    
    // ENS Reverse Registrar storage (this contract implements IENSReverseRegistrar)
    // Mapping from address to ENS name
    mapping(address => string) private reverseRecords;
    
    // Group counter for assigning IDs
    uint256 public groupCounter;
    
    // Mapping from group ID to contract address
    mapping(uint256 => address) public groupIdToContract;
    
    // Mapping to track deployed contracts
    mapping(address => bool) public isDeployed;
    
    // Array of all deployed contract addresses
    address[] public deployedContracts;
    
    // Mapping from user address to nonce (for salt generation)
    mapping(address => uint256) public userNonce;
    
    // Custom errors
    error InvalidUSDCAddress();
    error InvalidIdentityVerificationHubAddress();
    error InvalidAavePoolAddress();
    error InvalidAaveUSDCAddress();
    error InvalidFeeRecipient();
    error InvalidOperatorAddress();
    error InvalidENSReverseRegistrar();
    error EmptyENSName();
    
    // Event emitted when a new RondaProtocol is deployed
    event RondaProtocolDeployed(
        uint256 indexed groupId,
        address indexed rondaProtocol,
        address indexed deployer,
        bytes32 salt,
        string ensName
    );
    
    /**
     * @notice Constructor for RondaProtocolFactory
     * @param _usdcAddress The address of the USDC token (constant for all deployments)
     * @param _identityVerificationHubV2Address The address of the Identity Verification Hub V2 (constant for all deployments)
     * @param _aavePoolAddress The address of the Aave Pool (constant for all deployments)
     * @param _aaveUsdcAddress The address of the Aave USDC aToken (constant for all deployments)
     * @param _feeRecipient The address to receive excess funds from interest (constant for all deployments)
     * @param _operator The address authorized to call distributeFunds on deployed contracts (constant for all deployments)
     * @param _mainEnsName The main ENS name (e.g., "ronda.eth") for subdomain creation
     * @dev This factory implements IENSReverseRegistrar, so it acts as its own ENS Reverse Registrar
     */
    constructor(
        address _usdcAddress,
        address _identityVerificationHubV2Address,
        address _aavePoolAddress,
        address _aaveUsdcAddress,
        address _feeRecipient,
        address _operator,
        string memory _mainEnsName
    ) {
        if (_usdcAddress == address(0)) revert InvalidUSDCAddress();
        if (_identityVerificationHubV2Address == address(0)) revert InvalidIdentityVerificationHubAddress();
        if (_aavePoolAddress == address(0)) revert InvalidAavePoolAddress();
        if (_aaveUsdcAddress == address(0)) revert InvalidAaveUSDCAddress();
        if (_feeRecipient == address(0)) revert InvalidFeeRecipient();
        if (_operator == address(0)) revert InvalidOperatorAddress();
        // Main ENS name is optional - if empty, ENS registration will be skipped
        if (bytes(_mainEnsName).length == 0) revert EmptyENSName();
        
        usdcAddress = _usdcAddress;
        identityVerificationHubV2Address = _identityVerificationHubV2Address;
        aavePoolAddress = _aavePoolAddress;
        aaveUsdcAddress = _aaveUsdcAddress;
        feeRecipient = _feeRecipient;
        operator = _operator;
        mainEnsName = _mainEnsName;
    }
    
    /**
     * @notice Computes the address of a RondaProtocol contract that would be deployed with CREATE2
     * @param _creator The creator address
     * @param _nonce The nonce for this creator
     * @return The computed address
     */
    function computeAddress(address _creator, uint256 _nonce) public view returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(_creator, _nonce));
        bytes memory bytecode = type(RondaProtocol).creationCode;
        bytes32 bytecodeHash = keccak256(bytecode);
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            bytecodeHash
        )))));
    }
    
    /**
     * @notice Internal function to deploy and initialize a contract
     * @param salt The salt for CREATE2 deployment
     * @param groupId The group ID to assign
     * @param params The deployment parameters
     * @return The deployed contract address
     */
    function _deployAndInitialize(
        bytes32 salt,
        uint256 groupId,
        DeploymentParams memory params
    ) internal returns (address) {
        bytes memory bytecode = type(RondaProtocol).creationCode;
        address deployed;
        assembly {
            deployed := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        if (deployed == address(0)) {
            revert("CREATE2 deployment failed");
        }
        
        RondaProtocol protocol = RondaProtocol(deployed);
        
        // Build the full ENS subdomain (e.g., "mygroup.ronda.eth")
        string memory fullEnsSubdomain = string(abi.encodePacked(params.name, ".", mainEnsName));
        
        // Initialize the contract
        protocol.initialize(
            groupId,
            fullEnsSubdomain,
            usdcAddress,
            identityVerificationHubV2Address,
            aavePoolAddress,
            aaveUsdcAddress,
            feeRecipient,
            operator,
            params.scopeSeed,
            params.verificationConfig
        );
        
        // Create the group
        protocol.createGroup(
            params.creator,
            params.depositFrequency,
            params.borrowFrequency,
            params.recurringAmount,
            params.operationCounter,
            params.verificationType,
            params.minAge,
            params.allowedNationalities,
            params.requiredGender,
            params.usersToInvite
        );
        
        // Set ENS reverse record for the deployed contract (if ENS is configured)
        // Format: {name}.{mainEnsName} (e.g., "mygroup.ronda.eth")
        bytes32 ensNode = bytes32(0);
        if (bytes(mainEnsName).length > 0) {
            string memory subdomainName = string(abi.encodePacked(params.name, ".", mainEnsName));
            ensNode = this.setNameForAddr(deployed, subdomainName);
        }
        
        return deployed;
    }
    
    /**
     * @notice Internal helper to convert uint256 to string
     * @param value The uint256 value to convert
     * @return The string representation
     */
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
    
    /**
     * @notice Deploys a new RondaProtocol contract using CREATE2 and creates the group
     * @param params The deployment parameters
     * @return groupId The ID assigned to this group/contract
     * @return rondaProtocol The address of the deployed contract
     */
    function deployRondaProtocol(
        DeploymentParams memory params
    ) external returns (uint256 groupId, address rondaProtocol) {
        // Get and increment the nonce for this creator
        uint256 nonce = userNonce[params.creator]++;
        
        // Compute salt from creator address and nonce
        bytes32 salt = keccak256(abi.encodePacked(params.creator, nonce));
        
        // Compute the expected address
        address expectedAddress = computeAddress(params.creator, nonce);
        
        // Check if contract already exists at this address
        if (isDeployed[expectedAddress]) {
            revert("Contract already deployed at this address");
        }
        
        // Assign group ID
        groupId = groupCounter++;
        
        // Deploy, initialize, and create group
        rondaProtocol = _deployAndInitialize(salt, groupId, params);
        
        // Verify the deployed address matches expected
        if (rondaProtocol != expectedAddress) {
            revert("Deployed address mismatch");
        }
        
        // Mark as deployed and track
        isDeployed[rondaProtocol] = true;
        groupIdToContract[groupId] = rondaProtocol;
        deployedContracts.push(rondaProtocol);
        
        // Generate ENS name for event
        string memory ensName = string(abi.encodePacked(params.name, ".", mainEnsName));
        
        emit RondaProtocolDeployed(groupId, rondaProtocol, msg.sender, salt, ensName);
    }
    
    /**
     * @notice Gets the number of deployed contracts
     * @return The number of deployed contracts
     */
    function getDeployedCount() external view returns (uint256) {
        return deployedContracts.length;
    }
    
    /**
     * @notice Gets all deployed contract addresses
     * @return An array of all deployed contract addresses
     */
    function getAllDeployed() external view returns (address[] memory) {
        return deployedContracts;
    }
    
    /**
     * @notice Gets the contract address for a given group ID
     * @param _groupId The group ID
     * @return The contract address
     */
    function getContractByGroupId(uint256 _groupId) external view returns (address) {
        return groupIdToContract[_groupId];
    }
    
    // ============================================================================
    // IENSReverseRegistrar IMPLEMENTATION
    // ============================================================================
    
    /**
     * @notice Sets the `name()` record for the reverse ENS record associated with the calling account
     * @param name The name to set
     * @return The ENS node hash of the reverse record
     */
    function setName(string memory name) external returns (bytes32) {
        reverseRecords[msg.sender] = name;
        return _namehash(msg.sender);
    }
    
    /**
     * @notice Sets the `name()` record for the reverse ENS record associated with the addr provided account
     * @param addr The address to set the name for
     * @param name The name to set
     * @return The ENS node hash of the reverse record
     */
    function setNameForAddr(
        address addr,
        string memory name
    ) external returns (bytes32) {
        reverseRecords[addr] = name;
        return _namehash(addr);
    }
    
    /**
     * @notice Sets the `name()` record for the reverse ENS record associated with the contract provided that is owned with `Ownable`
     * @param contractAddr The address of the contract to set the name for (implementing Ownable)
     * @param name The name to set
     * @return The ENS node hash of the reverse record
     */
    function setNameForOwnableWithSignature(
        address contractAddr,
        address /* owner */,
        string calldata name,
        uint256[] memory /* coinTypes */,
        uint256 /* signatureExpiry */,
        bytes calldata /* signature */
    ) external returns (bytes32) {
        // Simplified implementation - just set the name
        reverseRecords[contractAddr] = name;
        return _namehash(contractAddr);
    }
    
    /**
     * @notice Sets the `name()` record for the reverse ENS record associated with the addr provided account using a signature
     * @param addr The address to set the name for
     * @param name The name of the reverse record
     * @return The ENS node hash of the reverse record
     */
    function setNameForAddrWithSignature(
        address addr,
        string calldata name,
        uint256[] calldata /* coinTypes */,
        uint256 /* signatureExpiry */,
        bytes calldata /* signature */
    ) external returns (bytes32) {
        // Simplified implementation - just set the name
        reverseRecords[addr] = name;
        return _namehash(addr);
    }
    
    /**
     * @notice Gets the ENS name for an address
     * @param addr The address to query
     * @return The ENS name associated with the address
     */
    function name(address addr) external view returns (string memory) {
        return reverseRecords[addr];
    }
    
    /**
     * @notice Internal helper to compute namehash for an address
     * @param addr The address to compute namehash for
     * @return The namehash
     */
    function _namehash(address addr) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(addr));
    }
}

