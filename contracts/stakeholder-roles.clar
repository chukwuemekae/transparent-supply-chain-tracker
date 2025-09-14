;; stakeholder-roles
;; Defines and manages permissions for different supply chain participants including manufacturers, distributors, retailers, and auditors.

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_STAKEHOLDER_NOT_FOUND (err u404))
(define-constant ERR_INVALID_ROLE (err u402))
(define-constant ERR_DUPLICATE_STAKEHOLDER (err u403))
(define-constant ERR_INVALID_PERMISSION (err u405))
(define-constant ERR_ROLE_SUSPENDED (err u406))
(define-constant ERR_INSUFFICIENT_REPUTATION (err u407))
(define-constant ERR_INVALID_KYC (err u408))
(define-constant ERR_EXPIRED_CREDENTIALS (err u409))

;; Stakeholder Role Types
(define-constant ROLE_MANUFACTURER "MANUFACTURER")
(define-constant ROLE_SUPPLIER "SUPPLIER")
(define-constant ROLE_DISTRIBUTOR "DISTRIBUTOR")
(define-constant ROLE_RETAILER "RETAILER")
(define-constant ROLE_LOGISTICS "LOGISTICS")
(define-constant ROLE_AUDITOR "AUDITOR")
(define-constant ROLE_CERTIFIER "CERTIFIER")
(define-constant ROLE_REGULATOR "REGULATOR")
(define-constant ROLE_CONSUMER "CONSUMER")
(define-constant ROLE_ADMIN "ADMIN")

;; Permission Types
(define-constant PERM_REGISTER_PRODUCT "REGISTER_PRODUCT")
(define-constant PERM_UPDATE_PRODUCT "UPDATE_PRODUCT")
(define-constant PERM_MOVE_PRODUCT "MOVE_PRODUCT")
(define-constant PERM_VIEW_PRODUCT "VIEW_PRODUCT")
(define-constant PERM_CERTIFY_PRODUCT "CERTIFY_PRODUCT")
(define-constant PERM_AUDIT_PRODUCT "AUDIT_PRODUCT")
(define-constant PERM_RECALL_PRODUCT "RECALL_PRODUCT")
(define-constant PERM_MANAGE_STAKEHOLDERS "MANAGE_STAKEHOLDERS")
(define-constant PERM_VIEW_ANALYTICS "VIEW_ANALYTICS")
(define-constant PERM_SYSTEM_ADMIN "SYSTEM_ADMIN")

;; Status Types
(define-constant STATUS_PENDING u1)
(define-constant STATUS_ACTIVE u2)
(define-constant STATUS_SUSPENDED u3)
(define-constant STATUS_REVOKED u4)
(define-constant STATUS_EXPIRED u5)

;; KYC Verification Levels
(define-constant KYC_NONE u0)
(define-constant KYC_BASIC u1)
(define-constant KYC_STANDARD u2)
(define-constant KYC_ENHANCED u3)
(define-constant KYC_INSTITUTIONAL u4)

;; Constants
(define-constant MIN_REPUTATION u0)
(define-constant MAX_REPUTATION u100)
(define-constant REPUTATION_THRESHOLD u60) ;; Minimum for sensitive operations
(define-constant MAX_PERMISSIONS u20)
(define-constant CREDENTIAL_VALIDITY u525600) ;; 1 year in blocks

;; Data Variables
(define-data-var stakeholder-count uint u0)
(define-data-var admin-count uint u0)
(define-data-var suspended-count uint u0)
(define-data-var system-paused bool false)

;; Main Stakeholder Registry
(define-map stakeholders
  principal
  {
    role: (string-ascii 20),
    company-name: (string-utf8 200),
    registration-number: (string-ascii 50),
    primary-contact: (string-utf8 100),
    email: (string-utf8 100),
    physical-address: (string-utf8 300),
    country: (string-ascii 3), ;; ISO country code
    industry-sector: (string-ascii 50),
    registration-date: uint,
    status: uint,
    reputation-score: uint,
    kyc-level: uint,
    kyc-verified-at: uint,
    kyc-expires-at: uint,
    last-activity: uint,
    suspended-until: (optional uint),
    suspension-reason: (optional (string-utf8 200))
  })

