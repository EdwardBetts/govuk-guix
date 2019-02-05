(define-module (gds build rails-build-system)
  #:use-module ((guix build gnu-build-system) #:prefix gnu:)
  #:use-module (guix build syscalls)
  #:use-module (guix build utils)
  #:use-module (sxml simple)
  #:use-module (ice-9 match)
  #:use-module (ice-9 ftw)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-26)
  #:export (%standard-phases
            rails-build))

;; Commentary:
;;
;; Builder-side code of the standard build procedure for applications
;; using Rails.
;;
;; Code:

(define wrap-ruby-program
  (@@ (guix build ruby-build-system) wrap-ruby-program))

(define* (replace-relative-spring-path #:key outputs
                                       #:allow-other-keys)
  (let* ((out (assoc-ref outputs "out"))
         (files
          (find-files
           (string-append out "/bin")
           (lambda (name stat)
             (or
              (access? name X_OK)
              (begin
                (simple-format
                 #t
                 "Skipping wrapping ~A as its not executable\n" name)
                #f))))))
    (substitute* files
      (("File\\.expand_path\\([\"']\\.\\./spring[\"'], __FILE__\\)")
       "File.expand_path('../.spring-real', __FILE__)")))
  #t)

(define* (wrap-with-relative-path #:key outputs
                                  #:allow-other-keys)
  (let* ((out (assoc-ref outputs "out"))
         (files
          (find-files
           (string-append out "/bin")
           (lambda (name stat)
             (or
              (access? name X_OK)
              (begin
                (simple-format
                 #t
                 "Skipping wrapping ~A as its not executable\n" name)
                #f))))))
    (substitute* files
      (((string-append out "/bin"))
       "${BASH_SOURCE%/*}")))
  #t)

(define* (create-tmp-directory #:key outputs
                              #:allow-other-keys)
  (mkdir-p (string-append
            (assoc-ref outputs "out")
            "/tmp")))

(define* (create-log-directory #:key outputs #:allow-other-keys)
  (mkdir-p (string-append
            (assoc-ref outputs "out")
            "/log")))

(define* (precompile-rails-assets
          #:key inputs precompile-rails-assets?
          #:allow-other-keys)
  (or (not precompile-rails-assets?)
      (invoke "bundle" "exec" "rake" "assets:precompile")))

(define* (install #:key inputs outputs exclude-files #:allow-other-keys)
  (let* ((out (assoc-ref outputs "out"))
         (install-file?
          (negate (lambda (f)
                    (member f
                            (append exclude-files
                                    '("." ".."))))))
         (files (scandir "." install-file?)))

    (simple-format #t "exclude-files: ~A\n" exclude-files)
    (mkdir-p out)
    (for-each (lambda (file)
                (if (directory-exists? file)
                    (copy-recursively
                     file
                     (string-append out "/" file)
                     #:log (%make-void-port "w"))
                    (copy-file file (string-append out "/" file))))
              files))
  #t)

(define* (wrap-bin-files-for-rails #:key inputs outputs #:allow-other-keys)
  (for-each
   (lambda (script)
     (wrap-program
         script
       `("PATH" ":" prefix (,(string-append
                              (assoc-ref inputs "node")
                              "/bin")))))
   (find-files
    (string-append (assoc-ref outputs "out") "/bin")
    (lambda (name stat)
      (and
       (not (string-prefix? "." (last (string-split name #\/))))
       (or
        (access? name X_OK)
        (begin
          (simple-format #t "Skipping wrapping ~A as its not executable\n" name)
          #f))))))
  #t)

(define* (patch-bin-files #:key inputs outputs #:allow-other-keys)
  (let* ((out (assoc-ref outputs "out")))
    (substitute*
        (find-files
         (string-append out "/bin")
         (lambda (name stat)
           (or
            (access? name X_OK)
            (begin
              (simple-format #t "Skipping patching ~A as its not executable\n" name)
              #f))))
      (("/usr/bin/env") (which "env"))))
  #t)

(define %standard-phases
  (modify-phases gnu:%standard-phases
    (replace 'configure (lambda args #t))
    (replace 'build (lambda args #t))
    (replace 'check (lambda args #t))
    (replace 'install install)
    (add-before 'install 'precompile-rails-assets
                precompile-rails-assets)
    (add-after 'install 'wrap-bin-files-for-rails
               wrap-bin-files-for-rails)
    (add-after 'wrap-bin-files-for-rails 'replace-relative-spring-path
               replace-relative-spring-path)
    (add-after 'install 'create-tmp-directory
               create-tmp-directory)
    (add-after 'create-tmp-directory 'create-log-directory
               create-log-directory)
    (add-after 'create-log-directory 'patch-bin-files
               patch-bin-files)
    (add-after 'patch-bin-files 'wrap-with-relative-path
               wrap-with-relative-path)))

(define* (rails-build #:key
                      inputs
                      (phases %standard-phases)
                      #:allow-other-keys
                      #:rest args)
  "Build the given Rails application, applying all of PHASES in order."
  (apply gnu:gnu-build #:inputs inputs #:phases phases args))
