# Verified Title Deeds NFT

This project provides a Clarity smart contract for managing real estate titles as Non-Fungible Tokens (NFTs) on the Stacks blockchain. It's designed to mirror the security and procedural requirements of traditional property registries.

## Core Features

- **Property as NFT:** Each unique property is minted as an NFT, creating a singular, digitally-native record of ownership.
- **Rich Metadata:** The contract stores essential property data on-chain, such as the legal description, jurisdiction, and property ID.
- **Verified Transfers:** To enhance security and prevent fraudulent transfers, each ownership change must be co-signed or verified by a designated `legal-verifier` principal. This simulates the role of a land registry office or title company.
- **Admin Controls:** The contract deployer has administrative rights to mint new titles and manage the designated legal verifier.
- **On-Chain History:** Every transfer and data update is immutably recorded on the Stacks blockchain, providing a transparent and auditable history of title.

## How It Works

1.  **Minting:** The contract owner mints a new NFT representing a property, assigning it to the initial owner and populating its legal data.
2.  **Transfer Initiation:** The current owner initiates a transfer to a new owner.
3.  **Legal Verification:** The designated `legal-verifier` calls a function to approve the transfer.
4.  **Transfer Execution:** Once verified, the standard `transfer` function can be successfully executed, changing the owner of the NFT.