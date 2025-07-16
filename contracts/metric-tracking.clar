;; Metric Tracking Contract
;; Tracks and records performance metrics

;; Constants
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-METRIC-NOT-FOUND (err u301))
(define-constant ERR-INVALID-INPUT (err u302))
(define-constant ERR-INVALID-VALUE (err u303))

;; Data Variables
(define-data-var next-metric-id uint u1)
(define-data-var next-measurement-id uint u1)

;; Data Maps
(define-map metrics
  { metric-id: uint }
  {
    scorecard-id: uint,
    objective-id: uint,
    name: (string-ascii 50),
    description: (string-ascii 100),
    unit: (string-ascii 20),
    metric-type: uint,
    frequency: uint,
    creation-block: uint,
    is-active: bool
  }
)

(define-map measurements
  { measurement-id: uint }
  {
    metric-id: uint,
    value: uint,
    measurement-block: uint,
    recorded-by: principal,
    notes: (string-ascii 100)
  }
)

(define-map metric-summaries
  { metric-id: uint }
  {
    total-measurements: uint,
    latest-value: uint,
    highest-value: uint,
    lowest-value: uint,
    average-value: uint,
    last-updated: uint
  }
)

;; Public Functions

;; Create a new metric
(define-public (create-metric
  (scorecard-id uint)
  (objective-id uint)
  (name (string-ascii 50))
  (description (string-ascii 100))
  (unit (string-ascii 20))
  (metric-type uint)
  (frequency uint)
)
  (let
    (
      (metric-id (var-get next-metric-id))
    )
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    (asserts! (> (len unit) u0) ERR-INVALID-INPUT)
    (asserts! (<= metric-type u3) ERR-INVALID-INPUT)
    (asserts! (> frequency u0) ERR-INVALID-INPUT)

    (map-set metrics
      { metric-id: metric-id }
      {
        scorecard-id: scorecard-id,
        objective-id: objective-id,
        name: name,
        description: description,
        unit: unit,
        metric-type: metric-type,
        frequency: frequency,
        creation-block: block-height,
        is-active: true
      }
    )

    (map-set metric-summaries
      { metric-id: metric-id }
      {
        total-measurements: u0,
        latest-value: u0,
        highest-value: u0,
        lowest-value: u0,
        average-value: u0,
        last-updated: block-height
      }
    )

    (var-set next-metric-id (+ metric-id u1))
    (ok metric-id)
  )
)

;; Record a measurement
(define-public (record-measurement (metric-id uint) (value uint) (notes (string-ascii 100)))
  (let
    (
      (measurement-id (var-get next-measurement-id))
      (metric-data (unwrap! (map-get? metrics { metric-id: metric-id }) ERR-METRIC-NOT-FOUND))
      (summary-data (unwrap! (map-get? metric-summaries { metric-id: metric-id }) ERR-METRIC-NOT-FOUND))
    )
    (asserts! (get is-active metric-data) ERR-NOT-AUTHORIZED)

    (map-set measurements
      { measurement-id: measurement-id }
      {
        metric-id: metric-id,
        value: value,
        measurement-block: block-height,
        recorded-by: tx-sender,
        notes: notes
      }
    )

    (let
      (
        (new-total (+ (get total-measurements summary-data) u1))
        (new-highest (if (> value (get highest-value summary-data)) value (get highest-value summary-data)))
        (new-lowest (if (or (is-eq (get total-measurements summary-data) u0) (< value (get lowest-value summary-data))) value (get lowest-value summary-data)))
        (new-average (/ (+ (* (get average-value summary-data) (get total-measurements summary-data)) value) new-total))
      )
      (map-set metric-summaries
        { metric-id: metric-id }
        {
          total-measurements: new-total,
          latest-value: value,
          highest-value: new-highest,
          lowest-value: new-lowest,
          average-value: new-average,
          last-updated: block-height
        }
      )
    )

    (var-set next-measurement-id (+ measurement-id u1))
    (ok measurement-id)
  )
)

;; Update metric status
(define-public (update-metric-status (metric-id uint) (is-active bool))
  (let
    (
      (metric-data (unwrap! (map-get? metrics { metric-id: metric-id }) ERR-METRIC-NOT-FOUND))
    )
    (map-set metrics
      { metric-id: metric-id }
      (merge metric-data { is-active: is-active })
    )

    (ok true)
  )
)

;; Read-only Functions

;; Get metric by ID
(define-read-only (get-metric (metric-id uint))
  (map-get? metrics { metric-id: metric-id })
)

;; Get measurement by ID
(define-read-only (get-measurement (measurement-id uint))
  (map-get? measurements { measurement-id: measurement-id })
)

;; Get metric summary
(define-read-only (get-metric-summary (metric-id uint))
  (map-get? metric-summaries { metric-id: metric-id })
)

;; Calculate performance score
(define-read-only (calculate-performance-score (metric-id uint) (target-value uint))
  (match (map-get? metric-summaries { metric-id: metric-id })
    summary-data
      (let
        (
          (current-value (get latest-value summary-data))
          (score (if (> target-value u0) (/ (* current-value u100) target-value) u0))
        )
        (some (if (> score u100) u100 score))
      )
    none
  )
)

;; Get next metric ID
(define-read-only (get-next-metric-id)
  (var-get next-metric-id)
)
