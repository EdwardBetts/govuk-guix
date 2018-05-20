(define-module (gds services govuk)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-26)
  #:use-module (gnu services)
  #:use-module (gnu services shepherd)
  #:use-module (gnu system shadow)
  #:use-module ((gnu packages admin)
                #:select (shadow))
  #:use-module (guix records)
  #:use-module (guix modules)
  #:use-module (guix gexp)
  #:use-module (guix utils)
  #:use-module (ice-9 match)
  #:use-module (guix packages)
  #:use-module (guix gexp)
  #:use-module (gnu packages base)
  #:use-module (gnu packages databases)
  #:use-module (gds packages govuk)
  #:use-module (gds services)
  #:use-module (gds services utils)
  #:use-module (gds services utils databases)
  #:use-module (gds services utils databases postgresql)
  #:use-module (gds services utils databases mysql)
  #:use-module (gds services utils databases mongodb)
  #:use-module (gds services utils databases elasticsearch)
  #:use-module (gds services utils databases rabbitmq)
  #:use-module (gds services govuk plek)
  #:use-module (gds services sidekiq)
  #:use-module (gds services delayed-job)
  #:use-module (gds services govuk signon)
  #:use-module (gds services govuk rummager)
  #:use-module (gds services govuk tailon)
  #:use-module (gds services govuk router)
  #:use-module (gds services govuk publishing-e2e-tests)
  #:use-module (gds services rails)
  #:export (<router-api-config>
            router-api-config
            router-api-config?
            router-api-config-nodes))

;;;
;;; Utilities
;;;


