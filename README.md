# VIGIX Smart Contract

Official smart contract for VIGIX, the access and fee layer of Vestige Index.

---

## Overview

VIGIX is designed as a utility layer within Vestige Index.

Its primary purpose is to:

- Reduce or remove execution fees
- Provide access to protocol-level features
- Align incentives between users and execution quality

VIGIX does not custody funds and does not act as an intermediary.

---

## Key Properties

- Non-custodial design
- Wallet-native execution
- No fund custody by Vestige Index
- Transparent fee mechanics
- On-chain verifiable behavior

All interactions are executed directly from the user’s wallet.

---

## Fee Model

Vestige Index applies a standard execution fee:

- 0.05% per swap

Users holding at least $100 worth of VIGIX may unlock:

- 0% execution fees

Fee logic is fully transparent and enforced on-chain.

---

## Transparency

This repository provides full visibility into the VIGIX smart contract.

- Contract logic is open-source
- No hidden execution layers
- All mechanics can be independently verified

---

## Scope

This repository includes:

- VIGIX smart contract

This repository does NOT include:

- Vestige Index frontend
- Routing engine
- Aggregation logic
- Execution infrastructure

---

## Security

- Non-custodial architecture
- No asset storage within Vestige Index
- All actions require explicit wallet signature
- Users retain full control of funds at all times

## Contract

Deployed contract address:

(0xea1989dDc9F7db000347F6Ac14C63fd395B6EDAd)

---

## Disclaimer

This software is provided "as is", without warranty of any kind.

Use at your own risk.

---

## Trademark Notice

VIGIX and Vestige Index are trademarks of Vestige Index.

This repository contains the open-source smart contract only.  
The name, branding, and associated assets are not included under the MIT License.

You are not permitted to use the name "VIGIX", "Vestige Index", or any similar branding
to represent a derivative or modified version of this project without explicit permission.

All rights to the Vestige Index brand and identity are reserved.
## Minting Policy

VIGIX cannot be manually minted by the owner.

New VIGIX is only minted when a user buys through the contract, according to the bonding curve logic.

VIGIX is burned when a user sells through the contract.

The owner cannot arbitrarily create tokens.

