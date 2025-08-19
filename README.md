# BlockSignal: Cross-Chain Token Bridge for Stacks

> A secure and decentralized cross-chain token bridge with validator staking, built for the Stacks blockchain.

## 🏗️ Architecture

BlockSignal enables secure token transfers between Stacks and other blockchains through:

- Multi-token support using SIP-010 fungible token standard
- Validator staking mechanism for consensus
- Bridge request/claim workflow with cryptographic proofs
- Dynamic fee system and emergency controls

## 🔑 Key Features

- **Multi-Token Support**: Bridge any SIP-010 compatible token
- **Validator Staking**: Secure consensus through staked validators
- **Dynamic Fees**: Configurable fee structure (default 0.5%)
- **Security Controls**: 
  - Pausable operations
  - Owner-controlled admin functions
  - Double-claim prevention
  - Validator threshold requirements

## 📋 Contract Functions

### Admin Functions
```clarity
(define-public (pause))
(define-public (unpause))
(define-public (set-bridge-fee (bps uint)))
(define-public (set-bridge-recipient (who principal)))
```

### Validator Management
```clarity
(define-public (register-validator (token-contract <ft-trait>) (stake uint)))
(define-public (deactivate-validator))
```

### Bridge Operations
```clarity
(define-public (register-bridge-token (token principal)))
(define-public (request-bridge (token <ft-trait>) (amount uint) 
               (dest-chain (string-ascii 20)) (dest-address (string-ascii 64))))
(define-public (claim-bridge (token <ft-trait>) (req-id uint) (proof-hash (buff 32))))
```

## 🔒 Security Features

1. **Access Control**
   - Owner-only administrative functions
   - Active validator checks
   - Pausable operations

2. **Bridge Security**
   - Minimum stake requirements
   - Bridge request validation
   - Claim verification system
   - Double-spend prevention

3. **Token Safety**
   - Registered token whitelist
   - Fee calculation checks
   - Balance validations

## 🚀 Getting Started

1. Deploy the contract to Stacks blockchain
2. Register bridge tokens using `register-bridge-token`
3. Set up validators with `register-validator`
4. Configure bridge fees using `set-bridge-fee`
5. Users can begin bridging tokens with `request-bridge`

## 📝 Example Usage

```clarity
;; Register a validator with 1000 token stake
(contract-call? .blocksignal register-validator 'SP2PABAF9FTAJYNFZH93XENAJ8FVY99RRM50D2JG9.wrapped-stx u1000)

;; Bridge 100 tokens to Ethereum
(contract-call? .blocksignal request-bridge 'SP2PABAF9FTAJYNFZH93XENAJ8FVY99RRM50D2JG9.wrapped-stx u100 "ethereum" "0x1234...")
```

## 🛠️ Development



---
*Built for Stacks Smart Contract Competition 2025*
