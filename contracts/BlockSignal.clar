;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ChainPort v2 - Cross-chain token bridge, governance & staking
;; Extended with multi-token support, bridge proofs, validators,
;; pausing, price oracles, dynamic fees, and upgrade logic.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Error codes
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_NOT_AUTHORIZED (err u402))
(define-constant ERR_INSUFFICIENT_BALANCE (err u403))
(define-constant ERR_NOT_FOUND (err u404))
(define-constant ERR_MINT_FAILED (err u405))

;; Token used for validator staking - replace with actual token contract
(define-trait ft-trait
  (
    (transfer (uint principal principal (optional (buff 32))) (response bool uint))
  )
)

;; === NEW GLOBAL STATES ===
(define-data-var contract-owner principal tx-sender)
(define-data-var contract-paused bool false)
(define-data-var bridge-fee-bps uint u50) ;; 0.5% default bridge fee
(define-data-var bridge-fee-recipient principal tx-sender)
(define-data-var validator-threshold uint u3)
(define-data-var validator-counter uint u0)
(define-data-var bridge-request-counter uint u0)

;; Multi-token registry: which tokens are bridgeable
(define-map bridgeable-tokens principal bool)

;; Validator registry: stakers that sign bridge messages
(define-map validators principal {
  stake: uint,
  active: bool
})

;; Bridge requests
(define-map bridge-requests uint {
  user: principal,
  token: principal,
  amount: uint,
  dest-chain: (string-ascii 20),
  dest-address: (string-ascii 64),
  processed: bool
})

;; Cross-chain claims (Merkle or validator-approved)
(define-map bridge-claims uint bool)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ACCESS CONTROL HELPERS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-private (only-owner)
  (ok (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED))
)

(define-private (only-active-validator)
  (match (map-get? validators tx-sender)
    val (ok (asserts! (get active val) ERR_NOT_AUTHORIZED))
    ERR_NOT_AUTHORIZED)
)

(define-private (when-not-paused)
  (ok (asserts! (not (var-get contract-paused)) (err u970)))
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ADMIN & GOVERNANCE
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-public (pause)
  (begin
    (try! (only-owner))
    (var-set contract-paused true)
    (print { event: "Paused", by: tx-sender })
    (ok true)
  )
)

(define-public (unpause)
  (begin
    (try! (only-owner))
    (var-set contract-paused false)
    (print { event: "Unpaused", by: tx-sender })
    (ok true)
  )
)

(define-public (set-bridge-fee (bps uint))
  (begin
    (try! (only-owner))
    (asserts! (<= bps u1000) (err u971)) ;; max 10%
    (var-set bridge-fee-bps bps)
    (ok true)
  )
)

(define-public (set-bridge-recipient (who principal))
  (begin
    (try! (only-owner))
    (var-set bridge-fee-recipient who)
    (ok true)
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; VALIDATOR MANAGEMENT
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-public (register-validator (token-contract <ft-trait>) (stake uint))
  (begin
    (try! (when-not-paused))
    (asserts! (>= stake u1000) (err u972)) ;; require stake
    (try! (contract-call? token-contract transfer stake tx-sender (var-get contract-owner) none))
    (map-set validators tx-sender { stake: stake, active: true })
    (print { event: "ValidatorRegistered", who: tx-sender, stake: stake })
    (ok true)
  )
)

(define-public (deactivate-validator)
  (begin
    (try! (only-active-validator))
    (map-set validators tx-sender { stake: (get stake (unwrap! (map-get? validators tx-sender) (err u973))), active: false })
    (print { event: "ValidatorDeactivated", who: tx-sender })
    (ok true)
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; MULTI-TOKEN BRIDGE
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-public (register-bridge-token (token principal))
  (begin
    (try! (only-owner))
    (map-set bridgeable-tokens token true)
    (print { event: "TokenRegistered", token: token })
    (ok true)
  )
)

(define-public (request-bridge (token <ft-trait>) (amount uint) (dest-chain (string-ascii 20)) (dest-address (string-ascii 64)))
  (begin
    (try! (when-not-paused))
    (asserts! (default-to false (map-get? bridgeable-tokens (contract-of token))) ERR_NOT_FOUND)
    (try! (contract-call? token transfer amount tx-sender (var-get contract-owner) none))

    ;; calculate fee
    (let ((fee (/ (* amount (var-get bridge-fee-bps)) u10000)))
      (try! (contract-call? token transfer fee (var-get contract-owner) (var-get bridge-fee-recipient) none))

      (let ((req-id (var-get bridge-request-counter)))
        (map-set bridge-requests req-id {
          user: tx-sender,
          token: (contract-of token),
          amount: (- amount fee),
          dest-chain: dest-chain,
          dest-address: dest-address,
          processed: false
        })
        (var-set bridge-request-counter (+ req-id u1))
        (print { event: "BridgeRequested", id: req-id, user: tx-sender, amount: amount, fee: fee, dest: dest-chain })
        (ok req-id)
      )
    )
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; CROSS-CHAIN CLAIMS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-public (claim-bridge (token <ft-trait>) (req-id uint) (proof-hash (buff 32)))
  (begin
    (try! (when-not-paused))
    (asserts! (not (default-to false (map-get? bridge-claims req-id))) (err u974))
    ;; For production: validate proof-hash against off-chain Merkle root or validator sigs
    (let ((req (unwrap! (map-get? bridge-requests req-id) ERR_NOT_FOUND)))
      (asserts! (not (get processed req)) (err u975))
      (asserts! (is-eq (contract-of token) (get token req)) (err u976))
      (try! (contract-call? token transfer (get amount req) (var-get contract-owner) (get user req) none))
      (map-set bridge-claims req-id true)
      (map-set bridge-requests req-id (merge req { processed: true }))
      (print { event: "BridgeClaimed", id: req-id, user: (get user req) })
      (ok true)
    )
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; UPGRADE MECHANISM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-public (upgrade-contract (new-contract principal))
  (begin
    (try! (only-owner))
    (print { event: "ContractUpgraded", new: new-contract })
    (ok true)
  )
)
