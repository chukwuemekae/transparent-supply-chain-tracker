;; product-registry
;; Core contract that registers products with unique identifiers and tracks their movement through various stages of the supply chain.

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_PRODUCT_NOT_FOUND (err u404))
(define-constant ERR_INVALID_STAGE (err u402))
(define-constant ERR_DUPLICATE_PRODUCT (err u403))
(define-constant ERR_INVALID_LOCATION (err u405))
(define-constant ERR_INSUFFICIENT_PERMISSIONS (err u406))
(define-constant ERR_INVALID_TIMESTAMP (err u407))
(define-constant ERR_BATCH_NOT_FOUND (err u408))
(define-constant ERR_INVALID_QUALITY_SCORE (err u409))

;; Supply Chain Stages
(define-constant STAGE_MANUFACTURED u1)
(define-constant STAGE_QUALITY_CHECKED u2)
(define-constant STAGE_PACKAGED u3)
(define-constant STAGE_SHIPPED u4)
(define-constant STAGE_IN_TRANSIT u5)
(define-constant STAGE_CUSTOMS_CLEARED u6)
(define-constant STAGE_WAREHOUSED u7)
(define-constant STAGE_DISTRIBUTED u8)
(define-constant STAGE_RETAIL_READY u9)
(define-constant STAGE_SOLD u10)
(define-constant STAGE_RECALLED u99)

;; Quality and Safety Constants
(define-constant MIN_QUALITY_SCORE u0)
(define-constant MAX_QUALITY_SCORE u100)
(define-constant CRITICAL_TEMPERATURE_THRESHOLD u25) ;; Celsius
(define-constant MAX_LOCATION_STRING_LENGTH u200)
(define-constant MAX_DESCRIPTION_LENGTH u500)
(define-constant MAX_BATCH_SIZE u10000)

;; Data Variables
(define-data-var product-count uint u0)
(define-data-var batch-count uint u0)
(define-data-var total-recalled-products uint u0)
(define-data-var registry-paused bool false)

;; Product Structure
(define-map products 
  {product-id: (string-ascii 64)}
  {
    manufacturer: principal,
    product-name: (string-utf8 200),
    category: (string-ascii 50),
    batch-id: (string-ascii 32),
    manufacture-date: uint,
    expiry-date: uint,
    current-stage: uint,
    current-location: (string-utf8 200),
    current-holder: principal,
    quality-score: uint,
    temperature-sensitive: bool,
    organic-certified: bool,
    active: bool,
    created-at: uint,
    updated-at: uint
  })

;; Supply Chain Movement History
(define-map product-movements
  {product-id: (string-ascii 64), movement-id: uint}
  {
    from-stage: uint,
    to-stage: uint,
    from-location: (string-utf8 200),
    to-location: (string-utf8 200),
    from-holder: principal,
    to-holder: principal,
    timestamp: uint,
    transportation-method: (string-ascii 50),
    temperature-recorded: (optional uint),
    quality-check-passed: bool,
    notes: (optional (string-utf8 300)),
    verified-by: principal
  })

;; Batch Information
(define-map product-batches
  {batch-id: (string-ascii 32)}
  {
    manufacturer: principal,
    product-type: (string-utf8 100),
    batch-size: uint,
    manufacture-date: uint,
    quality-certifications: (list 10 (string-ascii 50)),
    raw-materials-source: (string-utf8 200),
    production-facility: (string-utf8 150),
    batch-notes: (optional (string-utf8 400)),
    active: bool
  })

;; Product Locations and GPS Coordinates
(define-map product-locations
  {product-id: (string-ascii 64)}
  {
    latitude: (string-ascii 20),
    longitude: (string-ascii 20),
    address: (string-utf8 250),
    facility-type: (string-ascii 50),
    last-updated: uint,
    updated-by: principal
  })

;; Movement counter for each product
(define-map product-movement-counts {product-id: (string-ascii 64)} uint)

;; Quality and Safety Alerts
(define-map quality-alerts
  {product-id: (string-ascii 64), alert-id: uint}
  {
    alert-type: (string-ascii 50),
    severity: uint, ;; 1-5 scale
    description: (string-utf8 300),
    raised-by: principal,
    timestamp: uint,
    resolved: bool,
    resolution-notes: (optional (string-utf8 200))
  })

;; Alert counter for products
(define-map product-alert-counts {product-id: (string-ascii 64)} uint)

;; Authorized stakeholders per product
(define-map product-stakeholders 
  {product-id: (string-ascii 64), stakeholder: principal}
  {role: (string-ascii 30), authorized-at: uint, authorized-by: principal})

;; Private Helper Functions
(define-private (is-valid-stage (stage uint))
  (and (>= stage STAGE_MANUFACTURED) 
       (or (<= stage STAGE_SOLD) (is-eq stage STAGE_RECALLED))))

(define-private (is-valid-quality-score (score uint))
  (and (>= score MIN_QUALITY_SCORE) (<= score MAX_QUALITY_SCORE)))

