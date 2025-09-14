;; certification-manager
;; Manages quality certifications, compliance documents, and third-party verifications for products and supply chain participants.

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_CERTIFICATION_NOT_FOUND (err u404))
(define-constant ERR_INVALID_CERTIFICATION (err u402))
(define-constant ERR_DUPLICATE_CERTIFICATION (err u403))
(define-constant ERR_EXPIRED_CERTIFICATION (err u405))
(define-constant ERR_INVALID_ISSUER (err u406))
(define-constant ERR_CERTIFICATION_REVOKED (err u407))
(define-constant ERR_INVALID_SCORE (err u408))
(define-constant ERR_INSUFFICIENT_PERMISSIONS (err u409))
(define-constant ERR_INVALID_DATE (err u410))

;; Certification Types
(define-constant CERT_ORGANIC "ORGANIC")
(define-constant CERT_ISO_9001 "ISO_9001")
(define-constant CERT_HACCP "HACCP")
(define-constant CERT_FAIR_TRADE "FAIR_TRADE")
(define-constant CERT_HALAL "HALAL")
(define-constant CERT_KOSHER "KOSHER")
(define-constant CERT_NON_GMO "NON_GMO")
(define-constant CERT_SUSTAINABILITY "SUSTAINABILITY")
(define-constant CERT_SAFETY "SAFETY")
(define-constant CERT_QUALITY "QUALITY")

;; Certification Status
(define-constant STATUS_PENDING u1)
(define-constant STATUS_APPROVED u2)
(define-constant STATUS_REJECTED u3)
(define-constant STATUS_EXPIRED u4)
(define-constant STATUS_REVOKED u5)
(define-constant STATUS_RENEWED u6)

;; Constants
(define-constant MAX_CERTIFICATION_VALIDITY u525600) ;; 1 year in blocks (approx)
(define-constant MIN_SCORE u0)
(define-constant MAX_SCORE u100)
(define-constant MAX_DOCUMENTS u20)

;; Data Variables
(define-data-var certification-count uint u0)
(define-data-var issuer-count uint u0)
(define-data-var audit-count uint u0)
(define-data-var system-paused bool false)

;; Certification Registry
(define-map certifications
  {certification-id: (string-ascii 64)}
  {
    product-id: (optional (string-ascii 64)),
    entity-id: principal, ;; Product manufacturer or facility
    certification-type: (string-ascii 50),
    issuer: principal,
    issue-date: uint,
    expiry-date: uint,
    status: uint,
    score: uint, ;; 0-100 certification score
    compliance-level: (string-ascii 20), ;; A, B, C, D grades
    document-hash: (string-ascii 128), ;; Hash of certification document
    verification-url: (optional (string-utf8 200)),
    notes: (optional (string-utf8 400)),
    created-at: uint,
    updated-at: uint
  })

;; Authorized Certification Issuers
(define-map certification-issuers
  principal
  {
    issuer-name: (string-utf8 150),
    issuer-type: (string-ascii 50), ;; "GOVERNMENT", "PRIVATE", "NGO", "INTERNATIONAL"
    authorized-certifications: (list 20 (string-ascii 50)),
    accreditation-body: (string-utf8 100),
    active: bool,
    authorized-at: uint,
    authorized-by: principal,
    reputation-score: uint
  })

;; Audit Trail for Certifications
(define-map certification-audits
  {certification-id: (string-ascii 64), audit-id: uint}
  {
    auditor: principal,
    audit-type: (string-ascii 30), ;; "INITIAL", "RENEWAL", "INSPECTION", "COMPLAINT"
    audit-date: uint,
    findings: (string-utf8 500),
    score: uint,
    pass: bool,
    corrective-actions: (optional (string-utf8 300)),
    next-audit-date: (optional uint),
    audit-documents: (list 10 (string-ascii 128))
  })

;; Certification Dependencies (some certs require others)
(define-map certification-dependencies
  (string-ascii 50) ;; certification type
  (list 5 (string-ascii 50))) ;; required prerequisite certifications

;; Audit counters per certification
(define-map certification-audit-counts {certification-id: (string-ascii 64)} uint)