;; Role-based Permissions
(define-map role-permissions
  (string-ascii 20) ;; role
  (list 20 (string-ascii 30))) ;; list of permissions

;; Individual Stakeholder Permissions (overrides or additions)
(define-map stakeholder-permissions
  principal
  {
    granted-permissions: (list 10 (string-ascii 30)),
    revoked-permissions: (list 10 (string-ascii 30)),
    custom-permissions: (list 5 (string-ascii 30))
  })

;; Stakeholder Relationships (who can interact with whom)
(define-map stakeholder-relationships
  {stakeholder-a: principal, stakeholder-b: principal}
  {
    relationship-type: (string-ascii 30), ;; "SUPPLIER", "CUSTOMER", "PARTNER", "AUDITOR"
    established-at: uint,
    established-by: principal,
    active: bool,
    trust-level: uint, ;; 1-5 scale
    interaction-count: uint
  })

;; Compliance and Audit Records
(define-map stakeholder-compliance
  principal
  {
    compliance-score: uint,
    last-audit-date: uint,
    next-audit-due: uint,
    violations-count: uint,
    certifications: (list 10 (string-ascii 64)),
    regulatory-status: (string-ascii 20),
    risk-category: (string-ascii 10) ;; "LOW", "MEDIUM", "HIGH"
  })

;; Activity and Performance Tracking
(define-map stakeholder-performance
  principal
  {
    total-transactions: uint,
    successful-transactions: uint,
    failed-transactions: uint,
    average-processing-time: uint, ;; in blocks
    quality-ratings: (list 100 uint), ;; Recent quality ratings
    customer-feedback-score: uint,
    on-time-delivery-rate: uint, ;; percentage
    last-performance-update: uint
  })

;; Delegation and Authorization
(define-map delegated-authorities
  {delegator: principal, delegate: principal}
  {
    permissions: (list 5 (string-ascii 30)),
    valid-from: uint,
    valid-until: uint,
    active: bool,
    delegation-reason: (string-utf8 200)
  })

;; Notification and Alert System
(define-map stakeholder-notifications
  {stakeholder: principal, notification-id: uint}
  {
    message: (string-utf8 300),
    priority: uint, ;; 1-5 scale
    notification-type: (string-ascii 30),
    created-at: uint,
    read: bool,
    action-required: bool
  })

(define-map stakeholder-notification-counts principal uint)

;; Private Helper Functions
(define-private (is-valid-role (role (string-ascii 20)))
  (or (is-eq role ROLE_MANUFACTURER)
      (is-eq role ROLE_SUPPLIER)
      (is-eq role ROLE_DISTRIBUTOR)
      (is-eq role ROLE_RETAILER)
      (is-eq role ROLE_LOGISTICS)
      (is-eq role ROLE_AUDITOR)
      (is-eq role ROLE_CERTIFIER)
      (is-eq role ROLE_REGULATOR)
      (is-eq role ROLE_CONSUMER)
      (is-eq role ROLE_ADMIN)))

(define-private (is-stakeholder-active (stakeholder principal))
  (match (map-get? stakeholders stakeholder)
    stakeholder-data
      (and (is-eq (get status stakeholder-data) STATUS_ACTIVE)
           (match (get suspended-until stakeholder-data)
             suspended-until (< suspended-until block-height)
             true))
    false))

(define-private (has-permission (stakeholder principal) (permission (string-ascii 30)))
  (let ((stakeholder-info (unwrap! (map-get? stakeholders stakeholder) false))
        (role (get role stakeholder-info))
        (role-perms (default-to (list) (map-get? role-permissions role)))
        (custom-perms (map-get? stakeholder-permissions stakeholder)))
    
    ;; Check if permission exists in role permissions or custom permissions
    (or (is-some (index-of role-perms permission))
        (match custom-perms
          perms (is-some (index-of (get granted-permissions perms) permission))
          false))))

