;; Quantum Computing Power Marketplace

;; Define constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-listed (err u102))
(define-constant err-insufficient-balance (err u103))
(define-constant err-insufficient-funds (err u104))
(define-constant err-invalid-input (err u105))

;; Define data maps
(define-map quantum-resources 
  { provider: principal, resource-id: uint }
  { computational-power: uint, price-per-unit: uint, available: bool })

(define-map user-balances principal uint)

;; Define variables
(define-data-var next-resource-id uint u1)
(define-data-var job-status (string-ascii 20) "queued")
(define-data-var demand-factor uint u100)
(define-data-var total-market-value uint u0)

;; List a quantum computing resource
(define-public (list-resource (computational-power uint) (price-per-unit uint))
  (if (or (is-eq computational-power u0) (is-eq price-per-unit u0))
      err-invalid-input
      (let
        ((resource-id (var-get next-resource-id))
         (market-value (* computational-power price-per-unit)))
        (map-insert quantum-resources 
          { provider: tx-sender, resource-id: resource-id }
          { computational-power: computational-power, price-per-unit: price-per-unit, available: true })
        (var-set next-resource-id (+ resource-id u1))
        (var-set total-market-value (+ (var-get total-market-value) market-value))
        (ok resource-id))))

;; Update resource availability
(define-public (update-resource-availability (resource-id uint) (available bool))
  (let
    ((resource (unwrap! (map-get? quantum-resources { provider: tx-sender, resource-id: resource-id }) err-not-found)))
    (map-set quantum-resources
      { provider: tx-sender, resource-id: resource-id }
      (merge resource { available: available }))
    (ok true)))

;; Book a quantum computing resource
(define-public (book-resource (provider principal) (resource-id uint) (units uint))
  (if (is-eq units u0)
      err-invalid-input
      (let
        ((resource (unwrap! (map-get? quantum-resources { provider: provider, resource-id: resource-id }) err-not-found))
         (total-cost (* (get price-per-unit resource) units)))
        (asserts! (get available resource) err-not-found)
        (asserts! (<= total-cost (default-to u0 (map-get? user-balances tx-sender))) err-insufficient-balance)
        (map-set user-balances tx-sender (- (default-to u0 (map-get? user-balances tx-sender)) total-cost))
        (map-set user-balances provider (+ (default-to u0 (map-get? user-balances provider)) total-cost))
        (ok true))))

;; Deposit balance
(define-public (deposit (amount uint))
  (if (is-eq amount u0)
      err-invalid-input
      (let
        ((sender tx-sender))
        (try! (stx-transfer? amount sender (as-contract tx-sender)))
        (map-set user-balances 
          sender 
          (+ (default-to u0 (map-get? user-balances sender)) amount))
        (ok true))))

;; Withdraw balance
(define-public (withdraw (amount uint))
  (let
    ((sender tx-sender)
     (current-balance (default-to u0 (map-get? user-balances sender))))
    (asserts! (>= current-balance amount) err-insufficient-funds)
    (try! (as-contract (stx-transfer? amount tx-sender sender)))
    (map-set user-balances
      sender
      (- current-balance amount))
    (ok true)))

;; Queue a job
(define-public (queue-job (provider principal) (resource-id uint) (job-data (string-ascii 1000)))
  (begin
    (try! (book-resource provider resource-id u1))
    (var-set job-status "queued")
    (print job-data)
    (ok true)))

;; Update job status (called by an authorized off-chain oracle)
(define-public (update-job-status (new-status (string-ascii 20)))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set job-status new-status)
    (ok true)))

;; Get job status
(define-read-only (get-job-status)
  (ok (var-get job-status)))

;; Update demand factor (called periodically by an authorized off-chain oracle)
(define-public (update-demand-factor (new-factor uint))
  (if (is-eq new-factor u0)
      err-invalid-input
      (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set demand-factor new-factor)
        (ok true))))

;; Get current price for a resource
(define-read-only (get-current-price (provider principal) (resource-id uint))
  (let
    ((resource (unwrap! (map-get? quantum-resources { provider: provider, resource-id: resource-id }) err-not-found))
     (base-price (get price-per-unit resource))
     (current-demand (var-get demand-factor)))
    (ok (* base-price (/ current-demand u100))))
)

;; Get user balance
(define-read-only (get-balance (user principal))
  (ok (default-to u0 (map-get? user-balances user))))

;; Get resource details for a specific provider and resource ID
(define-read-only (get-resource-details (provider principal) (resource-id uint))
  (map-get? quantum-resources { provider: provider, resource-id: resource-id }))

;; Calculate total market value (using cumulative tracking)
(define-read-only (get-total-market-value)
  (ok (var-get total-market-value)))