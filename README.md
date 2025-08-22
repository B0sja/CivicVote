# CivicVote - Decentralized Community Governance Platform

A blockchain-based governance system that enables transparent community decision-making through token-weighted voting.

## Features

- **Proposal Creation**: Community members can create governance proposals
- **Token-Weighted Voting**: Voting power proportional to governance token holdings
- **Transparent Process**: All votes and proposals recorded on-chain
- **Time-Limited Voting**: Proposals have defined voting periods
- **Automatic Finalization**: Proposals automatically finalized after voting period

## Smart Contract Functions

### Public Functions
- `distribute-tokens(amount)` - Distribute governance tokens to members
- `create-proposal(title, description)` - Create new governance proposal
- `cast-vote(proposal-id, support)` - Vote on active proposals
- `finalize-proposal(proposal-id)` - Finalize completed proposals
- `transfer-governance-tokens(amount, recipient)` - Transfer tokens between members

### Read-Only Functions
- `get-proposal(proposal-id)` - Retrieve proposal details
- `get-member-balance(member)` - Check member's token balance

## Getting Started

1. Deploy the contract to Stacks blockchain
2. Distribute governance tokens to community members
3. Members can create proposals and participate in voting
4. Proposals are automatically finalized based on vote outcomes

## Requirements

- Minimum 10 governance tokens required to create proposals
- Voting period: ~2 days (288 blocks)
- Token-weighted voting system ensures proportional representation
\`\`\`

```clarity file="project-2-carbon/contracts/eco-credits.clar"
;; EcoCredits - Carbon Offset and Environmental Impact Tracking
(define-fungible-token carbon-credit)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-access-denied (err u601))
(define-constant err-insufficient-credits (err u602))
(define-constant err-project-not-found (err u603))
(define-constant err-already-verified (err u604))
(define-constant err-verification-expired (err u605))
(define-constant err-verification-pending (err u606))
(define-constant err-invalid-project-name (err u607))
(define-constant err-invalid-location (err u608))
(define-constant err-invalid-methodology (err u609))
(define-constant err-invalid-credit-amount (err u610))

;; Storage
(define-map carbon-projects uint {
  developer: principal,
  project-name: (string-utf8 128),
  location: (string-utf8 256),
  methodology: (string-utf8 128),
  verified-credits: uint,
  disputed-credits: uint,
  status: (string-utf8 16),
  verification-deadline: uint
})

(define-map verifications {project-id: uint, auditor: principal} bool)
(define-map credit-balances principal uint)
(define-data-var project-counter uint u0)
(define-data-var min-audit-stake uint u15000000) ;; 15 credits
(define-data-var verification-period uint u576) ;; ~4 days in blocks

;; Issue carbon credits for environmental projects
(define-public (issue-credits (credit-amount uint))
  (begin
    ;; Validate inputs
    (asserts! (> credit-amount u0) err-invalid-credit-amount)
    
    ;; Check authorization
    (asserts! (is-eq tx-sender contract-owner) err-access-denied)
    
    ;; Mint credits
    (try! (ft-mint? carbon-credit credit-amount tx-sender))
    
    ;; Update credit balances
    (ok (map-set credit-balances tx-sender credit-amount))
  )
)

;; Register carbon offset project
(define-public (register-project (project-name (string-utf8 128)) (location (string-utf8 256)) (methodology (string-utf8 128)))
  (let
    ((developer tx-sender)
     (project-id (var-get project-counter))
     (credit-balance (default-to u0 (map-get? credit-balances developer))))
    
    ;; Validate inputs
    (asserts! (> (len project-name) u0) err-invalid-project-name)
    (asserts! (> (len location) u0) err-invalid-location)
    (asserts! (> (len methodology) u0) err-invalid-methodology)
    
    ;; Check if developer has enough credits
    (asserts! (>= credit-balance (var-get min-audit-stake)) err-insufficient-credits)
    
    ;; Store the project record
    (map-set carbon-projects project-id {
      developer: developer,
      project-name: project-name,
      location: location,
      methodology: methodology,
      verified-credits: u0,
      disputed-credits: u0,
      status: u"pending",
      verification-deadline: (+ burn-block-height (var-get verification-period))
    })
    
    ;; Increment project counter
    (var-set project-counter (+ project-id u1))
    
    (ok project-id)))

;; Audit carbon project
(define-public (audit-project (project-id uint) (is-valid bool))
  (let
    ((project (unwrap! (map-get? carbon-projects project-id) err-project-not-found))
     (auditor tx-sender)
     (credit-balance (default-to u0 (map-get? credit-balances auditor)))
     (verification-key {project-id: project-id, auditor: auditor}))
    
    ;; Check if verification period is active
    (asserts! (&lt; burn-block-height (get verification-deadline project)) err-verification-expired)
    
    ;; Check if auditor hasn't already verified
    (asserts! (is-none (map-get? verifications verification-key)) err-already-verified)
    
    ;; Record the verification
    (map-set verifications verification-key true)
    
    ;; Update verification counts
    (if is-valid
      (ok (map-set carbon-projects project-id (merge project {verified-credits: (+ (get verified-credits project) credit-balance)})))
      (ok (map-set carbon-projects project-id (merge project {disputed-credits: (+ (get disputed-credits project) credit-balance)})))
    )
  )
)

;; Finalize project verification
(define-public (finalize-project (project-id uint))
  (let
    ((project (unwrap! (map-get? carbon-projects project-id) err-project-not-found)))
    
    ;; Check if verification period has ended
    (asserts! (>= burn-block-height (get verification-deadline project)) err-verification-pending)
    
    ;; Update project status
    (ok (map-set carbon-projects project-id 
      (merge project 
        {status: (if (> (get verified-credits project) (get disputed-credits project)) u"approved" u"rejected")})))
  )
)

;; Get project details
(define-read-only (get-project (project-id uint))
  (map-get? carbon-projects project-id))

;; Get credit balance
(define-read-only (get-credit-balance (holder principal))
  (default-to u0 (map-get? credit-balances holder)))

;; Transfer carbon credits
(define-public (transfer-credits (credit-amount uint) (recipient principal))
  (let
    ((sender tx-sender)
     (sender-balance (default-to u0 (map-get? credit-balances sender)))
     (recipient-balance (default-to u0 (map-get? credit-balances recipient))))
    
    ;; Validate inputs
    (asserts! (> credit-amount u0) err-invalid-credit-amount)
    (asserts! (not (is-eq recipient 'SP000000000000000000002Q6VF78)) err-access-denied)
    
    ;; Check if sender has enough credits
    (asserts! (>= sender-balance credit-amount) err-insufficient-credits)
    
    ;; Update balances
    (map-set credit-balances sender (- sender-balance credit-amount))
    (ok (map-set credit-balances recipient (+ recipient-balance credit-amount)))
  )
)