(define-private (is-sufficient-reputation (stakeholder principal) (threshold uint))
  (match (map-get? stakeholders stakeholder)
    stakeholder-data (>= (get reputation-score stakeholder-data) threshold)
    false))

(define-private (is-kyc-valid (stakeholder principal) (required-level uint))
  (match (map-get? stakeholders stakeholder)
    stakeholder-data
      (and (>= (get kyc-level stakeholder-data) required-level)
           (> (get kyc-expires-at stakeholder-data) block-height))
    false))

(define-private (update-reputation (stakeholder principal) (change int))
  (match (map-get? stakeholders stakeholder)
    stakeholder-data
      (let ((current-rep (get reputation-score stakeholder-data))
            (new-rep (if (> change 0)
                        (min MAX_REPUTATION (+ current-rep (to-uint change)))
                        (max MIN_REPUTATION (- current-rep (to-uint (* change -1)))))))
        (map-set stakeholders stakeholder
                (merge stakeholder-data {reputation-score: new-rep}))
        true)
    false))

(define-private (get-next-notification-id (stakeholder principal))
  (+ (default-to u0 (map-get? stakeholder-notification-counts stakeholder)) u1))

(define-private (send-notification (stakeholder principal) 
                                 (message (string-utf8 300))
                                 (priority uint)
                                 (notification-type (string-ascii 30))
                                 (action-required bool))
  (let ((notification-id (get-next-notification-id stakeholder))
        (notification {
          message: message,
          priority: priority,
          notification-type: notification-type,
          created-at: block-height,
          read: false,
          action-required: action-required
        }))
    
    (map-set stakeholder-notifications {stakeholder: stakeholder, notification-id: notification-id} notification)
    (map-set stakeholder-notification-counts stakeholder notification-id)
    notification-id))

;; Read-Only Functions
(define-read-only (get-stakeholder (stakeholder principal))
  (map-get? stakeholders stakeholder))

(define-read-only (get-stakeholder-permissions (stakeholder principal))
  (map-get? stakeholder-permissions stakeholder))

(define-read-only (get-role-permissions (role (string-ascii 20)))
  (map-get? role-permissions role))

(define-read-only (get-stakeholder-compliance (stakeholder principal))
  (map-get? stakeholder-compliance stakeholder))

(define-read-only (get-stakeholder-performance (stakeholder principal))
  (map-get? stakeholder-performance stakeholder))

(define-read-only (get-relationship (stakeholder-a principal) (stakeholder-b principal))
  (map-get? stakeholder-relationships {stakeholder-a: stakeholder-a, stakeholder-b: stakeholder-b}))

(define-read-only (get-delegated-authority (delegator principal) (delegate principal))
  (map-get? delegated-authorities {delegator: delegator, delegate: delegate}))

(define-read-only (get-notification (stakeholder principal) (notification-id uint))
  (map-get? stakeholder-notifications {stakeholder: stakeholder, notification-id: notification-id}))

(define-read-only (check-permission (stakeholder principal) (permission (string-ascii 30)))
  (and (is-stakeholder-active stakeholder)
       (has-permission stakeholder permission)))

(define-read-only (get-system-stats)
  {total-stakeholders: (var-get stakeholder-count),
   active-admins: (var-get admin-count),
   suspended-stakeholders: (var-get suspended-count),
   system-paused: (var-get system-paused)})

(define-read-only (is-relationship-active (stakeholder-a principal) (stakeholder-b principal))
  (match (get-relationship stakeholder-a stakeholder-b)
    rel-data (get active rel-data)
    false))