;; Entity certification history
(define-map entity-certifications
  principal
  (list 50 (string-ascii 64))) ;; list of certification IDs

;; Compliance violations
(define-map compliance-violations
  {entity-id: principal, violation-id: uint}
  {
    violation-type: (string-ascii 50),
    severity: uint, ;; 1-5 scale
    description: (string-utf8 400),
    reported-by: principal,
    reported-at: uint,
    resolved: bool,
    resolution-date: (optional uint),
    penalty-applied: (optional (string-utf8 200))
  })

(define-map entity-violation-counts principal uint)

;; Private Helper Functions
(define-private (is-authorized-issuer (issuer principal) (cert-type (string-ascii 50)))
  (match (map-get? certification-issuers issuer)
    issuer-data
      (and (get active issuer-data)
           (is-some (index-of (get authorized-certifications issuer-data) cert-type)))
    false))

(define-private (is-certification-valid (certification-id (string-ascii 64)))
  (match (map-get? certifications {certification-id: certification-id})
    cert-data
      (and (is-eq (get status cert-data) STATUS_APPROVED)
           (> (get expiry-date cert-data) block-height))
    false))

(define-private (get-next-audit-id (certification-id (string-ascii 64)))
  (+ (default-to u0 (map-get? certification-audit-counts {certification-id: certification-id})) u1))

(define-private (get-next-violation-id (entity-id principal))
  (+ (default-to u0 (map-get? entity-violation-counts entity-id)) u1))

(define-private (check-certification-dependencies (cert-type (string-ascii 50)) (entity-id principal))
  ;; Check if entity has required prerequisite certifications
  (match (map-get? certification-dependencies cert-type)
    required-certs
      (fold check-single-dependency required-certs true)
    true)) ;; No dependencies required

(define-private (check-single-dependency (required-cert (string-ascii 50)) (all-satisfied bool))
  (if all-satisfied
      (has-valid-certification-type CONTRACT_OWNER required-cert) ;; Simplified check
      false))

(define-private (has-valid-certification-type (entity-id principal) (cert-type (string-ascii 50)))
  ;; Simplified implementation - would check entity's active certifications
  true)

(define-private (calculate-compliance-score (entity-id principal))
  ;; Calculate overall compliance score based on certifications and violations
  (let ((violation-count (default-to u0 (map-get? entity-violation-counts entity-id)))
        (base-score u100))
    (if (> violation-count u0)
        (max u0 (- base-score (* violation-count u10)))
        base-score)))

(define-private (update-issuer-reputation (issuer principal) (positive bool))
  (match (map-get? certification-issuers issuer)
    issuer-data
      (let ((current-score (get reputation-score issuer-data))
            (new-score (if positive
                          (min u100 (+ current-score u5))
                          (max u0 (- current-score u10)))))
        (map-set certification-issuers issuer
                (merge issuer-data {reputation-score: new-score}))
        true)
    false))

;; Read-Only Functions
(define-read-only (get-certification (certification-id (string-ascii 64)))
  (map-get? certifications {certification-id: certification-id}))

(define-read-only (get-issuer-info (issuer principal))
  (map-get? certification-issuers issuer))

(define-read-only (get-certification-audit (certification-id (string-ascii 64)) (audit-id uint))
  (map-get? certification-audits {certification-id: certification-id, audit-id: audit-id}))

(define-read-only (get-entity-certifications (entity-id principal))
  (default-to (list) (map-get? entity-certifications entity-id)))

(define-read-only (get-compliance-violation (entity-id principal) (violation-id uint))
  (map-get? compliance-violations {entity-id: entity-id, violation-id: violation-id}))

(define-read-only (get-certification-audit-count (certification-id (string-ascii 64)))
  (default-to u0 (map-get? certification-audit-counts {certification-id: certification-id})))

(define-read-only (get-entity-violation-count (entity-id principal))
  (default-to u0 (map-get? entity-violation-counts entity-id)))

(define-read-only (is-entity-compliant (entity-id principal))
  (>= (calculate-compliance-score entity-id) u70)) ;; 70% threshold for compliance

