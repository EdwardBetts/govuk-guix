(define-module (gds systems govuk publishing-e2e-tests)
  #:use-module (srfi srfi-1)
  #:use-module (gnu system)
  #:use-module (gnu services)
  #:use-module (gnu services web)
  #:use-module (gds packages govuk)
  #:use-module (gds services)
  #:use-module (gds services rails)
  #:use-module (gds services utils)
  #:use-module (gds services utils databases)
  #:use-module (gds services utils databases postgresql)
  #:use-module (gds services utils databases mysql)
  #:use-module (gds services govuk)
  #:use-module (gds services govuk signon)
  #:use-module (gds systems utils)
  #:use-module (gds systems govuk development))

(define services
  (setup-services
   (cons
    publishing-e2e-tests-service
    (operating-system-user-services development-os))))

(define-public publishing-e2e-tests-os
  (system-without-unnecessary-services
   (cons (find (lambda (s) (eq? (service-kind s)
                                publishing-e2e-tests-service-type))
               services)
         base-services)
   (operating-system
    (inherit development-os)
    (services
     (modify-services
         (map
          (lambda (s)
            (if (and
                 (list? (service-parameters s))
                 (find rails-app-config? (service-parameters s))
                 (any
                  (lambda (p)
                    (or (postgresql-connection-config? p)
                        (mysql-connection-config? p)))
                  (service-parameters s)))
                (rails-run-db:setup s)
                s))
          (use-gds-sso-strategy
           (map
            setup-blank-databases-on-service-startup
            services)
           "mock")) ;; This is not a real value that the gds-sso gem
                    ;; uses, as it just checks if the value is "real" or
                    ;; not.
       (specialist-publisher-service-type
        parameters =>
        (map
         (lambda (parameter)
           (if
            (service-startup-config?
             parameter)
            (service-startup-config-add-pre-startup-scripts
             parameter
             `((db-seed
                . ,(run-command "rake" "db:seed"))
               (publish-finders
                . ,(run-command "rake" "publishing_api:publish_finders"))))
            parameter))
         parameters))
       (nginx-service-type
        parameter =>
        (nginx-configuration
         (inherit parameter)
         (server-blocks
          (cons
           (nginx-server-configuration
            (inherit (car (nginx-configuration-server-blocks parameter)))
            (server-name '("publishing-e2e-tests.guix-dev.gov.uk"))
            (root "/var/apps/publishing-e2e-tests")
            (locations
             (list
              (nginx-location-configuration
               (uri "/")
               (body '("autoindex on;"))))))
           (nginx-configuration-server-blocks parameter))))))))))

publishing-e2e-tests-os