(define* (make-rails-app-using-plek-and-signon-service-type name
                                                            #:key
                                                            signon-plek-name)
  (let ((base-service-type
         (make-rails-app-using-plek-service-type name)))

    (define (update-service-startup-config-for-signon-application parameters)
      (let ((signon-application (find signon-application? parameters)))
        (if signon-application
            (map
             (lambda (parameter)
               (if (service-startup-config? parameter)
                   (service-startup-config-with-additional-environment-variables
                    parameter
                    `(("OAUTH_ID" . ,(signon-application-oauth-id
                                      signon-application))
                      ("OAUTH_SECRET" . ,(signon-application-oauth-secret
                                          signon-application))))
                   parameter))
             parameters)
            parameters)))

    (define (update-service-startup-config-for-signon-api-user parameters)
      (map
       (lambda (parameter)
         (if (service-startup-config? parameter)
             (service-startup-config-with-additional-environment-variables
              parameter
              (map
               (match-lambda
                 (($ <signon-authorisation> application-name token
                                            environment-variable)
                  (let ((name
                         (or environment-variable
                             (string-append
                              (string-map
                               (lambda (c)
                                 (if (eq? c #\space) #\_ c))
                               (string-upcase application-name))
                              "_BEARER_TOKEN"))))
                    (cons name token))))
               (concatenate
                (map
                 (match-lambda
                   (($ <signon-api-user> name email authorisation-permissions)
                    (map car authorisation-permissions)))
                 (filter signon-api-user? parameters)))))
             parameter))
       parameters))

    (define (update-signon-application parameters)
      (let ((plek-config (find plek-config? parameters)))
        (if plek-config
            (map
             (lambda (parameter)
               (if (signon-application? parameter)
                   (let ((service-uri
                          (if (eq? name 'authenticating-proxy)
                              (plek-config-draft-origin plek-config)
                              (service-uri-from-plek-config plek-config
                                                            (or signon-plek-name
                                                                name)))))
                     (signon-application
                      (inherit parameter)
                      (home-uri service-uri)
                      (redirect-uri
                       (string-append service-uri "/auth/gds/callback"))))
                   parameter))
             parameters)
            parameters)))

    (define (generic-rails-app-log-files name . rest)
      (let*
          ((string-name (symbol->string name))
           (ss (find shepherd-service? rest))
           (sidekiq-config (find sidekiq-config? rest))
           (sidekiq-service-name
            (string-append
             (symbol->string
              (first (shepherd-service-provision ss)))
             "-sidekiq")))
        (cons
         (string-append "/var/log/" string-name ".log")
         (if sidekiq-config
             (list
              (string-append "/var/log/" sidekiq-service-name ".log"))
             '()))))

    (service-type-extensions-modify-parameters
     (service-type
      (inherit base-service-type)
      (extensions
       (cons*
        (service-extension signon-service-type
                           (lambda (parameters)
                             (filter
                              (lambda (parameter)
                                (or (signon-application? parameter)
                                    (signon-api-user? parameter)
                                    (signon-user? parameter)))
                              parameters)))
        (service-extension govuk-tailon-service-type
                           (lambda (parameters)
                             (let ((log-files
                                    (apply
                                     generic-rails-app-log-files
                                     name
                                     parameters)))
                               (if (eq? (length log-files) 1)
                                   log-files
                                   (list
                                    (cons (symbol->string name)
                                          log-files))))))
        (service-type-extensions base-service-type))))
     (lambda (parameters)
       (update-service-startup-config-for-signon-application
        (update-service-startup-config-for-signon-api-user
         (update-signon-application parameters)))))))

;;;
;;; GOV.UK Content Schemas
;;;

(define-public govuk-content-schemas-service-type
  (shepherd-service-type
   'govuk-content-schemas
   (lambda (package)
     (shepherd-service
      (provision (list 'govuk-content-schemas))
      (documentation "Ensure /var/apps/govuk-content-schemas exists")
      (start
       #~(lambda _
           (use-modules (guix build utils))

           (if (not (file-exists? "/var/apps/govuk-content-schemas"))
               (begin
                 (mkdir-p "/var/apps")
                 (symlink #$package
                          "/var/apps/govuk-content-schemas")))
           #t))
   (stop #~(lambda _
             #f))
   (respawn? #f)))))

(define-public govuk-content-schemas-service
  (service govuk-content-schemas-service-type govuk-content-schemas))

;;;
;;; Signon
;;;

(define-public signon-service
  (service
   signon-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(signon))
           (requirement '(mysql loopback)))
          (service-startup-config)
          (plek-config) (rails-app-config) (@ (gds packages govuk) signon)
          (signon-config)
          (sidekiq-config
           (file "config/sidekiq.yml"))
          (mysql-connection-config
           (user "signon")
           (port "-")
           (database "signon_production")
           (password ""))
          (redis-connection-config))))

;;;
;;; Asset Manager
;;;

(define-public asset-manager-service-type
  (make-rails-app-using-plek-and-signon-service-type 'asset-manager))

(define-public asset-manager-service
  (service
   asset-manager-service-type
   (list (shepherd-service
          (inherit default-shepherd-service)
          (provision '(asset-manager))
          (requirement '(publishing-api signon redis)))
         (plek-config)
         (rails-app-config
          (precompiled-assets-are-environment-specific? #f))
         asset-manager
         (sidekiq-config
          (file "config/sidekiq.yml"))
         (signon-application
          (name "Asset Manager")
          (supported-permissions '("signin")))
         (service-startup-config
          (root-pre-startup-scripts
           `((mount-uploads
              .
              ,(with-imported-modules (source-module-closure
                                       '((guix build utils)
                                         (gnu build file-systems)))
                 #~(lambda ()
                     (use-modules (gds build utils)
                                  (gnu build file-systems))
                     (for-each
                      (lambda (directory)
                        (let ((app-dir
                               (string-append "/var/apps/asset-manager/" directory))
                              (storage-dir
                               (string-append "/var/lib/asset-manager/" directory)))
                          (mkdir-p storage-dir)
                          (bind-mount storage-dir app-dir)
                          (chmod app-dir #o777)))
                      '("uploads" "fake-s3"))
                     #t))))))
         (redis-connection-config)
         (mongodb-connection-config
          (database "asset_manager")))))

;;;
;;; Authenticating Proxy
;;;

(define-public authenticating-proxy-service-type
  (make-rails-app-using-plek-and-signon-service-type 'authenticating-proxy))

(define-public authenticating-proxy-service
  (service
   authenticating-proxy-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(authenticating-proxy))
           (requirement '(signon)))
         (plek-config)
         (rails-app-config
          (assets? #f))
         authenticating-proxy
         (service-startup-config)
         (signon-application
          (name "Content Preview")
          (supported-permissions '("signin")))
         (mongodb-connection-config
          (database "authenticating_proxy")))))

;;;
;;; Calculators
;;;

(define-public calculators-service-type
  (make-rails-app-using-plek-and-signon-service-type 'calculators))

(define-public calculators-service
  (service
   calculators-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(calculators))
           (requirement '(publishing-api signon)))
          (plek-config) (rails-app-config) calculators
          (service-startup-config))))

;;;
;;; Calendars
;;;

(define-public calendars-service-type
  (make-rails-app-using-plek-and-signon-service-type 'calendars))

(define-public calendars-service
  (service
   calendars-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(calendars))
           (requirement '(publishing-api signon)))
          (plek-config) (rails-app-config) calendars
          (service-startup-config))))

;;;
;;; Collections
;;;

(define-public collections-service-type
  (make-rails-app-using-plek-and-signon-service-type 'collections))

(define-public collections-service
  (service
   collections-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(collections))
           (requirement '(content-store static rummager)))
         (plek-config) (rails-app-config) collections
         (service-startup-config
          (environment-variables
           '(("GOVUK_APP_NAME" . "collections")))))))

(define-public draft-collections-service-type
  (make-rails-app-using-plek-and-signon-service-type 'draft-collections))

(define-public draft-collections-service
  (service
   draft-collections-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(draft-collections))
           (requirement '(draft-content-store draft-static rummager)))
          (plek-config) (rails-app-config) collections
          (service-startup-config
           (environment-variables
            '(("GOVUK_APP_NAME" . "draft-collections")))))))

;;;
;;; Collections Publisher
;;;

(define-public collections-publisher-service-type
  (make-rails-app-using-plek-and-signon-service-type 'collections-publisher))

(define-public collections-publisher-service
  (service
   collections-publisher-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(collections-publisher))
           (requirement '(publishing-api signon)))
          (plek-config) (rails-app-config) collections-publisher
          (signon-application
           (name "Collections Publisher")
           (supported-permissions '("signin" "GDS Editor")))
          (signon-api-user
           (name "Collections Publisher")
           (email "collections-publisher@guix-dev.gov.uk")
           (authorisation-permissions
            (list
             (cons
              (signon-authorisation
               (application-name "Publishing API"))
              '("signin")))))
          (service-startup-config)
          (sidekiq-config
           (file "config/sidekiq.yml"))
          (redis-connection-config)
          (memcached-connection-config)
          (mysql-connection-config
           (user "collections-pub")
           (password (random-base16-string 30))
           (database "collections_publisher_production")))))

;;;
;;; Contacts Admin
;;;

(define-public contacts-admin-service-type
  (make-rails-app-using-plek-and-signon-service-type 'contacts-admin))

(define-public contacts-admin-service
  (service
   contacts-admin-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(contacts-admin))
           (requirement '(publishing-api whitehall signon)))
          (plek-config) (rails-app-config) contacts-admin
          (signon-application
           (name "Contacts Admin")
           (supported-permissions '("signin")))
          (signon-api-user
           (name "Contacts Admin")
           (email "contacts-admin@guix-dev.gov.uk")
           (authorisation-permissions
            (list
             (cons
              (signon-authorisation
               (application-name "Publishing API"))
              '("signin")))))
          (service-startup-config)
          (redis-connection-config)
          (mysql-connection-config
           (user "contacts")
           (password (random-base16-string 30))
           (database "contacts_production")))))

;;;
;;; Content Performance Manager
;;;

(define-public content-performance-manager-service-type
  (make-rails-app-using-plek-and-signon-service-type 'content-performance-manager))

(define-public content-performance-manager-service
  (service
   content-performance-manager-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(content-performance-manager))
           (requirement '(publishing-api whitehall signon)))
          (sidekiq-config
           (file "config/sidekiq.yml"))
          (plek-config) (rails-app-config) content-performance-manager
          (signon-application
           (name "Content Performance Manager")
           (supported-permissions '("signin" "inventory_management")))
          (signon-api-user
           (name "Content Performance Manager")
           (email "content-performance-manager@guix-dev.gov.uk")
           (authorisation-permissions
            (list
             (cons
              (signon-authorisation
               (application-name "Publishing API"))
              '("signin")))))
          (service-startup-config)
          (redis-connection-config)
          (postgresql-connection-config
           (user "content_performance_manager")
           (database "content_performance_manager_production")))))

;;;
;;; Content Audit Tool
;;;

(define-public content-audit-tool-service-type
  (make-rails-app-using-plek-and-signon-service-type 'content-audit-tool))

(define-public content-audit-tool-service
  (service
   content-audit-tool-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(content-audit-tool))
           (requirement '(publishing-api whitehall signon)))
          (sidekiq-config
           (file "config/sidekiq.yml"))
          (plek-config) (rails-app-config) content-audit-tool
          (signon-application
           (name "Content Audit Tool")
           (supported-permissions '("signin")))
          (signon-api-user
           (name "Content Audit Tool")
           (email "content-audit-tool@guix-dev.gov.uk")
           (authorisation-permissions
            (list
             (cons
              (signon-authorisation
               (application-name "Publishing API"))
              '("signin")))))
          (service-startup-config)
          (redis-connection-config)
          (postgresql-connection-config
           (user "content_audit_tool")
           (database "content_audit_tool_production")))))

;;;
;;; Email Alert API
;;;

(define-public email-alert-api-service-type
  (make-rails-app-using-plek-and-signon-service-type 'email-alert-api))

(define-public email-alert-api-service
  (service
   email-alert-api-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(email-alert-api))
           (requirement '(postgres)))
          (plek-config) (rails-app-config) email-alert-api
          (service-startup-config)
          (redis-connection-config)
          (sidekiq-config
           (file "config/sidekiq.yml"))
          (postgresql-connection-config
           (user "email-alert-api")
           (database "email_alert_api")))))

;;;
;;; Email Alert Frontend
;;;

(define-public email-alert-frontend-service-type
  (make-rails-app-using-plek-and-signon-service-type 'email-alert-frontend))

(define-public email-alert-frontend-service
  (service
   email-alert-frontend-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(email-alert-frontend))
           (requirement '()))
          (plek-config) (rails-app-config) email-alert-frontend
          (service-startup-config))))

(define-public draft-email-alert-frontend-service-type
  (make-rails-app-using-plek-and-signon-service-type 'draft-email-alert-frontend))

(define-public draft-email-alert-frontend-service
  (service
   draft-email-alert-frontend-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(draft-email-alert-frontend))
           (requirement '()))
          (plek-config) (rails-app-config) email-alert-frontend
          (service-startup-config))))

;;;
;;; Email Alert Service
;;;

;; TODO: This is not actually a Rails app...
(define-public email-alert-service-type
  (make-rails-app-using-plek-and-signon-service-type 'email-alert-service))

(define-public email-alert-service-service
  (service
   email-alert-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(email-alert-service))
           (requirement '()))
         (plek-config)
         (rails-app-config
          (run-with "bin/email_alert_service"))
         email-alert-service
         (service-startup-config)
         (redis-connection-config))))

;;;
;;; Feedback
;;;

(define-public feedback-service-type
  (make-rails-app-using-plek-and-signon-service-type 'feedback))

(define-public feedback-service
  (service
   feedback-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(feedback))
           (requirement '(publishing-api support-api signon)))
          (plek-config) (rails-app-config) feedback
          (service-startup-config))))

;;;
;;; Finder Frontend
;;;

(define-public finder-frontend-service-type
  (make-rails-app-using-plek-and-signon-service-type 'finder-frontend))

(define-public finder-frontend-service
  (service
   finder-frontend-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(finder-frontend))
           (requirement '(content-store rummager static)))
          (plek-config) (rails-app-config) finder-frontend
          (service-startup-config
           (environment-variables
            '(("GOVUK_APP_NAME" . "finder-frontend"))))
)))

(define-public draft-finder-frontend-service-type
  (make-rails-app-using-plek-and-signon-service-type 'draft-finder-frontend))

(define-public draft-finder-frontend-service
  (service
   draft-finder-frontend-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(draft-finder-frontend))
           (requirement '(draft-content-store rummager draft-static)))
          (plek-config) (rails-app-config) finder-frontend
          (service-startup-config
           (environment-variables
            '(("GOVUK_APP_NAME" . "draft-finder-frontend")))))))

;;;
;;; HMRC Manuals API
;;;

(define-public hmrc-manuals-api-service-type
  (make-rails-app-using-plek-and-signon-service-type 'hmrc-manuals-api))

(define-public hmrc-manuals-api-service
  (service
   hmrc-manuals-api-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(hmrc-manuals-api))
           (requirement '(publishing-api signon)))
          (plek-config) (rails-app-config) hmrc-manuals-api
          (signon-application
           (name "HMRC Manuals API")
           (supported-permissions '("signin")))
          (signon-api-user
           (name "HMRC Manuals API")
           (email "hmrc-manuals-api@guix-dev.gov.uk")
           (authorisation-permissions
            (list
             (cons
              (signon-authorisation
               (application-name "Publishing API"))
              '("signin")))))
          (service-startup-config)
          (redis-connection-config))))

;;;
;;; Licence Finder
;;;

(define-public licence-finder-service-type
  (make-rails-app-using-plek-and-signon-service-type 'licencefinder))

(define-public licence-finder-service
  (service
   licence-finder-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(licence-finder))
           (requirement '(publishing-api signon)))
          (plek-config) (rails-app-config) licence-finder
          (signon-api-user
           (name "Licence Finder")
           (email "licence-finder@guix-dev.gov.uk")
           (authorisation-permissions
            (list
             (cons
              (signon-authorisation
               (application-name "Publishing API"))
              '("signin")))))
          (service-startup-config)
          (mongodb-connection-config
           (database "licence_finder")))))

;;;
;;; Link Checker API
;;;

(define-public link-checker-api-service-type
  (make-rails-app-using-plek-and-signon-service-type 'link-checker-api))

(define-public link-checker-api-service
  (service
   link-checker-api-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(link-checker-api))
           (requirement '(signon)))
         (plek-config)
         (rails-app-config
          (assets? #f))
         (sidekiq-config
          (file "config/sidekiq.yml"))
         link-checker-api
         (signon-api-user
          (name "Link Checker API")
          (email "link-checker-api@guix-dev.gov.uk")
          (authorisation-permissions (list)))
         (service-startup-config)
         (redis-connection-config)
         (mongodb-connection-config
          (database "link_checker_api")))))

;;;
;;; Local Links Manager
;;;

(define-public local-links-manager-service-type
  (make-rails-app-using-plek-and-signon-service-type 'local-links-manager))

(define-public local-links-manager-service
  (service
   local-links-manager-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(local-links-manager))
           (requirement '(publishing-api signon)))
          (plek-config) (rails-app-config) local-links-manager
          (signon-api-user
           (name "Local Links Manager")
           (email "local-links-manager@guix-dev.gov.uk")
           (authorisation-permissions
            (list
             (cons
              (signon-authorisation
               (application-name "Publishing API"))
              '("signin")))))
          (signon-application
           (name "Local Links Manager")
           (supported-permissions '("signin")))
          (service-startup-config)
          (redis-connection-config)
          (postgresql-connection-config
           (user "local_links_manager")
           (database "local-links-manager_production")))))

;;;
;;; Imminence
;;;

(define-public imminence-service-type
  (make-rails-app-using-plek-and-signon-service-type 'imminence))

(define-public imminence-service
  (service
   imminence-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(imminence))
           (requirement '(publishing-api signon redis)))
          (plek-config) (rails-app-config) imminence
          (signon-application
           (name "Imminence")
           (supported-permissions '("signin")))
          (sidekiq-config
           (file "config/sidekiq.yml"))
          (service-startup-config)
          (redis-connection-config)
          (mongodb-connection-config
           (database "imminence")))))

;;;
;;; Manuals Frontend
;;;

(define-public manuals-frontend-service-type
  (make-rails-app-using-plek-and-signon-service-type 'manuals-frontend))

(define-public manuals-frontend-service
  (service
   manuals-frontend-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(manuals-frontend))
           (requirement '(publishing-api signon)))
          (plek-config) (rails-app-config) manuals-frontend
          (service-startup-config)
          (mongodb-connection-config
           (database "manuals_frontend")))))

(define-public draft-manuals-frontend-service-type
  (make-rails-app-using-plek-and-signon-service-type 'draft-manuals-frontend))

(define-public draft-manuals-frontend-service
  (service
   draft-manuals-frontend-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(draft-manuals-frontend))
           (requirement '(publishing-api signon)))
          (plek-config) (rails-app-config) manuals-frontend
          (service-startup-config)
          (mongodb-connection-config
           (database "manuals_frontend")))))

;;;
;;; Manuals Publisher
;;;

(define-public manuals-publisher-service-type
  (make-rails-app-using-plek-and-signon-service-type 'manuals-publisher))

(define-public manuals-publisher-service
  (service
   manuals-publisher-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(manuals-publisher))
           (requirement '(publishing-api
                          signon
                          whitehall))) ;; Whitehall required for the Organisation API
          (plek-config) (rails-app-config) manuals-publisher
          (signon-application
           (name "Manuals Publisher")
           (supported-permissions '("signin" "editor" "gds_editor")))
          (signon-api-user
           (name "Manuals Publisher")
           (email "manuals-publisher@guix-dev.gov.uk")
           (authorisation-permissions
            (list
             (cons
              (signon-authorisation
               (application-name "Publishing API"))
              '("signin")))))
          (service-startup-config)
          (sidekiq-config
           (file "config/sidekiq.yml"))
          (redis-connection-config)
          (mongodb-connection-config
           (database "manuals_publisher")))))

;;;
;;; Policy Publisher
;;;

(define-public policy-publisher-service-type
  (make-rails-app-using-plek-and-signon-service-type 'policy-publisher))

(define-public policy-publisher-service
  (service
   policy-publisher-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(policy-publisher))
           (requirement '(publishing-api signon)))
          (plek-config) (rails-app-config) policy-publisher
          (signon-application
           (name "Policy Publisher")
           (supported-permissions '("signin")))
          (signon-api-user
           (name "Policy Publisher")
           (email "policy-publisher@guix-dev.gov.uk")
           (authorisation-permissions
            (list
             (cons
              (signon-authorisation
               (application-name "Publishing API"))
              '("signin")))))
          (service-startup-config)
          (postgresql-connection-config
           (user "policy_publisher")
           (database "policy-publisher_production")))))

;;;
;;; Release
;;;

(define-public release-service-type
  (make-rails-app-using-plek-and-signon-service-type 'release))

(define-public release-service
  (service
   release-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(release))
           (requirement '(publishing-api signon)))
          (plek-config) (rails-app-config) release
          (signon-application
           (name "Release")
           (supported-permissions '("signin" "deploy")))
          (service-startup-config)
          (mysql-connection-config
           (user "release")
           (port "-")
           (database "release_production")
           (password "")))))

;;;
;;; Search Admin
;;;

(define-public search-admin-service-type
  (make-rails-app-using-plek-and-signon-service-type 'search-admin-publisher))

(define-public search-admin-service
  (service
   search-admin-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(search-admin))
           (requirement '(publishing-api signon)))
          (plek-config) (rails-app-config) search-admin
          (signon-application
           (name "Search Admin")
           (supported-permissions '("signin")))
          (service-startup-config)
          (mysql-connection-config
           (user "search_admin")
           (port "-")
           (database "search_admin_production")
           (password "")))))

;;;
;;; Service Manual Publisher
;;;

(define-public service-manual-publisher-service-type
  (make-rails-app-using-plek-and-signon-service-type 'service-manual-publisher))

(define-public service-manual-publisher-service
  (service
   service-manual-publisher-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(service-manual-publisher))
           (requirement '(publishing-api signon)))
          (plek-config) (rails-app-config) service-manual-publisher
          (signon-application
           (name "Service Manual Publisher")
           (supported-permissions '("signin" "gds_editor")))
          (signon-api-user
           (name "Service Manual Publisher")
           (email "service-manual-publisher@guix-dev.gov.uk")
           (authorisation-permissions
            (list
             (cons
              (signon-authorisation
               (application-name "Publishing API"))
              '("signin")))))
          (service-startup-config)
          (postgresql-connection-config
           (user "service_manual_publisher")
           (database "service-manual-publisher_production")))))

;;;
;;; Service Manual Frontend
;;;

(define-public service-manual-frontend-service-type
  (make-rails-app-using-plek-and-signon-service-type 'service-manual-frontend))

(define-public service-manual-frontend-service
  (service
   service-manual-frontend-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(service-manual-frontend))
           (requirement '(publishing-api signon)))
          (plek-config) (rails-app-config) service-manual-frontend
          (service-startup-config))))

(define-public draft-service-manual-frontend-service-type
  (make-rails-app-using-plek-and-signon-service-type 'draft-service-manual-frontend))

(define-public draft-service-manual-frontend-service
  (service
   draft-service-manual-frontend-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(draft-service-manual-frontend))
           (requirement '(publishing-api signon)))
          (plek-config) (rails-app-config) service-manual-frontend
          (service-startup-config))))

;;;
;;; Short Url Manager
;;;

(define-public short-url-manager-service-type
  (make-rails-app-using-plek-and-signon-service-type 'short-url-manager))

(define-public short-url-manager-service
  (service
   short-url-manager-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(short-url-manager))
           (requirement '(publishing-api signon)))
          (plek-config) (rails-app-config) short-url-manager
          (signon-application
           (name "Short URL Manager")
           (supported-permissions '("signin" "manage_short_urls" "request_short_urls")))
          (signon-api-user
           (name "Short URL Manager")
           (email "short-url-manager@guix-dev.gov.uk")
           (authorisation-permissions
            (list
             (cons
              (signon-authorisation
               (application-name "Publishing API"))
              '("signin")))))
          (service-startup-config)
          (mongodb-connection-config
           (database "short_url_manager")))))

;;;
;;; Smart Answers
;;;

(define-public smart-answers-service-type
  (make-rails-app-using-plek-and-signon-service-type 'smartanswers))

(define-public smart-answers-service
  (service
   smart-answers-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(smart-answers))
           (requirement '(publishing-api
                          signon
                          content-store
                          imminence
                          static
                          whitehall)))
          (plek-config) (rails-app-config) smart-answers
          (service-startup-config))))

;;;
;;; Smokey
;;;


(define (smokey-start-script environment-variables package)
  (program-file
   (string-append "start-smokey")
   (with-imported-modules '((guix build utils)
                            (gnu services herd))
    #~(let ((bundle (string-append #$package "/bin/bundle")))
        (use-modules (guix build utils)
                     (gnu services herd)
                     (srfi srfi-26)
                     (ice-9 popen)
                     (ice-9 rw)
                     (ice-9 rdelim))

        (mkdir-p "/var/apps/smokey")

        (for-each
         (lambda (env-var)
           (setenv (car env-var) (cdr env-var)))
         '#$environment-variables)
        (chdir #$package)
        (let
            ((result
              (zero? (system*
                      bundle
                      "exec"
                      "rake"))))

          result)))))

(define (smokey-activation environment-variables package)
  (with-imported-modules (source-module-closure
                          '((guix build syscalls)
                            (gnu build file-systems)))
    #~(begin
        (use-modules (guix build utils)
                     (gnu build file-systems)
                     (guix build syscalls)
                     (ice-9 match)
                     (ice-9 ftw)
                     (srfi srfi-26))
        (let* ((root-directory "/var/apps/smokey"))
          (if (file-exists? root-directory)
              (begin
                (mkdir-p (string-append root-directory "/bin"))
                (mount "tmpfs" (string-append root-directory "/bin") "tmpfs")
                (copy-recursively
                 (string-append #$package "/bin")
                 (string-append root-directory "/bin")
                 #:log (%make-void-port "w")
                 #:follow-symlinks? #f)
                (substitute* (find-files (string-append root-directory "/bin")
                                         (lambda (name stat)
                                           (access? name X_OK)))
                  (((string-append #$package "/bin"))
                   "${BASH_SOURCE%/*}"))
                (substitute* (find-files (string-append root-directory "/bin")
                                         (lambda (name stat)
                                           (access? name X_OK)))
                  (("File\\.expand_path\\([\"']\\.\\./spring[\"'], __FILE__\\)")
                   "File.expand_path('../.spring-real', __FILE__)"))
                (for-each
                 (lambda (path)
                   (mkdir-p (string-append root-directory path))
                   (chmod (string-append root-directory path) #o777))
                 '("/tmp" "/log")))
              (begin
                (mkdir-p root-directory)
                (bind-mount #$package root-directory)

                (for-each
                 (lambda (file)
                   (if (file-exists? file)
                       (mount "tmpfs" file "tmpfs")))
                 (map
                  (lambda (dir)
                    (string-append root-directory "/" dir))
                  '("log" "public")))))

          (let* ((dir (string-append "/tmp/env.d/"))
                 (file (string-append dir "smokey")))
            (mkdir-p dir)
            (call-with-output-file file
              (lambda (port)
                (for-each
                 (lambda (env-var)
                   (simple-format port "export ~A=\"~A\"\n" (car env-var) (cdr env-var)))
                 '#$environment-variables))))))))

(define-public smokey-service-type
  (service-type
   (name 'smokey)
   (extensions
    (list
     (service-extension
      activation-service-type
      (match-lambda
        ((plek-config package)
         (smokey-activation
          (plek-config->environment-variables plek-config)
          package))))
     (service-extension
      shepherd-root-service-type
      (match-lambda
        ((plek-config package)
         (let* ((start-script
                 (smokey-start-script
                  (plek-config->environment-variables plek-config)
                  package)))
           (list
            (shepherd-service
             (provision (list 'smokey))
             (documentation "Smokey")
             (requirement '(smart-answers))
             (respawn? #f)
             (start #~(make-forkexec-constructor #$start-script))
             (stop #~(make-kill-destructor))))))))))))

(define-public smokey-service
  (service
   smokey-service-type
   (list (plek-config) smokey)))

;;;
;;; Support
;;;

(define-public support-service-type
  (make-rails-app-using-plek-and-signon-service-type 'support))

(define-public support-service
  (service
   support-service-type
   (list (shepherd-service
          (inherit default-shepherd-service)
          (provision '(support))
          (requirement '(support-api signon)))
         (signon-application
          (name "Support")
          (supported-permissions '("signin")))
         (plek-config) (rails-app-config) support
         (redis-connection-config)
         (service-startup-config))))

;;;
;;; Support API
;;;

(define-public support-api-service-type
  (make-rails-app-using-plek-and-signon-service-type 'support-api))

(define-public support-api-service
  (service
   support-api-service-type
   (list (shepherd-service
          (inherit default-shepherd-service)
          (provision '(support-api))
          (requirement '(publishing-api signon)))
         (plek-config) (rails-app-config) support-api
         (service-startup-config)
         (sidekiq-config
          (file "config/sidekiq.yml"))
         (redis-connection-config)
         (postgresql-connection-config
          (user "support-api")
          (database "support_api")))))

;;;
;;; Travel Advice Publisher
;;;

(define-public travel-advice-publisher-service-type
  (make-rails-app-using-plek-and-signon-service-type 'travel-advice-publisher))

(define-public travel-advice-publisher-service
  (service
   travel-advice-publisher-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(travel-advice-publisher))
           (requirement '(publishing-api signon static rummager asset-manager)))
          (plek-config) (rails-app-config) travel-advice-publisher
          (signon-application
           (name "Travel Advice Publisher")
           (supported-permissions '("signin" "gds_editor")))
          (signon-api-user
           (name "Travel Advice Publisher")
           (email "travel-advice-publisher@guix-dev.gov.uk")
           (authorisation-permissions
            (list
             (cons
              (signon-authorisation
               (application-name "Publishing API"))
              '("signin"))
             (cons
              (signon-authorisation
               (application-name "Asset Manager"))
              '("signin")))))
          (service-startup-config)
          (redis-connection-config)
          (sidekiq-config
           (file "config/sidekiq.yml"))
          (mongodb-connection-config
           (database "travel_advice_publisher")))))

;;;
;;; Publishing API Service
;;;

(define-public publishing-api-service-type
  (make-rails-app-using-plek-and-signon-service-type 'publishing-api))

(define-public publishing-api-service
  (service
   publishing-api-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(publishing-api))
           (requirement '(content-store draft-content-store signon
                          govuk-content-schemas redis loopback postgres
                          rabbitmq memcached)))
         (service-startup-config-add-pre-startup-scripts
          (service-startup-config
           (environment-variables
            '(("GOVUK_CONTENT_SCHEMAS_PATH" . "/var/apps/govuk-content-schemas"))))
          `((setup-exchange
             . ,#~(lambda ()
                    (run-command "rake" "setup_exchange")))))
          (plek-config)
          (rails-app-config
           (assets? #f))
          publishing-api
          (signon-application
           (name "Publishing API")
           (supported-permissions '("signin" "view_all")))
          (sidekiq-config
           (file "config/sidekiq.yml"))
          (memcached-connection-config)
          (postgresql-connection-config
           (user "publishing-api")
           (port "5432")
           (database "publishing_api_production"))
          (rabbitmq-connection-config (user "publishing_api")
                                      (password "publishing_api"))
          (redis-connection-config))))

;;;
;;; Content store
;;;

(define-public content-store-service-type
  (make-rails-app-using-plek-and-signon-service-type 'content-store))

(define-public content-store-service
  (service
   content-store-service-type
   (list (shepherd-service
           (inherit default-shepherd-service)
           (provision '(content-store))
           (requirement '(router-api mongodb)))
          (service-startup-config)
          (plek-config)
          (rails-app-config
           (assets? #f))
          content-store
          (mongodb-connection-config
           (database "content-store")))))

(define-public draft-content-store-service-type
  (make-rails-app-using-plek-service-type 'draft-content-store))

(define-public draft-content-store-service
  (service
   draft-content-store-service-type
   (list (shepherd-service
          (inherit default-shepherd-service)
          (provision '(draft-content-store))
          (requirement '(draft-router-api mongodb)))
         (service-startup-config)
         (plek-config)
         (rails-app-config
          (assets? #f))
         content-store
         (mongodb-connection-config
          (database "draft-content-store")))))

;;;
;;; Specialist Publisher
;;;

(define-public specialist-publisher-service-type
  (make-rails-app-using-plek-and-signon-service-type 'specialist-publisher))

(define-public specialist-publisher-service
  (service
   specialist-publisher-service-type
   (list (shepherd-service
          (inherit default-shepherd-service)
          (provision '(specialist-publisher))
          (requirement '(publishing-api asset-manager signon mongodb nginx)))
         (plek-config) (rails-app-config) specialist-publisher
         (signon-application
          (name "Specialist Publisher")
          (supported-permissions '("signin" "editor" "gds_editor")))
         (signon-api-user
          (name "Specialist Publisher")
          (email "specialist-publisher@guix-dev.gov.uk")
          (authorisation-permissions
           (list
            (cons
             (signon-authorisation
              (application-name "Publishing API"))
             '("signin"))
            (cons
             (signon-authorisation
              (application-name "Asset Manager"))
             '("signin")))))
         (service-startup-config)
         (mongodb-connection-config
          (database "specialist_publisher"))
         (redis-connection-config))))

;;;
;;; Government Frontend
;;;

(define-public government-frontend-service-type
  (make-rails-app-using-plek-and-signon-service-type 'government-frontend))

(define-public government-frontend-service
  (service
   government-frontend-service-type
   (list (shepherd-service
          (inherit default-shepherd-service)
          (provision '(government-frontend))
          (requirement '(content-store static)))
         (service-startup-config
          (environment-variables
           '(("GOVUK_APP_NAME" . "government-frontend"))))
         (memcached-connection-config)
         (plek-config) (rails-app-config) government-frontend)))

(define-public draft-government-frontend-service-type
  (make-rails-app-using-plek-and-signon-service-type 'draft-government-frontend))

(define-public draft-government-frontend-service
  (service
   draft-government-frontend-service-type
   (list (shepherd-service
          (inherit default-shepherd-service)
          (provision '(draft-government-frontend))
          (requirement '(draft-content-store draft-static)))
         (service-startup-config
          (environment-variables
           '(("GOVUK_APP_NAME" . "draft-government-frontend"))))
         (memcached-connection-config)
         (plek-config) (rails-app-config) government-frontend)))

;;;
;;; Frontend
;;;

(define-public frontend-service-type
  (make-rails-app-using-plek-and-signon-service-type 'frontend))

(define-public frontend-service
  (service
   frontend-service-type
   (list (shepherd-service
          (inherit default-shepherd-service)
          (provision '(frontend))
          (requirement '(static
                         rummager
                         content-store
                         ;; For publishing special routes
                         publishing-api)))
         (service-startup-config-add-pre-startup-scripts
          (service-startup-config
           (environment-variables
            '(("GOVUK_APP_NAME" . "frontend"))))
          `((publish-special-routes
             . ,#~(lambda ()
                    (run-command "rake" "publishing_api:publish_special_routes")))))
         (signon-api-user
          (name "Frontend")
          (email "frontend@guix-dev.gov.uk")
          (authorisation-permissions
           (list
            (cons
             (signon-authorisation
              (application-name "Publishing API"))
             '("signin")))))
         (plek-config) (rails-app-config) frontend)))

(define-public draft-frontend-service-type
  (make-rails-app-using-plek-and-signon-service-type 'draft-frontend))

(define-public draft-frontend-service
  (service
   draft-frontend-service-type
   (list (shepherd-service
          (inherit default-shepherd-service)
          (provision '(draft-frontend))
          (requirement '(draft-static rummager draft-content-store)))
         (service-startup-config
          (environment-variables
           '(("GOVUK_APP_NAME" . "draft-frontend"))))
         (signon-api-user
          (name "Draft Frontend")
          (email "draft-frontend@guix-dev.gov.uk")
          (authorisation-permissions
           (list
            (cons
             (signon-authorisation
              (application-name "Publishing API"))
             '("signin")))))
         (plek-config) (rails-app-config) frontend)))

;;;
;;; Publisher
;;;

(define-public publisher-service-type
  (make-rails-app-using-plek-and-signon-service-type 'publisher))

(define-public publisher-service
  (service
   publisher-service-type
   (list (shepherd-service
          (inherit default-shepherd-service)
          (provision '(publisher))
          (requirement '(publishing-api frontend draft-frontend
                         rummager asset-manager calendars signon)))
         (service-startup-config)
         (plek-config) (rails-app-config) publisher
         (redis-connection-config)
         (signon-application
          (name "Publisher")
          (supported-permissions '("signin" "skip_review")))
         (signon-api-user
          (name "Publisher")
          (email "publisher@guix-dev.gov.uk")
          (authorisation-permissions
           (list
            (cons
             (signon-authorisation
              (application-name "Publishing API"))
             '("signin"))
            (cons
             (signon-authorisation
              (application-name "Asset Manager")
              (environment-variable "PUBLISHER_ASSET_MANAGER_CLIENT_BEARER_TOKEN"))
             '("signin")))))
         (sidekiq-config
          (file "config/sidekiq.yml"))
         (mongodb-connection-config
          (database "govuk_content_production")))))

;;;
;;; Router
;;;

(define default-router-database-connection-configs
  (list
   (mongodb-connection-config
    (database "router"))))

(define-public router-service-type
  (make-router-service-type 'router))

(define-public router-service
  (service
   router-service-type
   (cons* (router-config) router
          default-router-database-connection-configs)))

(define default-draft-router-database-connection-configs
  (list
   (mongodb-connection-config
    (database "draft-router"))))

(define-public draft-router-service-type
  (make-router-service-type 'draft-router))

(define-public draft-router-service
  (service
   draft-router-service-type
   (cons* (router-config) router
          default-draft-router-database-connection-configs)))

;;;
;;; Router API
;;;

(define-record-type* <router-api-config>
  router-api-config make-router-api-config
  router-api-config?
  (router-nodes router-api-config-router-nodes
                (default '())))

(define-public router-api-service-type
  (make-rails-app-using-plek-and-signon-service-type 'router-api))

(define-public router-api-service
  (service
   router-api-service-type
   (cons* (shepherd-service
           (inherit default-shepherd-service)
           (provision '(router-api))
           (requirement '(router)))
          (service-startup-config)
          (plek-config)
          (rails-app-config
           (assets? #f))
          router-api
          (router-api-config)
          default-router-database-connection-configs)))

(define-public draft-router-api-service-type
  (make-rails-app-using-plek-and-signon-service-type 'draft-router-api))

(define-public draft-router-api-service
  (service
   draft-router-api-service-type
   (cons* (shepherd-service
           (inherit default-shepherd-service)
           (provision '(draft-router-api))
           (requirement '(draft-router)))
          (service-startup-config)
          (plek-config)
          (rails-app-config
           (assets? #f))
          router-api
          (router-api-config)
          default-draft-router-database-connection-configs)))

;;;
;;; Content Tagger
;;;

(define-public content-tagger-service-type
  (make-rails-app-using-plek-and-signon-service-type 'content-tagger))

(define-public content-tagger-service
  (service
   content-tagger-service-type
   (list (shepherd-service
          (inherit default-shepherd-service)
          (provision '(content-tagger))
          (requirement '(publishing-api signon rummager)))
         (service-startup-config)
         (signon-application
          (name "Content Tagger")
          (supported-permissions '("signin" "GDS Editor" "Tagathon participant")))
         (signon-api-user
          (name "Content Tagger")
          (email "content-tagger@guix-dev.gov.uk")
          (authorisation-permissions
           (list
            (cons
             (signon-authorisation
              (application-name "Publishing API"))
             '("signin")))))
         (plek-config) (rails-app-config) content-tagger
         (sidekiq-config
          (file "config/sidekiq.yml"))
         (postgresql-connection-config
          (user "content_tagger")
          (port "5432")
          (database "content_tagger_production")))))

;;;
;;; Maslow
;;;

(define-public maslow-service-type
  (make-rails-app-using-plek-and-signon-service-type 'maslow))

(define-public maslow-service
  (service
   maslow-service-type
   (list (shepherd-service
          (inherit default-shepherd-service)
          (provision '(maslow))
          (requirement '(publishing-api signon)))
         (service-startup-config)
         (signon-application
          (name "Maslow")
          (supported-permissions '("signin" "admin" "editor")))
         (signon-api-user
          (name "Maslow")
          (email "maslow@guix-dev.gov.uk")
          (authorisation-permissions
           (list
            (cons
             (signon-authorisation
              (application-name "Publishing API"))
             '("signin")))))
         (plek-config) (rails-app-config) maslow
         (mongodb-connection-config
          (database "maslow")))))

;;;
;;; Rummager
;;;

(define-public rummager-service
  (service rummager-service-type
           (list (service-startup-config-add-pre-startup-scripts
                  (service-startup-config)
                  `((publish-special-routes
                     . ,#~(lambda ()
                            (run-command
                             "bundle" "exec"
                             "rake" "message_queue:create_queues")))))
                 (redis-connection-config)
                 (plek-config)
                 (sidekiq-config (file "config/sidekiq.yml"))
                 (elasticsearch-connection-config)
                 (rabbitmq-connection-config (user "rummager")
                                             (password "rummager"))
                 rummager)))

;;;
;;; Info Frontend
;;;

(define-public info-frontend-service-type
  (make-rails-app-using-plek-and-signon-service-type 'info-frontend))

(define-public info-frontend-service
  (service
   info-frontend-service-type
   (list (shepherd-service
          (inherit default-shepherd-service)
          (provision '(info-frontend))
          (requirement '(content-store publishing-api static)))
         (signon-api-user
          (name "Info Frontend")
          (email "info-frontend@guix-dev.gov.uk")
          (authorisation-permissions
           (list
            (cons
             (signon-authorisation
              (application-name "Publishing API"))
             '("signin")))))
         (service-startup-config-add-pre-startup-scripts
          (service-startup-config)
          `((publish-special-routes
             . ,#~(lambda ()
                    (run-command "rake" "publishing_api:publish_special_routes")))))
         (plek-config) (rails-app-config)
         info-frontend)))

;;;
;;; Static service
;;;

(define-public static-service-type
  (make-rails-app-using-plek-service-type 'static))

(define-public static-service
  (service
   static-service-type
   (list (shepherd-service
          (inherit default-shepherd-service)
          (provision '(static))
          (requirement '(publishing-api)))
         (service-startup-config) (plek-config) (rails-app-config)
         static)))

(define-public draft-static-service-type
  (make-rails-app-using-plek-service-type 'draft-static))

(define-public draft-static-service
  (service
   draft-static-service-type
   (list (shepherd-service
          (inherit default-shepherd-service)
          (provision '(draft-static))
          (requirement '(publishing-api)))
         (service-startup-config
          (environment-variables
           '(("DRAFT_ENVIRONMENT" . "true"))))
         (plek-config) (rails-app-config) static)))

;;;
;;; Whitehall
;;;

(define-public whitehall-service-type
  (make-rails-app-using-plek-and-signon-service-type 'whitehall
                                                     #:signon-plek-name 'whitehall-admin))

(define-public whitehall-service
  (service
   whitehall-service-type
   (list (shepherd-service
          (inherit default-shepherd-service)
          (provision '(whitehall))
          (requirement '(publishing-api
                         ;; The frontend component of Whitehall uses
                         ;; the content store directly
                         content-store
                         signon
                         asset-manager
                         static
                         memcached)))
         (service-startup-config-add-pre-startup-scripts
          (service-startup-config)
          `((create-directories
             . ,(with-imported-modules '((guix build utils))
                  #~(lambda ()
                      (let ((user (getpwnam "whitehall")))
                        (for-each
                         (lambda (name)
                           (let ((mount-target
                                  (string-append "/var/apps/whitehall/" name))
                                 (mount-source
                                  (string-append "/var/lib/whitehall/" name)))
                             (mkdir-p mount-source)
                             (chown mount-source
                                    (passwd:uid user)
                                    (passwd:gid user))
                             (bind-mount mount-source mount-target)))
                         '("incoming-uploads"
                           "clean-uploads"
                           "infected-uploads"
                           "asset-manager-tmp"
                           "carrierwave-tmp"
                           "attachment-cache"
                           "bulk-upload-zip-file-tmp")))
                      #t))))
          #:run-as-root #t)
         (plek-config) (rails-app-config) whitehall
         (signon-application
          (name "Whitehall")
          (supported-permissions '("signin" "Editor" "GDS Editor" "GDS Admin"
                                   "Import CSVs" "Managing Editor"
                                   "Upload Executable File Attachments"
                                   "World Editor" "World Writer")))
         (signon-api-user
          (name "Whitehall")
          (email "whitehall@guix-dev.gov.uk")
          (authorisation-permissions
           (list
            (cons
             (signon-authorisation
              (application-name "Publishing API"))
             '("signin"))
            (cons
             (signon-authorisation
              (application-name "Asset Manager"))
             '("signin")))))
         (sidekiq-config
          (file "config/sidekiq.yml"))
         (memcached-connection-config)
         (redis-connection-config)
         (mysql-connection-config
          (user "whitehall")
          (port "-")
          (database "whitehall_production")
          (password "whitehall")))))

;;;
;;; Service Lists
;;;

(define-public publishing-application-services
  (list
   collections-publisher-service
   contacts-admin-service
   content-tagger-service
   local-links-manager-service
   manuals-publisher-service
   maslow-service
   policy-publisher-service
   publisher-service
   service-manual-publisher-service
   short-url-manager-service
   specialist-publisher-service
   travel-advice-publisher-service
   whitehall-service))

(define-public api-services
  (list
   content-store-service
   draft-content-store-service
   ;; email-alert-api-service Can't connect to Redis for some reason
   ;; email-alert-service-service Missing dependency on RabbitMQ
   imminence-service
   publishing-api-service
   rummager-service
   asset-manager-service
   router-api-service
   draft-router-api-service
   support-api-service
   hmrc-manuals-api-service
   ;; mapit-service
   ))

(define-public supporting-application-services
  (list
   ;; bouncer-service
   authenticating-proxy-service
   content-audit-tool-service
   content-performance-manager-service
   link-checker-api-service
   search-admin-service
   signon-service
   support-service
   ;; transition-service
   release-service
   router-service
   draft-router-service
   (service publishing-e2e-tests-service-type)))

(define-public frontend-services
  (list
   calculators-service
   calendars-service
   collections-service
   email-alert-frontend-service
   feedback-service
   finder-frontend-service
   frontend-service
   government-frontend-service
   info-frontend-service
   licence-finder-service
   manuals-frontend-service
   service-manual-frontend-service
   smart-answers-service
   smokey-service
   static-service))

(define-public draft-frontend-services
  (list
   draft-collections-service
   draft-email-alert-frontend-service
   draft-frontend-service
   draft-government-frontend-service
   draft-finder-frontend-service
   draft-manuals-frontend-service
   draft-service-manual-frontend-service
   draft-static-service))

(define-public govuk-services
  (append
   publishing-application-services
   api-services
   supporting-application-services
   frontend-services
   draft-frontend-services))