(define-read-only (get-certification-stats)
  {total-certifications: (var-get certification-count),
   total-issuers: (var-get issuer-count),
   total-audits: (var-get audit-count),
   system-paused: (var-get system-paused)})

(define-read-only (get-entity-compliance-score (entity-id principal))
  (calculate-compliance-score entity-id))

;; Public Functions
(define-public (issue-certification
                 (certification-id (string-ascii 64))
                 (product-id (optional (string-ascii 64)))
                 (entity-id principal)
                 (certification-type (string-ascii 50))
                 (expiry-date uint)
                 (score uint)
                 (compliance-level (string-ascii 20))
                 (document-hash (string-ascii 128))
                 (verification-url (optional (string-utf8 200))))
  (begin
    (asserts! (not (var-get system-paused)) ERR_UNAUTHORIZED)
    (asserts! (is-authorized-issuer tx-sender certification-type) ERR_INVALID_ISSUER)
    (asserts! (is-none (get-certification certification-id)) ERR_DUPLICATE_CERTIFICATION)
    (asserts! (and (>= score MIN_SCORE) (<= score MAX_SCORE)) ERR_INVALID_SCORE)
    (asserts! (> expiry-date block-height) ERR_INVALID_DATE)
    (asserts! (check-certification-dependencies certification-type entity-id) ERR_INVALID_CERTIFICATION)
    
    (let ((new-certification {
            product-id: product-id,
            entity-id: entity-id,
            certification-type: certification-type,
            issuer: tx-sender,
            issue-date: block-height,
            expiry-date: expiry-date,
            status: STATUS_APPROVED,
            score: score,
            compliance-level: compliance-level,
            document-hash: document-hash,
            verification-url: verification-url,
            notes: none,
            created-at: block-height,
            updated-at: block-height
          }))
      
      ;; Record certification
      (map-set certifications {certification-id: certification-id} new-certification)
      (map-set certification-audit-counts {certification-id: certification-id} u0)
      
      ;; Update entity certification list
      (let ((current-certs (default-to (list) (map-get? entity-certifications entity-id))))
        (map-set entity-certifications entity-id 
                (unwrap! (as-max-len? (append current-certs certification-id) u50) ERR_INVALID_CERTIFICATION)))
      
      ;; Update counters
      (var-set certification-count (+ (var-get certification-count) u1))
      
      ;; Update issuer reputation positively
      (update-issuer-reputation tx-sender true)
      
      (ok certification-id))))

(define-public (register-certification-issuer
                 (issuer principal)
                 (issuer-name (string-utf8 150))
                 (issuer-type (string-ascii 50))
                 (authorized-certifications (list 20 (string-ascii 50)))
                 (accreditation-body (string-utf8 100)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (is-none (get-issuer-info issuer)) ERR_DUPLICATE_CERTIFICATION)
    
    (let ((new-issuer {
            issuer-name: issuer-name,
            issuer-type: issuer-type,
            authorized-certifications: authorized-certifications,
            accreditation-body: accreditation-body,
            active: true,
            authorized-at: block-height,
            authorized-by: tx-sender,
            reputation-score: u75 ;; Start with good reputation
          }))
      
      (map-set certification-issuers issuer new-issuer)
      (var-set issuer-count (+ (var-get issuer-count) u1))
      (ok issuer))))