;; Public Functions
(define-public (register-stakeholder
                 (stakeholder principal)
                 (role (string-ascii 20))
                 (company-name (string-utf8 200))
                 (registration-number (string-ascii 50))
                 (primary-contact (string-utf8 100))
                 (email (string-utf8 100))
                 (physical-address (string-utf8 300))
                 (country (string-ascii 3))
                 (industry-sector (string-ascii 50)))
  (begin
    (asserts! (not (var-get system-paused)) ERR_UNAUTHORIZED)
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (is-valid-role role) ERR_INVALID_ROLE)
    (asserts! (is-none (get-stakeholder stakeholder)) ERR_DUPLICATE_STAKEHOLDER)
    
    (let ((new-stakeholder {
            role: role,
            company-name: company-name,
            registration-number: registration-number,
            primary-contact: primary-contact,
            email: email,
            physical-address: physical-address,
            country: country,
            industry-sector: industry-sector,
            registration-date: block-height,
            status: STATUS_PENDING,
            reputation-score: u75, ;; Start with neutral reputation
            kyc-level: KYC_NONE,
            kyc-verified-at: u0,
            kyc-expires-at: u0,
            last-activity: block-height,
            suspended-until: none,
            suspension-reason: none
          }))
      
      ;; Register stakeholder
      (map-set stakeholders stakeholder new-stakeholder)
      
      ;; Initialize compliance record
      (map-set stakeholder-compliance stakeholder {
        compliance-score: u80,
        last-audit-date: u0,
        next-audit-due: (+ block-height CREDENTIAL_VALIDITY),
        violations-count: u0,
        certifications: (list),
        regulatory-status: "PENDING",
        risk-category: "MEDIUM"
      })
      
      ;; Initialize performance tracking
      (map-set stakeholder-performance stakeholder {
        total-transactions: u0,
        successful-transactions: u0,
        failed-transactions: u0,
        average-processing-time: u0,
        quality-ratings: (list),
        customer-feedback-score: u75,
        on-time-delivery-rate: u90,
        last-performance-update: block-height
      })
      
      ;; Initialize notification counter
      (map-set stakeholder-notification-counts stakeholder u0)
      
      ;; Send welcome notification
      (send-notification stakeholder 
                        u"Welcome to the supply chain network. Please complete KYC verification."
                        u3 "ONBOARDING" true)
      
      (var-set stakeholder-count (+ (var-get stakeholder-count) u1))
      (ok stakeholder))))

