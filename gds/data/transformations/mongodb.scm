(define-module (gds data transformations mongodb)
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 match)
  #:use-module (guix gexp)
  #:use-module (guix store)
  #:use-module (guix packages)
  #:use-module (guix records)
  #:use-module (guix monads)
  #:use-module (gnu packages admin)
  #:use-module (gnu packages base)
  #:use-module (gnu packages compression)
  #:use-module (gnu packages databases)
  #:use-module (gnu packages pv)
  #:use-module (gnu services)
  #:use-module (gnu services shepherd)
  #:use-module (gnu services databases)
  #:use-module (gds data data-extract)
  #:use-module (gds data transformations)
  #:use-module (gds services utils databases mongodb)
  #:export (with-mongodb

            mongodb-convert-tar-archive-to-archive-dump

            mongodb-load-extracts))

(define* (with-mongodb
          mongodb-service
          gexp-to-run
          #:key (base-directory #~(string-append
                                   (getcwd)
                                   "/mongo")))
  (let ((mongodb (mongodb-configuration-mongodb
                  (service-parameters mongodb-service))))
    (with-imported-modules '((guix build utils))
      #~(let* ((pid-file "/tmp/mongodb.pid")
               (base-directory #$base-directory))

          (define (start-mongodb)
            ((make-forkexec-constructor
              (list #$(file-append mongodb "/bin/mongod")
                    "--wiredTigerCacheSizeGB=1"
                    "--nojournal"
                    (string-append "--pidfilepath=" pid-file)
                    "--dbpath" base-directory)
              #:pid-file "/tmp/mongodb.pid")))

          (add-to-load-path #$(file-append shepherd
                                           "/share/guile/site/"
                                           (effective-version)))

          (use-modules (shepherd service)
                       (guix build utils))

          (setenv "PATH"
                  (list->search-path-as-string
                   (cons*
                    #$(file-append mongo-tools "/bin")
                    #$(file-append pv "/bin")
                    #$(file-append gzip "/bin")
                    #$(file-append xz "/bin")
                    (search-path-as-string->list (getenv "PATH")))
                   ":"))

          (simple-format #t "activating Mongodb\n")
          (force-output)
          (mkdir-p base-directory)
          (chmod base-directory #o700)

          (let ((mongodb-pid (start-mongodb))
                (result (#$gexp-to-run '())))

            (simple-format #t "Stopping MongoDB\n")
            ((make-kill-destructor) mongodb-pid)
            ;; TODO: Fix this
            (sleep 20)
            (force-output)

            result)))))

(define (mongodb-convert-tar-archive-to-archive-dump file database-name)
  (define operation
    #~(lambda _
        (let ((dump-directory "dump")
              (tmp-archive-filename "temp.mongodb.archive"))
          ;; Extract the tarball, as mongorestore needs the unpacked
          ;; form to work with
          (mkdir-p dump-directory)
          (chdir dump-directory)
          (invoke #$(file-append tar "/bin/tar")
                  "--extract"
                  "--xz"
                  "--strip-components=1"
                  "--file" #$file)
          (chdir "..")
          (display "\ndata extracted\n\n")
          (simple-format #t "checking metadata files in ~A\n"
                         dump-directory)
          (force-output)

          ;; Work around some broken collections by
          ;; deleting them, this is necessary for Travel
          ;; Advice Publisher
          (for-each (lambda (file)
                      (simple-format #t "deleting ~A\n" file)
                      (delete-file file))
                    (find-files dump-directory
                                "^\\{"))

          ;; Work around an issue with the
          ;; extracts. mongorestore seems to fail when trying
          ;; to use the options thing, so remove it.
          (for-each (lambda (file)
                      (simple-format #t "removing options from ~A\n" file)
                      (substitute* file
                                   (("\\\"options\\\" [^}]*\\},")
                                    "")))
                    (find-files dump-directory
                                ".*\\.metadata\\.json$"))

          (display "\nfinished checking metadata files\n")

          ;; Run mongorestore to populate the database
          (display "starting mongorestore\n\n")
          (force-output)

          (invoke "mongorestore" "-d" #$database-name
                  dump-directory)
          (delete-file-recursively dump-directory)

          (display "\n\nfinished running mongorestore\n")

          ;; Run mongodump to generate the archive file
          (display "starting mongodump to generate archive\n\n")
          (force-output)

          (invoke "mongodump"
                  "-d" #$database-name
                  (string-append "--archive=" tmp-archive-filename))

          (display "\n\nfinished running mongodump\n\n")

          ;; Create the xz compressed MongoDB archive file
          (display "starting xz to compress the archive\n\n")
          (force-output)

          (let ((command
                 (string-join
                  `("set -eo pipefail;"
                    "pv" "--force" ,tmp-archive-filename "|"
                    "xz" "-e" "-9" "-z" "-T0" "-c" ">"
                    ,#$output)
                  " ")))
            (or (zero? (system command))
                (error (string-append "command "
                                      (string-join command)
                                      " failed"))))

          (display "\n\nfinished generating output\n")
          (force-output)

          #t)))

  (data-transformation
   (output-name (string-append database-name ".mongo.xz"))
   (operation
    (with-imported-modules '((guix build utils))
      #~(begin
          (use-modules (guix build utils))
          #$(with-mongodb
             (service mongodb-service-type)
             operation))))))

(define (mongodb-load-extracts extracts-and-database-connection-configs)
  (define operation
    (with-imported-modules '((gds data transformations build mongodb))
      #~(lambda _
          (use-modules (gds data transformations build mongodb))
          #$@(map
              (match-lambda
                ((data-extract . database-connection-configs)
                 #~(decompress-file-and-pipe-to-mongorestore
                    #$(data-extract-file data-extract)
                    #$(mongodb-connection-config-database
                       (car database-connection-configs)))))

              extracts-and-database-connection-configs))))

  (with-imported-modules '((guix build utils))
    #~(begin
        (use-modules (guix build utils))

        #$(with-mongodb
           (service mongodb-service-type)
           operation))))