(define-public (conduct-certification-audit
                 (certification-id (string-ascii 64))
                 (audit-type (string-ascii 30))
                 (findings (string-utf8 500))
                 (score uint)
                 (pass bool)
                 (corrective-actions (optional (string-utf8 300)))
                 (next-audit-date (optional uint)))
  (begin
    (asserts! (not (var-get system-paused)) ERR_UNAUTHORIZED)
    (asserts! (is-some (get-certification certification-id)) ERR_CERTIFICATION_NOT_FOUND)
    (asserts! (and (>= score MIN_SCORE) (<= score MAX_SCORE)) ERR_INVALID_SCORE)
    
    (let ((audit-id (get-next-audit-id certification-id))
          (audit-record {
            auditor: tx-sender,
            audit-type: audit-type,
            audit-date: block-height,
            findings: findings,
            score: score,
            pass: pass,
            corrective-actions: corrective-actions,
            next-audit-date: next-audit-date,
            audit-documents: (list)
          }))
      
      ;; Record audit
      (map-set certification-audits {certification-id: certification-id, audit-id: audit-id} audit-record)
      (map-set certification-audit-counts {certification-id: certification-id} audit-id)
      
      ;; Update certification status based on audit results
      (if pass
          (begin
            ;; Positive audit - maintain or improve status
            (update-issuer-reputation tx-sender true)
            true)
          (begin
            ;; Failed audit - may need to revoke or downgrade
            (if (< score u50)
                (try! (revoke-certification certification-id "Failed audit with critical findings"))
                true)
            (update-issuer-reputation tx-sender false)
            true))
      
      (var-set audit-count (+ (var-get audit-count) u1))
      (ok audit-id))))

(define-public (revoke-certification (certification-id (string-ascii 64)) (reason (string-utf8 300)))
  (begin
    (asserts! (is-some (get-certification certification-id)) ERR_CERTIFICATION_NOT_FOUND)
    
    (match (get-certification certification-id)
      cert-data
        (begin
          ;; Only issuer or contract owner can revoke
          (asserts! (or (is-eq tx-sender (get issuer cert-data))
                       (is-eq tx-sender CONTRACT_OWNER)) ERR_UNAUTHORIZED)
          
          (let ((updated-cert (merge cert-data {
                  status: STATUS_REVOKED,
                  notes: (some reason),
                  updated-at: block-height
                })))
            
            (map-set certifications {certification-id: certification-id} updated-cert)
            
            ;; Update issuer reputation negatively
            (update-issuer-reputation (get issuer cert-data) false)
            
            (ok true)))
      ERR_CERTIFICATION_NOT_FOUND)))

(define-public (renew-certification
                 (certification-id (string-ascii 64))
                 (new-expiry-date uint)
                 (new-score uint)
                 (document-hash (string-ascii 128)))
  (begin
    (asserts! (not (var-get system-paused)) ERR_UNAUTHORIZED)
    (asserts! (and (>= new-score MIN_SCORE) (<= new-score MAX_SCORE)) ERR_INVALID_SCORE)
    (asserts! (> new-expiry-date block-height) ERR_INVALID_DATE)
    
    (match (get-certification certification-id)
      cert-data
        (begin
          (asserts! (is-eq tx-sender (get issuer cert-data)) ERR_UNAUTHORIZED)
          
          (let ((renewed-cert (merge cert-data {
                  expiry-date: new-expiry-date,
                  status: STATUS_RENEWED,
                  score: new-score,
                  document-hash: document-hash,
                  updated-at: block-height
                })))
            
            (map-set certifications {certification-id: certification-id} renewed-cert)
            (ok true)))
      ERR_CERTIFICATION_NOT_FOUND)))

(define-public (report-compliance-violation
                 (entity-id principal)
                 (violation-type (string-ascii 50))
                 (severity uint)
                 (description (string-utf8 400)))
  (begin
    (asserts! (and (>= severity u1) (<= severity u5)) ERR_INVALID_SCORE)
    
    (let ((violation-id (get-next-violation-id entity-id))
          (violation-record {
            violation-type: violation-type,
            severity: severity,
            description: description,
            reported-by: tx-sender,
            reported-at: block-height,
            resolved: false,
            resolution-date: none,
            penalty-applied: none
          }))
      
      (map-set compliance-violations {entity-id: entity-id, violation-id: violation-id} violation-record)
      (map-set entity-violation-counts entity-id violation-id)
      
      (ok violation-id))))

;; Admin Functions
(define-public (pause-system)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set system-paused true)
    (ok true)))

(define-public (unpause-system)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set system-paused false)
    (ok true)))

(define-public (deactivate-issuer (issuer principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    
    (match (get-issuer-info issuer)
      issuer-data
        (let ((updated-issuer (merge issuer-data {active: false})))
          (map-set certification-issuers issuer updated-issuer)
          (ok true))
      ERR_INVALID_ISSUER)))
