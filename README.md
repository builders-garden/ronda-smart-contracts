# Ronda Protocol

A decentralized rotating savings and credit association (ROSCA) protocol built on Celo, enabling groups to pool funds, and distribute funds to members on a rotating basis.

## Overview

Ronda Protocol allows users to create savings groups where members make periodic deposits in USDC. Funds are automatically deposited into Aave, and the interest earned serves as a revenue stream for the protocol developers. On a rotating basis, a randomly selected member receives the accumulated principal funds. The protocol integrates with Self Protocol for identity verification, ensuring only verified users can participate.

## Contracts

### RondaProtocol

Each `RondaProtocol` contract represents a single savings group. Key features:

- **Periodic Deposits**: Members deposit a fixed amount at regular intervals
- **Aave Integration**: Deposits are automatically supplied to Aave, with interest earned serving as protocol revenue
- **Identity Verification**: Uses Self Protocol for proof of personhood and optional age/nationality/gender verification
- **Fund Distribution**: Operator can distribute accumulated principal funds to eligible members
- **ENS Support**: Each group can have an associated ENS subdomain (e.g., `mygroup.ronda.eth`)

### RondaProtocolFactory

Factory contract for deploying `RondaProtocol` instances using CREATE2 for deterministic addresses:

- **CREATE2 Deployment**: Predictable contract addresses based on creator address and nonce
- **ENS Reverse Registrar**: Implements ENS reverse registrar interface to assign subdomains to deployed contracts
- **Group Management**: Tracks all deployed groups and assigns incremental group IDs

## Key Integrations

- **Celo**: Native deployment on Celo network using Circle USDC
- **Aave V3**: Automatic supply of deposits to Aave Pool, with interest serving as protocol revenue
- **Self Protocol**: Identity verification through Identity Verification Hub V2
- **ENS**: Human-readable addresses via Ethereum Name Service

## Contract Addresses

### Celo Mainnet

- **RondaProtocolFactory**: `0x3C8dFfF657093e03364f60848759454F459b03B6`

## Development

### Build

```bash
forge build
```

### Test

```bash
forge test
```

### Deploy Factory

```bash
forge script script/DeployFactory.s.sol:DeployFactory \
  --rpc-url https://forno.celo.org \
  --broadcast \
  --private-key $PRIVATE_KEY
```

### Deploy Ronda Protocol Instance

```bash
forge script script/DeployRonda.s.sol:DeployRonda \
  --rpc-url https://forno.celo.org \
  --broadcast \
  --private-key $PRIVATE_KEY
```

### Check Contract State

```bash
forge script script/CheckRondaState.s.sol:CheckRondaState \
  --rpc-url https://forno.celo.org
```

### Generate ABIs

```bash
npm run extract-abis
```

## Celo ETHGlobal Buenos Aires Submission

### Celo Integration

Ronda Protocol is deployed on Celo and integrates with Celo's Circle USDC for deposits and withdrawals. The protocol leverages Aave V3 on Celo to automatically supply pooled funds, with the interest earned serving as a revenue stream for the protocol developers (via the fee recipient address). All transactions utilize Celo's low-cost, fast finality blockchain infrastructure.

### Project Description

Ronda Protocol is a decentralized rotating savings and credit association that enables groups to pool funds, with Aave interest serving as protocol revenue, and distributes principal funds to members on a rotating basis with built-in identity verification.

### Team

The team is made by:

- Limone: product and fullstack developer. Worked on contracts, design and webapp developement. X: @limone_eth, Farcaster:@limone.eth
- Blackicon: fullstack developer. Worked on backend and webapp developement. X: @TBlackicon, Farcaster: @blackicon.eth
- Mide: fullstack developer. Worked on backend developement. X: @itsmide_eth, Farcaster: @itsmide.eth