(define-private (is-authorized-for-product (product-id (string-ascii 64)) (user principal))
  (or (is-eq user CONTRACT_OWNER)
      (is-some (map-get? product-stakeholders {product-id: product-id, stakeholder: user}))))

(define-private (get-next-movement-id (product-id (string-ascii 64)))
  (+ (default-to u0 (map-get? product-movement-counts {product-id: product-id})) u1))

(define-private (get-next-alert-id (product-id (string-ascii 64)))
  (+ (default-to u0 (map-get? product-alert-counts {product-id: product-id})) u1))

(define-private (update-product-location (product-id (string-ascii 64)) (location (string-utf8 200)))
  (match (map-get? products {product-id: product-id})
    product-data
      (let ((updated-product (merge product-data 
                                  {current-location: location, updated-at: block-height})))
        (map-set products {product-id: product-id} updated-product)
        true)
    false))

;; Read-Only Functions
(define-read-only (get-product (product-id (string-ascii 64)))
  (map-get? products {product-id: product-id}))

(define-read-only (get-product-movement (product-id (string-ascii 64)) (movement-id uint))
  (map-get? product-movements {product-id: product-id, movement-id: movement-id}))

(define-read-only (get-batch-info (batch-id (string-ascii 32)))
  (map-get? product-batches {batch-id: batch-id}))

(define-read-only (get-product-location (product-id (string-ascii 64)))
  (map-get? product-locations {product-id: product-id}))

(define-read-only (get-product-movements-count (product-id (string-ascii 64)))
  (default-to u0 (map-get? product-movement-counts {product-id: product-id})))

(define-read-only (get-product-alerts-count (product-id (string-ascii 64)))
  (default-to u0 (map-get? product-alert-counts {product-id: product-id})))

(define-read-only (get-quality-alert (product-id (string-ascii 64)) (alert-id uint))
  (map-get? quality-alerts {product-id: product-id, alert-id: alert-id}))

(define-read-only (is-product-recalled (product-id (string-ascii 64)))
  (match (get-product product-id)
    product-data (is-eq (get current-stage product-data) STAGE_RECALLED)
    false))

(define-read-only (get-registry-stats)
  {total-products: (var-get product-count),
   total-batches: (var-get batch-count),
   total-recalled: (var-get total-recalled-products),
   registry-paused: (var-get registry-paused)})

(define-read-only (is-stakeholder-authorized (product-id (string-ascii 64)) (stakeholder principal))
  (is-some (map-get? product-stakeholders {product-id: product-id, stakeholder: stakeholder})))

;; Public Functions
(define-public (register-product 
                 (product-id (string-ascii 64))
                 (product-name (string-utf8 200))
                 (category (string-ascii 50))
                 (batch-id (string-ascii 32))
                 (expiry-date uint)
                 (temperature-sensitive bool)
                 (organic-certified bool))
  (begin
    (asserts! (not (var-get registry-paused)) ERR_UNAUTHORIZED)
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (is-none (get-product product-id)) ERR_DUPLICATE_PRODUCT)
    (asserts! (> expiry-date block-height) ERR_INVALID_TIMESTAMP)
    
    (let ((new-product {
            manufacturer: tx-sender,
            product-name: product-name,
            category: category,
            batch-id: batch-id,
            manufacture-date: block-height,
            expiry-date: expiry-date,
            current-stage: STAGE_MANUFACTURED,
            current-location: u"Manufacturing Facility",
            current-holder: tx-sender,
            quality-score: u100, ;; Start with perfect score
            temperature-sensitive: temperature-sensitive,
            organic-certified: organic-certified,
            active: true,
            created-at: block-height,
            updated-at: block-height
          }))
      
      (map-set products {product-id: product-id} new-product)
      (map-set product-movement-counts {product-id: product-id} u0)
      (map-set product-alert-counts {product-id: product-id} u0)
      
      ;; Authorize manufacturer as stakeholder
      (map-set product-stakeholders 
               {product-id: product-id, stakeholder: tx-sender}
               {role: "manufacturer", authorized-at: block-height, authorized-by: tx-sender})
      
      (var-set product-count (+ (var-get product-count) u1))
      (ok product-id))))

(define-public (create-batch (batch-id (string-ascii 32))
                           (product-type (string-utf8 100))
                           (batch-size uint)
                           (raw-materials-source (string-utf8 200))
                           (production-facility (string-utf8 150)))
  (begin
    (asserts! (not (var-get registry-paused)) ERR_UNAUTHORIZED)
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (is-none (get-batch-info batch-id)) ERR_DUPLICATE_PRODUCT)
    (asserts! (<= batch-size MAX_BATCH_SIZE) ERR_INVALID_STAGE)
    
    (let ((new-batch {
            manufacturer: tx-sender,
            product-type: product-type,
            batch-size: batch-size,
            manufacture-date: block-height,
            quality-certifications: (list),
            raw-materials-source: raw-materials-source,
            production-facility: production-facility,
            batch-notes: none,
            active: true
          }))
      
      (map-set product-batches {batch-id: batch-id} new-batch)
      (var-set batch-count (+ (var-get batch-count) u1))
      (ok batch-id))))

