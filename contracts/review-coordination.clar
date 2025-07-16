;; Review Coordination Contract
;; Coordinates scorecard reviews and assessments

;; Constants
(define-constant ERR-NOT-AUTHORIZED (err u500))
(define-constant ERR-REVIEW-NOT-FOUND (err u501))
(define-constant ERR-INVALID-INPUT (err u502))
(define-constant ERR-INVALID-STATUS (err u503))
(define-constant ERR-REVIEW-CLOSED (err u504))

;; Data Variables
(define-data-var next-review-id uint u1)
(define-data-var next-assessment-id uint u1)

;; Data Maps
(define-map reviews
  { review-id: uint }
  {
    scorecard-id: uint,
    review-type: uint,
    scheduled-block: uint,
    start-block: uint,
    end-block: uint,
    status: uint,
    coordinator: principal,
    total-participants: uint,
    total-assessments: uint,
    creation-block: uint
  }
)

(define-map review-participants
  { review-id: uint, participant: principal }
  {
    role: uint,
    invited-block: uint,
    response-block: uint,
    participation-status: uint
  }
)

(define-map assessments
  { assessment-id: uint }
  {
    review-id: uint,
    assessor: principal,
    objective-id: uint,
    score: uint,
    comments: (string-ascii 200),
    assessment-block: uint,
    confidence-level: uint
  }
)

(define-map review-summaries
  { review-id: uint }
  {
    average-score: uint,
    highest-score: uint,
    lowest-score: uint,
    consensus-level: uint,
    completion-percentage: uint,
    final-recommendations: (string-ascii 300)
  }
)

;; Public Functions

;; Schedule a new review
(define-public (schedule-review
  (scorecard-id uint)
  (review-type uint)
  (scheduled-block uint)
  (duration-blocks uint)
)
  (let
    (
      (review-id (var-get next-review-id))
      (end-block (+ scheduled-block duration-blocks))
    )
    (asserts! (<= review-type u3) ERR-INVALID-INPUT)
    (asserts! (> scheduled-block block-height) ERR-INVALID-INPUT)
    (asserts! (> duration-blocks u0) ERR-INVALID-INPUT)

    (map-set reviews
      { review-id: review-id }
      {
        scorecard-id: scorecard-id,
        review-type: review-type,
        scheduled-block: scheduled-block,
        start-block: u0,
        end-block: end-block,
        status: u1,
        coordinator: tx-sender,
        total-participants: u0,
        total-assessments: u0,
        creation-block: block-height
      }
    )

    (var-set next-review-id (+ review-id u1))
    (ok review-id)
  )
)

;; Add participant to review
(define-public (add-participant (review-id uint) (participant principal) (role uint))
  (let
    (
      (review-data (unwrap! (map-get? reviews { review-id: review-id }) ERR-REVIEW-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get coordinator review-data)) ERR-NOT-AUTHORIZED)
    (asserts! (<= role u2) ERR-INVALID-INPUT)
    (asserts! (is-eq (get status review-data) u1) ERR-INVALID-STATUS)

    (map-set review-participants
      { review-id: review-id, participant: participant }
      {
        role: role,
        invited-block: block-height,
        response-block: u0,
        participation-status: u1
      }
    )

    (map-set reviews
      { review-id: review-id }
      (merge review-data { total-participants: (+ (get total-participants review-data) u1) })
    )

    (ok true)
  )
)

;; Start review
(define-public (start-review (review-id uint))
  (let
    (
      (review-data (unwrap! (map-get? reviews { review-id: review-id }) ERR-REVIEW-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get coordinator review-data)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status review-data) u1) ERR-INVALID-STATUS)
    (asserts! (>= block-height (get scheduled-block review-data)) ERR-INVALID-INPUT)

    (map-set reviews
      { review-id: review-id }
      (merge review-data
        {
          status: u2,
          start-block: block-height
        }
      )
    )

    (ok true)
  )
)

;; Submit assessment
(define-public (submit-assessment
  (review-id uint)
  (objective-id uint)
  (score uint)
  (comments (string-ascii 200))
  (confidence-level uint)
)
  (let
    (
      (assessment-id (var-get next-assessment-id))
      (review-data (unwrap! (map-get? reviews { review-id: review-id }) ERR-REVIEW-NOT-FOUND))
      (participant-data (unwrap! (map-get? review-participants { review-id: review-id, participant: tx-sender }) ERR-NOT-AUTHORIZED))
    )
    (asserts! (is-eq (get status review-data) u2) ERR-INVALID-STATUS)
    (asserts! (<= score u100) ERR-INVALID-INPUT)
    (asserts! (<= confidence-level u100) ERR-INVALID-INPUT)
    (asserts! (< block-height (get end-block review-data)) ERR-REVIEW-CLOSED)

    (map-set assessments
      { assessment-id: assessment-id }
      {
        review-id: review-id,
        assessor: tx-sender,
        objective-id: objective-id,
        score: score,
        comments: comments,
        assessment-block: block-height,
        confidence-level: confidence-level
      }
    )

    (map-set reviews
      { review-id: review-id }
      (merge review-data { total-assessments: (+ (get total-assessments review-data) u1) })
    )

    (var-set next-assessment-id (+ assessment-id u1))
    (ok assessment-id)
  )
)

;; Complete review
(define-public (complete-review (review-id uint) (final-recommendations (string-ascii 300)))
  (let
    (
      (review-data (unwrap! (map-get? reviews { review-id: review-id }) ERR-REVIEW-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get coordinator review-data)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status review-data) u2) ERR-INVALID-STATUS)

    (map-set reviews
      { review-id: review-id }
      (merge review-data { status: u3 })
    )

    (map-set review-summaries
      { review-id: review-id }
      {
        average-score: u0,
        highest-score: u0,
        lowest-score: u0,
        consensus-level: u0,
        completion-percentage: u100,
        final-recommendations: final-recommendations
      }
    )

    (ok true)
  )
)

;; Read-only Functions

;; Get review by ID
(define-read-only (get-review (review-id uint))
  (map-get? reviews { review-id: review-id })
)

;; Get participant info
(define-read-only (get-participant (review-id uint) (participant principal))
  (map-get? review-participants { review-id: review-id, participant: participant })
)

;; Get assessment by ID
(define-read-only (get-assessment (assessment-id uint))
  (map-get? assessments { assessment-id: assessment-id })
)

;; Get review summary
(define-read-only (get-review-summary (review-id uint))
  (map-get? review-summaries { review-id: review-id })
)

;; Check if review is active
(define-read-only (is-review-active (review-id uint))
  (match (map-get? reviews { review-id: review-id })
    review-data
      (and
        (is-eq (get status review-data) u2)
        (< block-height (get end-block review-data))
      )
    false
  )
)

;; Get next review ID
(define-read-only (get-next-review-id)
  (var-get next-review-id)
)
