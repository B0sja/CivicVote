;; CivicVote - Decentralized Community Governance Platform
(define-fungible-token governance-token)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-unauthorized (err u401))
(define-constant err-insufficient-balance (err u402))
(define-constant err-proposal-not-found (err u403))
(define-constant err-already-voted (err u404))
(define-constant err-voting-closed (err u405))
(define-constant err-voting-active (err u406))
(define-constant err-invalid-title (err u407))
(define-constant err-invalid-description (err u408))
(define-constant err-invalid-duration (err u409))
(define-constant err-invalid-amount (err u410))

;; Storage
(define-map proposals uint {
  creator: principal,
  title: (string-utf8 128),
  description: (string-utf8 512),
  votes-for: uint,
  votes-against: uint,
  status: (string-utf8 16),
  end-block: uint
})

(define-map votes {proposal-id: uint, voter: principal} bool)
(define-map member-tokens principal uint)
(define-data-var proposal-counter uint u0)
(define-data-var min-proposal-stake uint u10000000) ;; 10 tokens
(define-data-var voting-duration uint u288) ;; ~2 days in blocks

;; Distribute governance tokens to community members
(define-public (distribute-tokens (amount uint))
  (begin
    ;; Validate inputs
    (asserts! (> amount u0) err-invalid-amount)
    
    ;; Check authorization
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    
    ;; Mint tokens
    (try! (ft-mint? governance-token amount tx-sender))
    
    ;; Update member tokens
    (ok (map-set member-tokens tx-sender amount))
  )
)

;; Create new governance proposal
(define-public (create-proposal (title (string-utf8 128)) (description (string-utf8 512)))
  (let
    ((creator tx-sender)
     (proposal-id (var-get proposal-counter))
     (token-balance (default-to u0 (map-get? member-tokens creator))))
    
    ;; Validate inputs
    (asserts! (> (len title) u0) err-invalid-title)
    (asserts! (> (len description) u0) err-invalid-description)
    
    ;; Check if creator has enough tokens
    (asserts! (>= token-balance (var-get min-proposal-stake)) err-insufficient-balance)
    
    ;; Store the proposal
    (map-set proposals proposal-id {
      creator: creator,
      title: title,
      description: description,
      votes-for: u0,
      votes-against: u0,
      status: u"active",
      end-block: (+ burn-block-height (var-get voting-duration))
    })
    
    ;; Increment proposal counter
    (var-set proposal-counter (+ proposal-id u1))
    
    (ok proposal-id)))

;; Cast vote on proposal
(define-public (cast-vote (proposal-id uint) (support bool))
  (let
    ((proposal (unwrap! (map-get? proposals proposal-id) err-proposal-not-found))
     (voter tx-sender)
     (token-balance (default-to u0 (map-get? member-tokens voter)))
     (vote-key {proposal-id: proposal-id, voter: voter}))
    
    ;; Check if voting is still active
    (asserts! (< burn-block-height (get end-block proposal)) err-voting-closed)
    
    ;; Check if voter hasn't already voted
    (asserts! (is-none (map-get? votes vote-key)) err-already-voted)
    
    ;; Record the vote
    (map-set votes vote-key true)
    
    ;; Update vote counts
    (if support
      (ok (map-set proposals proposal-id (merge proposal {votes-for: (+ (get votes-for proposal) token-balance)})))
      (ok (map-set proposals proposal-id (merge proposal {votes-against: (+ (get votes-against proposal) token-balance)})))
    )
  )
)

;; Finalize proposal voting
(define-public (finalize-proposal (proposal-id uint))
  (let
    ((proposal (unwrap! (map-get? proposals proposal-id) err-proposal-not-found)))
    
    ;; Check if voting period has ended
    (asserts! (>= burn-block-height (get end-block proposal)) err-voting-active)
    
    ;; Update proposal status
    (ok (map-set proposals proposal-id 
      (merge proposal 
        {status: (if (> (get votes-for proposal) (get votes-against proposal)) u"passed" u"rejected")})))
  )
)

;; Get proposal details
(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals proposal-id))

;; Get member token balance
(define-read-only (get-member-balance (member principal))
  (default-to u0 (map-get? member-tokens member)))

;; Transfer governance tokens
(define-public (transfer-governance-tokens (amount uint) (recipient principal))
  (let
    ((sender tx-sender)
     (sender-balance (default-to u0 (map-get? member-tokens sender)))
     (recipient-balance (default-to u0 (map-get? member-tokens recipient))))
    
    ;; Validate inputs
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (not (is-eq recipient 'SP000000000000000000002Q6VF78)) err-unauthorized)
    
    ;; Check if sender has enough tokens
    (asserts! (>= sender-balance amount) err-insufficient-balance)
    
    ;; Update balances
    (map-set member-tokens sender (- sender-balance amount))
    (ok (map-set member-tokens recipient (+ recipient-balance amount)))
  )
)