(define-public (move-product (product-id (string-ascii 64))
                           (to-stage uint)
                           (to-location (string-utf8 200))
                           (to-holder principal)
                           (transportation-method (string-ascii 50))
                           (temperature-recorded (optional uint))
                           (quality-check-passed bool)
                           (notes (optional (string-utf8 300))))
  (begin
    (asserts! (not (var-get registry-paused)) ERR_UNAUTHORIZED)
    (asserts! (is-valid-stage to-stage) ERR_INVALID_STAGE)
    
    (match (get-product product-id)
      product-data
        (begin
          (asserts! (is-authorized-for-product product-id tx-sender) ERR_INSUFFICIENT_PERMISSIONS)
          (asserts! (get active product-data) ERR_PRODUCT_NOT_FOUND)
          
          (let ((movement-id (get-next-movement-id product-id))
                (movement-record {
                  from-stage: (get current-stage product-data),
                  to-stage: to-stage,
                  from-location: (get current-location product-data),
                  to-location: to-location,
                  from-holder: (get current-holder product-data),
                  to-holder: to-holder,
                  timestamp: block-height,
                  transportation-method: transportation-method,
                  temperature-recorded: temperature-recorded,
                  quality-check-passed: quality-check-passed,
                  notes: notes,
                  verified-by: tx-sender
                })
                (updated-product (merge product-data {
                  current-stage: to-stage,
                  current-location: to-location,
                  current-holder: to-holder,
                  updated-at: block-height
                })))
            
            ;; Record the movement
            (map-set product-movements {product-id: product-id, movement-id: movement-id} movement-record)
            (map-set product-movement-counts {product-id: product-id} movement-id)
            
            ;; Update product
            (map-set products {product-id: product-id} updated-product)
            
            ;; Authorize new holder as stakeholder
            (map-set product-stakeholders
                     {product-id: product-id, stakeholder: to-holder}
                     {role: "handler", authorized-at: block-height, authorized-by: tx-sender})
            
            (ok movement-id)))
      ERR_PRODUCT_NOT_FOUND)))

(define-public (update-product-location-gps (product-id (string-ascii 64))
                                          (latitude (string-ascii 20))
                                          (longitude (string-ascii 20))
                                          (address (string-utf8 250))
                                          (facility-type (string-ascii 50)))
  (begin
    (asserts! (is-authorized-for-product product-id tx-sender) ERR_INSUFFICIENT_PERMISSIONS)
    (asserts! (is-some (get-product product-id)) ERR_PRODUCT_NOT_FOUND)
    
    (let ((location-record {
            latitude: latitude,
            longitude: longitude,
            address: address,
            facility-type: facility-type,
            last-updated: block-height,
            updated-by: tx-sender
          }))
      
      (map-set product-locations {product-id: product-id} location-record)
      (ok true))))

(define-public (raise-quality-alert (product-id (string-ascii 64))
                                  (alert-type (string-ascii 50))
                                  (severity uint)
                                  (description (string-utf8 300)))
  (begin
    (asserts! (is-authorized-for-product product-id tx-sender) ERR_INSUFFICIENT_PERMISSIONS)
    (asserts! (is-some (get-product product-id)) ERR_PRODUCT_NOT_FOUND)
    (asserts! (and (>= severity u1) (<= severity u5)) ERR_INVALID_QUALITY_SCORE)
    
    (let ((alert-id (get-next-alert-id product-id))
          (alert-record {
            alert-type: alert-type,
            severity: severity,
            description: description,
            raised-by: tx-sender,
            timestamp: block-height,
            resolved: false,
            resolution-notes: none
          }))
      
      (map-set quality-alerts {product-id: product-id, alert-id: alert-id} alert-record)
      (map-set product-alert-counts {product-id: product-id} alert-id)
      (ok alert-id))))

(define-public (recall-product (product-id (string-ascii 64)) (reason (string-utf8 300)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    
    (match (get-product product-id)
      product-data
        (let ((updated-product (merge product-data {
                current-stage: STAGE_RECALLED,
                updated-at: block-height
              })))
          
          (map-set products {product-id: product-id} updated-product)
          (var-set total-recalled-products (+ (var-get total-recalled-products) u1))
          
          ;; Raise critical alert
          (try! (raise-quality-alert product-id "RECALL" u5 reason))
          (ok true))
      ERR_PRODUCT_NOT_FOUND)))

;; Admin Functions
(define-public (authorize-stakeholder (product-id (string-ascii 64))
                                    (stakeholder principal)
                                    (role (string-ascii 30)))
  (begin
    (asserts! (is-authorized-for-product product-id tx-sender) ERR_INSUFFICIENT_PERMISSIONS)
    
    (map-set product-stakeholders 
             {product-id: product-id, stakeholder: stakeholder}
             {role: role, authorized-at: block-height, authorized-by: tx-sender})
    (ok true)))

(define-public (pause-registry)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set registry-paused true)
    (ok true)))

(define-public (unpause-registry)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set registry-paused false)
    (ok true)))
