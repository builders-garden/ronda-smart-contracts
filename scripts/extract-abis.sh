#!/bin/bash

# Script to extract ABIs from compiled contracts
# Usage: ./scripts/extract-abis.sh

set -e

echo "Building contracts..."
forge build --skip test script

echo "Creating abis directory..."
mkdir -p abis

echo "Extracting RondaProtocol ABI..."
jq '.abi' out/RondaProtocol.sol/RondaProtocol.json > abis/RondaProtocol.json

echo "Extracting RondaProtocolFactory ABI..."
jq '.abi' out/RondaProtocolFactory.sol/RondaProtocolFactory.json > abis/RondaProtocolFactory.json

echo "✅ ABIs extracted successfully to abis/ directory:"
ls -lh abis/

