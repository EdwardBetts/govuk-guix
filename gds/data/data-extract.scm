(define-module (gds data data-extract)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-19)
  #:use-module (ice-9 match)
  #:use-module (guix gexp)
  #:use-module (guix monads)
  #:use-module (guix records)
  #:use-module (guix derivations)
  #:use-module (guix store)
  #:use-module (gds utils)
  #:use-module (gds services utils databases postgresql)
  #:use-module (gds services utils databases mongodb)
  #:use-module (gds services utils databases mysql)
  #:export (<data-extract>
            data-extract
            data-extract?
            data-extract-file
            data-extract-datetime
            data-extract-database
            data-extract-services

            filter-extracts
            group-extracts
            sort-extracts
            load-extract))

(define-record-type* <data-extract>
  data-extract make-data-extract
  data-extract?
  (file       data-extract-file)
  (datetime   data-extract-datetime)
  (database   data-extract-database)
  (services   data-extract-services))

(define* (filter-extracts extracts
                          #:optional #:key
                          service-types
                          databases
                          before-date
                          after-date)
  (filter
   (lambda (extract)
     (and
      (let ((services (data-extract-services extract)))
        (if services
            (any (lambda (service-type)
                   (member service-type (data-extract-services extract)))
                 service-types)
            #t))
      (if databases
          (member (data-extract-database extract) databases)
          #t)
      (if before-date
          (time<? (date->time-utc (data-extract-datetime extract))
                   (date->time-utc before-date))
          #t)
      (if after-date
          (time>? (date->time-utc (data-extract-datetime extract))
                   (date->time-utc after-date)))))
   extracts))

(define (group-extracts field extracts)
  (fold (lambda (extract result)
          (let ((key (field extract)))
            (fold (lambda (key result)
                    (if (list? key) (error "key is a list"))
                    (alist-add key extract result))
                  result
                  (if (list? key)
                      key
                      (list key)))))
        '()
        extracts))

(define (sort-extracts extracts)
  (stable-sort extracts
               (lambda (a b)
                 (time<? (date->time-utc (data-extract-datetime a))
                         (date->time-utc (data-extract-datetime b))))))

(define (load-extract extract database-connection-config)
  (let* ((load-gexp
          (match (data-extract-database extract)
            ("postgresql"
             (postgresql-import-gexp
              (postgresql-connection-config
               (inherit database-connection-config)
               (user "postgres")
               (database "postgres"))
              (data-extract-file extract)))
            ("mongo"
             (mongodb-restore-gexp
              database-connection-config
              (data-extract-file extract)))
            ("mysql"
             (mysql-run-file-gexp
              database-connection-config
              (data-extract-file extract)))))
         (script
          (with-store store
            (run-with-store store
              (mlet* %store-monad
                  ((script (gexp->script
                            "load-extract"
                            #~(begin (exit (#$load-gexp))))))
                (mbegin %store-monad
                  (built-derivations (list script))
                  (return (derivation->output-path script))))))))
    (simple-format #t "running script ~A\n\n" script)
    (system* script)))