(define-public (activate-stakeholder (stakeholder principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    
    (match (get-stakeholder stakeholder)
      stakeholder-data
        (begin
          (asserts! (is-eq (get status stakeholder-data) STATUS_PENDING) ERR_INVALID_ROLE)
          
          (let ((updated-stakeholder (merge stakeholder-data {
                  status: STATUS_ACTIVE,
                  last-activity: block-height
                })))
            
            (map-set stakeholders stakeholder updated-stakeholder)
            
            ;; If admin role, increment admin count
            (if (is-eq (get role stakeholder-data) ROLE_ADMIN)
                (var-set admin-count (+ (var-get admin-count) u1))
                true)
            
            ;; Send activation notification
            (send-notification stakeholder
                             u"Your account has been activated. You can now access the system."
                             u4 "ACTIVATION" false)
            
            (ok true)))
      ERR_STAKEHOLDER_NOT_FOUND)))

(define-public (update-kyc-status (stakeholder principal)
                                (kyc-level uint)
                                (validity-period uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (<= kyc-level KYC_INSTITUTIONAL) ERR_INVALID_KYC)
    
    (match (get-stakeholder stakeholder)
      stakeholder-data
        (let ((updated-stakeholder (merge stakeholder-data {
                kyc-level: kyc-level,
                kyc-verified-at: block-height,
                kyc-expires-at: (+ block-height validity-period)
              })))
          
          (map-set stakeholders stakeholder updated-stakeholder)
          
          ;; Send KYC update notification
          (send-notification stakeholder
                           u"Your KYC verification has been updated. Please review your new access level."
                           u3 "KYC_UPDATE" false)
          
          (ok true))
      ERR_STAKEHOLDER_NOT_FOUND)))

(define-public (establish-relationship (other-stakeholder principal)
                                     (relationship-type (string-ascii 30))
                                     (trust-level uint))
  (begin
    (asserts! (is-stakeholder-active tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-stakeholder-active other-stakeholder) ERR_STAKEHOLDER_NOT_FOUND)
    (asserts! (and (>= trust-level u1) (<= trust-level u5)) ERR_INVALID_PERMISSION)
    
    (let ((relationship {
            relationship-type: relationship-type,
            established-at: block-height,
            established-by: tx-sender,
            active: true,
            trust-level: trust-level,
            interaction-count: u0
          }))
      
      ;; Establish bidirectional relationship
      (map-set stakeholder-relationships 
               {stakeholder-a: tx-sender, stakeholder-b: other-stakeholder} 
               relationship)
      
      (map-set stakeholder-relationships 
               {stakeholder-a: other-stakeholder, stakeholder-b: tx-sender} 
               relationship)
      
      ;; Notify both parties
      (send-notification other-stakeholder
                       u"A new business relationship has been established with you."
                       u3 "RELATIONSHIP" false)
      
      (ok true))))

(define-public (grant-custom-permission (stakeholder principal) (permission (string-ascii 30)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (is-stakeholder-active stakeholder) ERR_STAKEHOLDER_NOT_FOUND)
    
    (let ((current-perms (default-to 
                         {granted-permissions: (list),
                          revoked-permissions: (list),
                          custom-permissions: (list)}
                         (map-get? stakeholder-permissions stakeholder)))
          (updated-perms (merge current-perms {
            custom-permissions: 
              (unwrap! (as-max-len? 
                       (append (get custom-permissions current-perms) permission) u5) 
                      ERR_INVALID_PERMISSION)
          })))
      
      (map-set stakeholder-permissions stakeholder updated-perms)
      
      ;; Send notification
      (send-notification stakeholder
                       u"You have been granted additional system permissions."
                       u4 "PERMISSION_GRANT" false)
      
      (ok true))))

(define-public (suspend-stakeholder (stakeholder principal)
                                  (duration uint)
                                  (reason (string-utf8 200)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    
    (match (get-stakeholder stakeholder)
      stakeholder-data
        (let ((updated-stakeholder (merge stakeholder-data {
                status: STATUS_SUSPENDED,
                suspended-until: (some (+ block-height duration)),
                suspension-reason: (some reason)
              })))
          
          (map-set stakeholders stakeholder updated-stakeholder)
          (var-set suspended-count (+ (var-get suspended-count) u1))
          
          ;; Send suspension notification
          (send-notification stakeholder
                           u"Your account has been suspended. Please contact support for details."
                           u5 "SUSPENSION" true)
          
          ;; Update reputation negatively
          (update-reputation stakeholder -20)
          
          (ok true))
      ERR_STAKEHOLDER_NOT_FOUND)))

(define-public (record-transaction-performance (stakeholder principal)
                                             (success bool)
                                             (processing-time uint))
  (begin
    (asserts! (is-stakeholder-active tx-sender) ERR_UNAUTHORIZED)
    
    (match (map-get? stakeholder-performance stakeholder)
      perf-data
        (let ((updated-perf (merge perf-data {
                total-transactions: (+ (get total-transactions perf-data) u1),
                successful-transactions: (if success
                                          (+ (get successful-transactions perf-data) u1)
                                          (get successful-transactions perf-data)),
                failed-transactions: (if success
                                      (get failed-transactions perf-data)
                                      (+ (get failed-transactions perf-data) u1)),
                average-processing-time: (/ (+ (* (get average-processing-time perf-data) 
                                                 (get total-transactions perf-data))
                                              processing-time)
                                           (+ (get total-transactions perf-data) u1)),
                last-performance-update: block-height
              })))
          
          (map-set stakeholder-performance stakeholder updated-perf)
          
          ;; Update reputation based on performance
          (if success
              (update-reputation stakeholder 1)
              (update-reputation stakeholder -2))
          
          (ok true))
      ERR_STAKEHOLDER_NOT_FOUND)))

;; Admin Functions
(define-public (set-role-permissions (role (string-ascii 20)) (permissions (list 20 (string-ascii 30))))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (is-valid-role role) ERR_INVALID_ROLE)
    
    (map-set role-permissions role permissions)
    (ok true)))

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
