(define-module (gds packages govuk)
  #:use-module (ice-9 regex)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:use-module (guix packages)
  #:use-module (guix utils)
  #:use-module (guix build-system gnu)
  #:use-module (guix build-system trivial)
  #:use-module (guix build-system ruby)
  #:use-module (guix download)
  #:use-module (guix search-paths)
  #:use-module (guix records)
  #:use-module (guix git-download)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages admin)
  #:use-module (gnu packages bash)
  #:use-module (gnu packages curl)
  #:use-module (gnu packages ruby)
  #:use-module (gnu packages certs)
  #:use-module (gnu packages commencement)
  #:use-module (gnu packages linux)
  #:use-module (gnu packages databases)
  #:use-module (gnu packages xml)
  #:use-module (gnu packages compression)
  #:use-module (gnu packages base)
  #:use-module (gnu packages tls)
  #:use-module (gnu packages node)
  #:use-module (gnu packages imagemagick)
  #:use-module (gnu packages golang)
  #:use-module (gnu packages web)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages libffi)
  #:use-module (gnu packages version-control)
  #:use-module (gnu packages rsync)
  #:use-module (gds build-system rails)
  #:use-module (gds packages utils)
  #:use-module (gds packages utils bundler)
  #:use-module (gds packages third-party phantomjs))

;; TODO: The native search paths in the ruby-2.3 package from GNU Guix
;; are wrong in the version currently in use, so fix this here.
(define ruby-2.3
  (package
    (inherit (@ (gnu packages ruby) ruby-2.3))
    (native-search-paths
     (list (search-path-specification
            (variable "GEM_PATH")
            (files (list "lib/ruby/gems/2.3.0")))))))

(define-public asset-manager
  (package-with-bundler
   (bundle-package
    (hash (base32 "0g202g0hl81yd9kgiayhscix0wsaxnmaib8l7yi730h77w4xw2zh")))
   (package
     (name "asset-manager")
     (version "release_181")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "13dacd2np9xzxn5ww63m5ldrvgqhzlldifcqzxdwcb7k6kzbl3q8")))
     (build-system rails-build-system)
     (inputs
      `(("govuk_clamscan"
         ,
         (package
           (name "fake-govuk-clamscan")
           (version "1")
           (source #f)
           (build-system trivial-build-system)
           (arguments
            `(#:modules ((guix build utils))
              #:builder (begin
                          (use-modules (guix build utils))
                          (let
                              ((bash (string-append
                                      (assoc-ref %build-inputs "bash")
                                      "/bin/bash")))
                            (mkdir-p (string-append %output "/bin"))
                            (call-with-output-file (string-append
                                                    %output
                                                    "/bin/govuk_clamscan")
                              (lambda (port)
                                (simple-format port "#!~A\nexit 0\n" bash)))
                            (chmod (string-append %output "/bin/govuk_clamscan") #o555)
                            #t))))
           (native-inputs
            `(("bash" ,bash)))
           (synopsis "")
           (description "")
           (license #f)
           (home-page #f)))))
     (arguments
      `(#:phases
        (modify-phases %standard-phases
          (add-after 'install 'create-uploads-directory
                     (lambda* (#:key outputs #:allow-other-keys)
                       (let ((out (assoc-ref outputs "out")))
                         (mkdir-p (string-append out "/uploads"))))))
        #:ruby ,ruby-2.3))
     (synopsis "Manages uploaded assets (e.g. PDFs, images, ...)")
     (description "The Asset Manager is used to manage assets for the GOV.UK Publishing Platform")
     (license license:expat)
     (home-page "https://github.com/alphagov/asset-manager"))))

(define-public authenticating-proxy
  (package-with-bundler
   (bundle-package
    (hash (base32 "1dz1wsjxzgnhccrzan2qs4zw6xzb2f1l6nc8bh5f4n2ng3vph6vp")))
   (package
     (name "authenticating-proxy")
     (version "release_41")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "0dhvipzya2gylm0lwqn9jicwf3n9z67bj0za6pi39c111h9jq8fz")))
     (build-system rails-build-system)
     (arguments
      `(#:phases
        (modify-phases %standard-phases
          (add-after 'install 'replace-mongoid.yml
            ,(replace-mongoid.yml)))
        #:ruby ,ruby-2.3))
     (synopsis "Proxy to add authentication via Signon")
     (description "The Authenticating Proxy is a Rack based proxy,
written in Ruby that performs authentication using gds-sso, and then
proxies requests to some upstream")
     (license #f)
     (home-page "https://github.com/alphagov/authenticating-proxy"))))

(define-public bouncer
  (package-with-bundler
   (bundle-package
    (hash (base32 "1zc783hlnlzh8l9798h0bmii94kwdhmf0j9n9my24rw8lz5kdia2")))
   (package
     (name "bouncer")
     (version "release_209")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "0iwp4y2dh894x4zdfwlq7w7d6j7wn3lfzm5gwwjh8rf8i624mmnp")))
     (build-system rails-build-system)
     (synopsis "Rack based redirector backed by the Transition service")
     (description "")
     (license license:expat)
     (home-page "https://github.com/alphagov/bouncer"))
   #:extra-inputs (list libffi postgresql)))

(define-public calculators
  (package-with-bundler
   (bundle-package
    (hash (base32 "16kdyd9695qv4yg7065bjccva20b3nzanbj2f6lb1k697z7v2n7s")))
   (package
     (name "calculators")
     (version "release_206")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "04pz2fh4jblxm7npv4sp4pllndq9fdh03kyqdamd6bqknz1qq9v1")))
     (build-system rails-build-system)
     (synopsis "Calculators provides the Child benefit tax calculator")
     (description "")
     (license license:expat)
     (home-page "https://github.com/alphagov/calculators"))
   #:extra-inputs (list libffi)))


(define-public calendars
  (package-with-bundler
   (bundle-package
    (hash (base32 "0v0jvqxp6qvk9s4an7dq8llayn68964xsvxrqbkdhpda70q95j8f")))
   (package
     (name "calendars")
     (version "release_431")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "1ai4c400fxk8wl7asg59b28yzdhsgwwrhplzji86cih8aynm9c3k")))
     (build-system rails-build-system)
     (synopsis "Serves calendars on GOV.UK")
     (description "")
     (license license:expat)
     (home-page "https://github.com/alphagov/calendars"))))

(define-public collections
  (package-with-bundler
   (bundle-package
    (hash (base32 "0s2pprx4bnd9advya7h2x5xx0y5lawgblc8579akxzfd1dvw928p")))
   (package
     (name "collections")
     (version "release_391")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "1rr5h347r822ijlm30s7z2858s7zi1amp15wqlwys7s4pvfpnar1")))
     (build-system rails-build-system)
     (synopsis "Collections serves the new GOV.UK navigation and other pages")
     (description "")
     (license license:expat)
     (home-page "https://github.com/alphagov/collections"))))

(define-public collections-publisher
  (package-with-bundler
   (bundle-package
    (hash (base32 "1fhbawz9jn2qhvwv2ximnplzf7dbrspk8bfk8zq4ldyzlm5dk2qr")))
   (package
     (name "collections-publisher")
     (version "release_268")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "1iff8p126jrc2qh9i490asslmmd25c9q1xmsvh205rfcjgnwrsxi")))
     (build-system rails-build-system)
     (arguments
      `(#:phases
        (modify-phases %standard-phases
          (add-after 'install 'replace-database.yml
                     ,(use-blank-database.yml)))))
     (synopsis "Used to create browse and topic pages")
     (description "")
     (license license:expat)
     (home-page "https://github.com/alphagov/collections-publisher"))
   #:extra-inputs (list mariadb)))

(define-public contacts-admin
  (package-with-bundler
   (bundle-package
    (hash (base32 "1k7c1lcyackl7kfi6wrcialdglzf69s6r4xmchi4gc4v90f0yl7x")))
   (package
     (name "contacts-admin")
     (version "release_358")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "1ryvx4gx2js1wdxkls2l2wy70fiwqv67m8sq970zg93ailxikjzd")))
     (build-system rails-build-system)
     (inputs
      `(;; hostname is needed by the redis-lock gem
        ("inetutils" ,inetutils)))
     (arguments `(#:precompile-rails-assets? #f))
     (synopsis "Used to publish organisation contact information to GOV.UK")
     (description "")
     (license license:expat)
     (home-page "https://github.com/alphagov/contacts-admin"))
   #:extra-inputs (list mariadb)))

(define-public content-performance-manager
  (package-with-bundler
   (bundle-package
    (hash (base32 "1g06pq1vmn9a0s6ydc93a39a199g51z8sjpvh8r8rh56h7abybam")))
   (package
     (name "content-performance-manager")
     (version "release_313")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "03l5dmsb9sqc69xlys7558z3m0bdwhmc32mcrpcd40wb3g7b61c5")))
     (build-system rails-build-system)
     (arguments
      `(#:phases
        (modify-phases %standard-phases
          (add-after 'install 'replace-database.yml
                     ,(use-blank-database.yml)))))
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/content-performance-manager"))
   #:extra-inputs (list postgresql libffi)))

(define-public content-store
  (package-with-bundler
   (bundle-package
    (hash (base32 "18bfmqrx4b5lv68ql8bxi8z735mffqsqz9lahwh3lk8jdgraxmj1")))
   (package
     (name "content-store")
     (version "release_668")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "0z6qxlrg0pxrbvvlv34bwqj48563iq0409xcsnv9q0aiwlvjhn5l")))
     (build-system rails-build-system)
     (arguments `(#:precompile-rails-assets? #f))
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/content-store"))))

(define-public content-tagger
  (package-with-bundler
   (bundle-package
    (hash (base32 "1gi159rdjm7cjh41bl7swjcywkkm17yz12r738m3jyx51qvn30ls")))
   (package
     (name "content-tagger")
     (version "release_579")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "0b7jqzyiz0s34g97g4crv9wg0pjjidpnhyi5w713i4nm4qqvsf16")))
     (build-system rails-build-system)
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/content-tagger"))
   #:extra-inputs (list postgresql)))

(define-public design-principles
  (package-with-bundler
   (bundle-package
    (hash (base32 "07vbzwzxmvj3c4rwx7w6d3py3r16f5ljx1yjxpjm8qm2hi6flrsg")))
   (package
     (name "design-principles")
     (version "release_876")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "1brak8fq2406i666iqq1drm1lamcvfdjrw8lh25gp6y60d96nnif")))
     (build-system rails-build-system)
     (arguments `(;; Asset precompilation fails
                  #:precompile-rails-assets? #f
                  #:ruby ,ruby-2.3))
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/design-principles"))))

(define-public email-alert-api
  (package-with-bundler
   (bundle-package
    (hash (base32 "03r4fp7i03qhpcxi6b9qw34gp8dyavnpfr52fqnsm4hbhblqi17m")))
   (package
     (name "email-alert-api")
     (version "release_258")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "136n8h9sdw1y9qz6rqv562xym4pbsc7li4rdgv5iqa0bdrwsm5hg")))
     (build-system rails-build-system)
     (arguments
      `(#:precompile-rails-assets? #f
        #:phases
        (modify-phases %standard-phases
          (add-after 'install 'replace-redis.yml
                     ,(replace-redis.yml))
          (add-after 'install 'replace-database.yml
                     ,(use-blank-database.yml)))))
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/email-alert-api"))
   #:extra-inputs (list libffi postgresql)))

(define-public email-alert-frontend
  (package-with-bundler
   (bundle-package
    (hash (base32 "18naj3b73k4sgzfc24bkgj5jwhcmq3578j1vw56l4j1wsck07044")))
   (package
     (name "email-alert-frontend")
     (version "release_52")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "0sdxrc8n0rbq6asiwamvh67wfqd4wspz9bdl7cq7kxsp4dca4dnn")))
     (build-system rails-build-system)
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/email-alert-frontend"))
   #:extra-inputs (list libffi)))

(define-public email-alert-service
  (package-with-bundler
   (bundle-package
    (hash (base32 "0j3m7vxaasc93cp84wiw7zkn3m8ryag740g7j26ykpxkr8ks0m2i")))
   (package
     (name "email-alert-service")
     (version "release_91")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "0d52gk5mnyb0bxbnf78skis7jgi9l5r2cnda4yam01q2i89xmxjj")))
     (build-system gnu-build-system)
     (inputs
      `(("ruby" ,ruby)))
     (arguments
      `(#:phases
        (modify-phases %standard-phases
          (replace 'configure (lambda args #t))
          (replace 'build (lambda args #t))
          (replace 'check (lambda args #t))
          (replace 'install
                   (lambda* (#:key inputs outputs #:allow-other-keys)
                     (let* ((out (assoc-ref outputs "out")))
                       (copy-recursively
                        "."
                        out
                        #:log (%make-void-port "w")))))
          (add-after 'patch-bin-files 'wrap-with-relative-path
                     (lambda* (#:key outputs #:allow-other-keys)
                       (let* ((out (assoc-ref outputs "out")))
                         (substitute* (find-files
                                       (string-append out "/bin"))
                           (((string-append out "/bin"))
                            "${BASH_SOURCE%/*}"))))))))
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/email-alert-service/"))))

(define-public feedback
  (package-with-bundler
   (bundle-package
    (hash (base32 "1j7j23dp7yh811nw858l41pcyip07dk5fxd7wsjjqjyrlsg6b1wa")))
   (package
     (name "feedback")
     (version "release_334")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "1ysplj9rca9d18g2wkjjahy3hjy534c8yxqj414wz3p221jg5xh8")))
     (build-system rails-build-system)
     (arguments `(#:ruby ,ruby-2.3))
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/feedback"))))

(define-public finder-frontend
  (package-with-bundler
   (bundle-package
    (hash (base32 "0j1xyk3v96x9kk7aq5kf8pn2xyv572zf9bp9vdjqx8k61i1mvc07")))
   (package
     (name "finder-frontend")
     (version "release_330")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "0ssgl1vyc6l9v0w3c2fjcp6drq3mrjrn4g1gmw6g5njpcxhzf1vi")))
     (build-system rails-build-system)
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/finder-frontend"))))

(define-public frontend
  (package-with-bundler
   (bundle-package
    (hash (base32 "1vphaid1r3imhcss6ydwm5cfjyhdj0yv66nwa0arwnx6i7214s6z")))
   (package
     (name "frontend")
     (version "release_2767")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "0kbiay9bm4f5sjy1ijs0g8vwi6468g3l02xxwfpc34wqakklph2v")))
     (build-system rails-build-system)
     (arguments `(#:ruby ,ruby-2.3))
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/frontend"))))

(define-public government-frontend
  (package-with-bundler
   (bundle-package
    (hash (base32 "0843y3kpzd1jhyyixds7030k4ns8rkpv580gzvh85cgv3ld5y7jv")))
   (package
     (name "government-frontend")
     (version "release_500")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "0gs2z3ylg63j86ir7vp738qxw5l7f3w6ilihw9xw8inrd858fkp9")))
     (build-system rails-build-system)
     (arguments
      `(#:phases
        (modify-phases %standard-phases
          (add-before 'bundle-install 'replace-ruby-version
                      ,(replace-ruby-version (package-version ruby))))))
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/government-frontend"))))

(define-public govuk-content-schemas
  (package
    (name "govuk-content-schemas")
    (version "release_642")
    (source
     (github-archive
      #:repository name
      #:commit-ish version
      #:hash (base32 "015p57mwj33mdh62irx2jb67srapcc6qdyhjm33d6a5x8hyhzpsp")))
    (build-system gnu-build-system)
    (arguments
     `(#:phases
       (modify-phases %standard-phases
         (delete 'configure)
         (delete 'build)
         (delete 'check)
         (replace 'install
           (lambda* (#:key outputs #:allow-other-keys)
             (let* ((out (assoc-ref outputs "out")))
               (copy-recursively "." out)
               #t))))))
    (synopsis "govuk-content-schemas")
    (description "govuk-content-schemas")
    (license #f)
    (home-page #f)))

(define-public govuk-setenv
  (package
   (name "govuk-setenv")
   (version "1")
   (source #f)
   (build-system trivial-build-system)
   (arguments
    `(#:modules ((guix build utils))
      #:builder (begin
                  (use-modules (guix build utils))
                  (let
                      ((bash (string-append
                              (assoc-ref %build-inputs "bash")
                              "/bin/bash"))
                       (sudo (string-append
                              (assoc-ref %build-inputs "sudo")
                              "/bin/sudo")))
                    (mkdir-p (string-append %output "/bin"))
                    (call-with-output-file (string-append
                                            %output
                                            "/bin/govuk-setenv")
                      (lambda (port)
                        (simple-format port "#!~A
set -exu
APP=\"$1\"
shift
source \"/tmp/env.d/$APP\"
cd \"/var/apps/$APP\"
~A --preserve-env -u \"$APP\" \"$@\"
" bash sudo)))
                    (chmod (string-append %output "/bin/govuk-setenv") #o555)
                    #t))))
   (native-inputs
    `(("bash" ,bash)
      ("sudo" ,sudo)))
   (synopsis "govuk-setenv script for running commands in the service environment")
   (description "This script runs the specified command in an
environment similar to that which the service is running. For example,
running govuk-setenv @code{publishing-api rails console} runs the
@code{rails console} command as the user associated with the
Publishing API service, and with the environment variables for this
service setup.")
   (license #f)
   (home-page #f)))

(define-public hmrc-manuals-api
  (package-with-bundler
   (bundle-package
    (hash (base32 "0clc4hys4dnsk17d3762g418ryiyzn7ym42vcm7cq2dcz7g53q2k")))
   (package
     (name "hmrc-manuals-api")
     (version "release_193")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "0afkr2y3wac0psqngq01rs6qvwgcz05klvqm2dyl8vp60wmkzdb0")))
     (build-system rails-build-system)
     (arguments `(#:precompile-rails-assets? #f))
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/hmrc-manuals-api"))
   #:extra-inputs (list libffi)))


(define-public imminence
  (package-with-bundler
   (bundle-package
    (hash (base32 "1785gi8pxjb5rwrqi7vlwcijb40h6ga383aqg42lry0b4j0s4jx9")))
   (package
     (name "imminence")
     (version "release_321")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "1rpajn4s7lhvxa483c3widn0gfbddsif53cscg3kq7ygsqzdg7gd")))
     (build-system rails-build-system)
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/imminence"))))

(define-public info-frontend
  (package-with-bundler
   (bundle-package
    (hash (base32 "1f406vh24gnzc0qxwqgnl5jn0zy9qdf9s03q2sms0gsl5rm6gcaa")))
   (package
     (name "info-frontend")
     (version "release_84")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "0g4dxjps1fa74jjn5psv5bal5jy537hvfpc0nj16kpywjg76dklz")))
     (build-system rails-build-system)
     (arguments `(#:precompile-rails-assets? #f))
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/info-frontend"))))

(define-public licence-finder
  (package-with-bundler
   (bundle-package
    (hash (base32 "16h24nc58h7h84hsbn9d1sgzz9g4fnj19dh4b4bmf1hyqck2jnpm")))
   (package
     (name "licence-finder")
     (version "release_297")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "0p7h5hp4kzbw38acl2021qhgyrir288xky6c21pfxv7vcjjcr64d")))
     (build-system rails-build-system)
     (arguments `(#:ruby ,ruby-2.3))
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/licence-finder"))))

(define-public local-links-manager
  (package-with-bundler
   (bundle-package
    (hash (base32 "15z1jxwfhdqxb2rq3yb6gd49q5r3j7mblkb3vxf4lxbmjvd4hhrp")))
   (package
     (name "local-links-manager")
     (version "release_134")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "1i6d331d41qk9mp3i6k9pryifss1l4smgrlfinhxw3gxsl71z39q")))
     (build-system rails-build-system)
     (inputs
      `(;; hostname is needed by the redis-lock gem
        ("inetutils" ,inetutils)))
     (arguments
      `(#:precompile-rails-assets? #f ;; Asset precompilation fails
        #:phases
        (modify-phases %standard-phases
          (add-after 'install 'replace-database.yml
            ,(use-blank-database.yml)))
        #:ruby ,ruby-2.3))
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/local-links-manager"))
   #:extra-inputs (list postgresql)))

(define-public manuals-frontend
  (package-with-bundler
   (bundle-package
    (hash (base32 "11gkyfvm7nbj6wb0wryk4rj3qpmpkfa55v2d680kbhmiww9hpicx")))
   (package
     (name "manuals-frontend")
     (version "release_216")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "0yz9lnp9p8d65nxgrik02b7nl0l6k630lf9sym2iq2bxg84sfnf0")))
     (build-system rails-build-system)
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/manuals-frontend"))))

(define-public manuals-publisher
  (package-with-bundler
   (bundle-package
    (hash (base32 "0aj4cp5zbhjb9x3x6c8gcpccyhxbffmkdw7rjmsdrj8a4v4xnc27")))
   (package
     (name "manuals-publisher")
     (version "release_980")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "0xlzjn82jwasgs0s2ifby1w89pyryk96y7d4k6xvra5zkmmjn7cq")))
     (build-system rails-build-system)
     (arguments
      `(#:precompile-rails-assets? #f ;; Asset precompilation fails
        #:phases
        (modify-phases %standard-phases
          (add-after 'install 'replace-mongoid.yml
                     ,(replace-mongoid.yml #:mongoid-version "3")))))
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/manuals-publisher"))))

(define-public maslow
  (package-with-bundler
   (bundle-package
    (hash (base32 "0sgwm594fd6k0l0cvmr417fwn3mjd78b1c7iil13iyfy0f1vz1ix")))
   (package
     (name "maslow")
     (version "release_202")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "0zv8n3p8f4jh7mmlsai0lmgvq01ykp8miji1ng2a7s498736cbdb")))
     (build-system rails-build-system)
     (arguments
      `(#:phases
        (modify-phases %standard-phases
          (add-after 'install 'replace-mongoid.yml
                     ,(replace-mongoid.yml))
          (add-after 'replace-mongoid.yml 'replace-gds-sso-initializer
                     ,(replace-gds-sso-initializer)))))
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/maslow"))
   #:extra-inputs (list libffi)))

(define-public policy-publisher
  (package-with-bundler
   (bundle-package
    (hash (base32 "0yg4ffs433hrw7csa51m93hi04fc2gjrl1xkj2bzhhgrc5lvsv5q")))
   (package
     (name "policy-publisher")
     (version "release_179")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "1mxwc8s412cwmd6dcvb7xhkk27kwbdgvjq3bg1x7z19rn94al5jp")))
     (build-system rails-build-system)
     (arguments
      `(#:phases
        (modify-phases %standard-phases
          (add-after 'install 'replace-database.yml
                     ,(use-blank-database.yml)))))
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/policy-publisher"))
   #:extra-inputs (list postgresql)))

(define-public publisher
  (package-with-bundler
   (bundle-package
    (hash (base32 "1dhqm67a4y4i55wkdixabgcwbngivqk1hhpg4mgainwwpjrw2ki7")))
   (package
     (name "publisher")
     (version "release_1820")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "19i2vj0x35jgi8q2fbn8z3v7x1gpca61cr4927rwv26qvf7p2bjf")))
     (build-system rails-build-system)
     (arguments
      `(#:phases
        (modify-phases %standard-phases
          (add-after 'install 'replace-mongoid.yml
                     ,(replace-mongoid.yml))
          (add-after 'replace-mongoid.yml 'replace-gds-sso-initializer
                     ,(replace-gds-sso-initializer)))))
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/publisher"))))

(define-public publishing-api
  (package-with-bundler
   (bundle-package
    (hash (base32 "1i1nyrrp6jym3yj32zgsfal91kg6v6p6jqzs6syngpyf9yrlvfrm")))
   (package
     (name "publishing-api")
     (version "release_1028")
     (source
      (github-archive
       #:repository "publishing-api"
       #:commit-ish version
       #:hash (base32 "1yala4a9rxiy171f6s93d47a08zjpi9dmknqknl6njbwcw3591mg")))
     (build-system rails-build-system)
     (arguments `(#:precompile-rails-assets? #f
                  #:ruby ,ruby-2.3))
     (synopsis "Service for storing and providing workflow for GOV.UK content")
     (description
      "The Publishing API is a service that provides a HTTP API for
managing content for GOV.UK.  Publishing applications can use the
Publishing API to manage their content, and the Publishing API will
populate the appropriate Content Stores (live or draft) with that
content, as well as broadcasting changes to a message queue.")
     (license license:expat)
     (home-page "https://github.com/alphagov/publishing-api"))
   #:extra-inputs (list
                   ;; Required by the pg gem
                   postgresql)))

(define-public publishing-e2e-tests
  (package-with-bundler
   (bundle-package
    (hash
     (base32 "16bgmq7pkgmgliv8c1nijiv6wcv9vj40k7g5rravhsi6d42ifw8r")))
   (package
     (name "publishing-e2e-tests")
     (version "0")
     (source
      (github-archive
       #:repository "publishing-e2e-tests"
       #:commit-ish "5451c1f1b7baa0ac4849deed278c98739cdf0f01"
       #:hash (base32 "116l3fhmr4jqpyf95gzpwmbqxcrhdj63f7npd1n8vfv521smig7r")))
     (build-system gnu-build-system)
     (inputs
      `(("ruby" ,ruby)
        ("phantomjs" ,phantomjs)))
     (arguments
      `(#:phases
        (modify-phases %standard-phases
          (replace 'configure (lambda args #t))
          (replace 'build (lambda args #t))
          (replace 'check (lambda args #t))
          (replace 'install
                   (lambda* (#:key inputs outputs #:allow-other-keys)
                     (let* ((out (assoc-ref outputs "out")))
                       (copy-recursively
                        "."
                        out
                        #:log (%make-void-port "w"))))))))
     (synopsis "Suite of end-to-end tests for GOV.UK")
     (description "")
     (license license:expat)
     (home-page "https://github.com/alphagov/publishing-e2e-tests"))
   #:extra-inputs (list
                   ;; For nokogiri
                   pkg-config
                   libxml2
                   libxslt)))

(define-public release
  (package-with-bundler
   (bundle-package
    (hash (base32 "1pwzrqarlrd32zsmbkmjvyg9j96i28qiskjh30bf3d8jsc9bp0cd")))
   (package
     (name "release")
     (version "release_261")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "0p5skmgd5lgffgqgkfz5liqc6cfkw9hnf7fpd5a38sxzvj7fpq3r")))
     (build-system rails-build-system)
     (arguments
      `(#:phases
        (modify-phases %standard-phases
          (add-after 'install 'replace-database.yml
                     ,(use-blank-database.yml)))))
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/release"))
   #:extra-inputs (list mariadb)))

(define-public router
  (package
    (name "router")
    (version "release_177")
    (source
     (github-archive
      #:repository name
      #:commit-ish version
      #:hash (base32 "18mk23hd6hr4h8fvijwygj6hyf9pa1krdq1k2six8gv9j48sckpm")))
    (build-system gnu-build-system)
    (native-inputs
     `(("go" ,go)))
    (arguments
     `(#:phases
       (modify-phases %standard-phases
         (delete 'configure)
         (delete 'install)
         (delete 'check)
         (replace 'build
                  (lambda* (#:key inputs outputs #:allow-other-keys)
                    (let* ((out (assoc-ref outputs "out"))
                           (cwd (getcwd)))
                      (copy-recursively cwd "../router-copy")
                      (mkdir-p "__build/src/github.com/alphagov")
                      (mkdir-p "__build/bin")
                      (setenv "GOPATH" (string-append cwd "/__build"))
                      (setenv "BINARY" (string-append cwd "/router"))
                      (rename-file "../router-copy"
                                   "__build/src/github.com/alphagov/router")
                      (and
                       (with-directory-excursion
                           "__build/src/github.com/alphagov/router"
                         (and
                          (zero? (system*
                                  "make" "build"
                                          (string-append "RELEASE_VERSION="
                                                         ,version)))
                          (mkdir-p (string-append out "/bin"))))
                       (begin
                         (copy-file "router"
                                    (string-append out "/bin/router"))
                         #t))))))))
    (synopsis "")
    (description "")
    (license "")
    (home-page "https://github.com/alphagov/router")))

(define-public router-api
  (package-with-bundler
   (bundle-package
    (hash (base32 "08ix77pc459l08gw956dwc4n6fmxq1n5nz2g631jv7r8kx5v8fpl")))
   (package
     (name "router-api")
     (version "release_126")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "1zg6b6xf5rxj1z7n9az0hm8698kcv7kgpdy5gpnllpxbr25f5x0j")))
     (build-system rails-build-system)
     (arguments `(#:precompile-rails-assets? #f
                  #:ruby ,ruby-2.3))
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/router-api"))))

(define-public rummager
  (package-with-bundler
   (bundle-package
    (hash (base32 "1hm9cpz9x9g777bb7hn5jwy8y2can6aqk033r2yhlj2hv4aglwxf")))
   (package
     (name "rummager")
     (version "release_1554")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "1647cvp3v2qmjxjrf63hh1nf5wnls0hbnsw4qmgh8c8v3rbfpirl")))
     (build-system rails-build-system)
     (arguments
      `(#:precompile-rails-assets? #f
        #:phases
        (modify-phases %standard-phases
          (add-after
           'install 'replace-redis.yml
           ,(replace-redis.yml)))
        #:ruby ,ruby-2.3))
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/rummager"))
   #:extra-inputs (list libffi)))

(define-public search-admin
  (package-with-bundler
   (bundle-package
    (hash (base32 "0cry008fkk8m6v0qw2lgvd9xlhl52n91nm97p0n7vmfav9qcvrgm")))
   (package
     (name "search-admin")
     (version "release_99")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "1vrv8zk25v6rp595havjglylqjkppqmg9pp05pw386cxm1nnrwcj")))
     (build-system rails-build-system)
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/search-admin"))
   #:extra-inputs (list mariadb)))

(define-public service-manual-frontend
  (package-with-bundler
   (bundle-package
    (hash (base32 "1ndlp4zy7jq9jvxl742apkz5bv5la88m0byxpk5cns0lhvsccbxi")))
   (package
     (name "service-manual-frontend")
     (version "release_105")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "0lzrn82k99vmbjvavsb0in1jy7lpna1jrb38sf7lqnw0wjlhb5l1")))
     (build-system rails-build-system)
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/service-manual-frontend"))))

(define-public service-manual-publisher
  (package-with-bundler
   (bundle-package
    (hash (base32 "1jw8f05z8v2v0h1gxrkarw8v2hs57bsb66x5pxd31603l493fjci")))
   (package
     (name "service-manual-publisher")
     (version "release_306")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "0r4q4779mlbhx12k599jxg0cjib5n3hkpm13kkbm9a3s91q7sfwx")))
     (build-system rails-build-system)
     (inputs
      `(;; Loading the database structure uses psql
        ("postgresql" ,postgresql)))
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/service-manual-publisher"))
   #:extra-inputs (list postgresql)))

(define-public short-url-manager
  (package-with-bundler
   (bundle-package
    (hash (base32 "10sm23564j504lkbr78s8b8jp6257jlmgkdkphq7wzng45diydss")))
   (package
     (name "short-url-manager")
     (version "release_130")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "1gmi5r557wrb2k9d4xaysbb5ia06dgnfl1fpk29ajanz92hr65h1")))
     (build-system rails-build-system)
     (arguments `(#:precompile-rails-assets? #f ;; Asset precompilation fails
                  #:ruby ,ruby-2.3))
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/short-url-manager"))))

(define-public signon
  (package-with-bundler
   (bundle-package
    (hash (base32 "014frgl8yz3mpnacdgqqk9fb47xpnnc54klikssd8g7s3z5j182r"))
    (without '("development" "test")))
   (package
     (name "signon")
     (version "release_944")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "12ibqa9q8l196nbhf7wmdhbhb18nr7yp5pnic4bhl1gd7c27av6g")))
     (build-system rails-build-system)
     (arguments
      `(#:phases
        (modify-phases %standard-phases
          (add-after 'install 'replace-database.yml
                     ,(use-blank-database.yml)))
        #:ruby ,ruby-2.3))
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/signon"))
   #:extra-inputs (list mariadb
                        postgresql
                        openssl)))

(define-public smart-answers
  (package-with-bundler
   (bundle-package
    (hash (base32 "1caz14dmv6qp10gzr68fw03y3f7gh2dc7vjdx2fz75wv0pgfy3x8")))
   (package
     (name "smart-answers")
     (version "release_3790")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "05mjkq27h5r9arm1fgwqslamx79iwkfdz94qgcy7p2rkhq8dldkl")))
     (build-system rails-build-system)
     (arguments `(#:precompile-rails-assets? #f)) ;; Asset precompilation fails
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/smart-answers"))))

(define-public specialist-publisher
  (package-with-bundler
   (bundle-package
    (hash (base32 "1xa7v9zh5d6v0f3km0i1vqzgl4qpmy7wa03adp16xry5ggcdmsfi"))
    (without '("development" "test")))
   (package
     (name "specialist-publisher")
     (version "release_840")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "0lmjav7jiyilsfhkqsqsxf1c6k6kkyrfllfzp5xfkvmp3575njgc")))
     (build-system rails-build-system)
     (arguments
      `(#:phases
        (modify-phases %standard-phases
          (add-after
           'install 'alter-secrets.yml
           (lambda* (#:key outputs #:allow-other-keys)
             (substitute* (string-append
                           (assoc-ref outputs "out")
                           "/config/secrets.yml")
               (("SECRET_TOKEN")
                "SECRET_KEY_BASE")))))))
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/specialist-publisher"))))

(define-public smokey
  (package-with-bundler
   (bundle-package
    (hash (base32 "1yv32mx794cygskvb5qg9d3xg7zr4lmmirhal0nwmpg4c5qnxyqh")))
   (package
     (name "smokey")
     (version "0")
     (source
      (github-archive
       #:repository name
       #:commit-ish "61cd5a70ca48eb9a6e5ca2522d608db75dbb6582"
       #:hash (base32 "1n1ah83nps1bkqgpq8rd1v6c988w9mvkacrphwg7zz1d6k8fqska")))
     (build-system gnu-build-system)
     (inputs
      `(("ruby" ,ruby)
        ("phantomjs" ,phantomjs)))
     (arguments
      `(#:phases
        (modify-phases %standard-phases
          (replace 'configure (lambda args #t))
          (replace 'build (lambda args #t))
          (replace 'check (lambda args #t))
          (replace 'install
                   (lambda* (#:key inputs outputs #:allow-other-keys)
                     (let* ((out (assoc-ref outputs "out")))
                       (copy-recursively
                        "."
                        out
                        #:log (%make-void-port "w")))))
          (add-after 'patch-bin-files 'wrap-with-relative-path
                     (lambda* (#:key outputs #:allow-other-keys)
                       (let* ((out (assoc-ref outputs "out")))
                         (substitute* (find-files
                                       (string-append out "/bin"))
                           (((string-append out "/bin"))
                            "${BASH_SOURCE%/*}"))))))))
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/smokey/"))
   #:extra-inputs (list
                   ;; For nokogiri
                   pkg-config
                   libxml2
                   libxslt)))

(define-public static
  (package-with-bundler
   (bundle-package
    (hash (base32 "1l2gnh3yw4w0d887hyf99q4w3w02wbmhbv96mjjjal20ncc470c9")))
   (package
     (name "static")
     (version "release_2722")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "1001cd91waxcf71gp3kbc306jz99fh5j0hfis2kgkd8ibckwavg3")))
     (build-system rails-build-system)
     (arguments `(#:precompile-rails-assets? #f
                  #:ruby ,ruby-2.3))
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/static"))))

(define-public support
  (package-with-bundler
   (bundle-package
    (hash (base32 "0b9nzzzzwyanklj5v3g9idsriihzvnq6yz9ym9py63kib02df3c1")))
   (package
     (name "support")
     (version "release_601")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "0nlq3pmmq00qmaw9k1xv2vqs5k4p346bjiyhgyw50vyc7maqjqxs")))
     (build-system rails-build-system)
     (arguments
      `(#:precompile-rails-assets? #f ;; Asset precompilation fails
        #:phases
        (modify-phases %standard-phases
          (add-after
           'install 'replace-redis.yml
           ,(replace-redis.yml)))))
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/support"))
   #:extra-inputs (list libffi)))

(define-public support-api
  (package-with-bundler
   (bundle-package
    (hash (base32 "1jbwxnvqzc205gc3yd25sgw2xk8bifb7cvqyhfl4xxb9g2qa6a66")))
   (package
     (name "support-api")
     (version "release_134")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "0q23c6wkjf6nlif3lrnrs3n5qfc9pchd6cbp7xm2pm7apgawskaw")))
     (build-system rails-build-system)
     (arguments `(#:ruby ,ruby-2.3))
     (inputs
      `(;; hostname is needed by the redis-lock gem
        ("inetutils" ,inetutils)
        ;; Loading the database structure uses psql
        ("postgresql" ,postgresql)))
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/support-api"))
   #:extra-inputs (list postgresql libffi)))

(define-public transition
  (package-with-bundler
   (bundle-package
    (hash (base32 "0bfx5kyjykzr6yh90ansm0k7i97g0whng2dlfq1rqhpy4c9m0qhz")))
   (package
     (name "transition")
     (version "release_796")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "0rh78566rbf05c6gxbqfsgjg6x661xb4yniq9hd0kvnfzyf2jg3i")))
     (build-system rails-build-system)
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/transition"))
   #:extra-inputs (list postgresql)))

(define-public travel-advice-publisher
  (package-with-bundler
   (bundle-package
    (hash (base32 "138dhgf4iph9xyv50398rq6gy8s2shpkz1s5b1fp6kxibnryx4vr")))
   (package
     (name "travel-advice-publisher")
     (version "release_277")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "06gcxay977jd7jkc7srwyzidwbzm1zc5an823jqac9hsv45fjysg")))
     (build-system rails-build-system)
     (arguments
      `(#:phases
        (modify-phases %standard-phases
          (add-after 'install 'replace-mongoid.yml
            ,(replace-mongoid.yml)))
        #:ruby ,ruby-2.3)) ;; There might be issues with Mongoid 2 and ruby 2.4
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/travel-advice-publisher"))
   #:extra-inputs (list libffi)))

(define-public whitehall
  (package-with-bundler
   (bundle-package
    (hash (base32 "0vcpffndgikciyyypz6krisfwydxag2q8vxnxb5awvqmdhqhcb1w")))
   (package
     (name "whitehall")
     (version "release_13096")
     (source
      (github-archive
       #:repository name
       #:commit-ish version
       #:hash (base32 "1m65bbx5jk9spvjrakn6wdgdkzcp2qmf4zypknm1jah4z3blzafz")))
     (build-system rails-build-system)
     (inputs
      `(("node" ,node)
        ;; TODO Adding curl here is unusual as ideally the gem
        ;; requiring it would link against the exact location of the
        ;; library at compile time.
        ("curl" ,curl)
        ;; hostname is needed by the redis-lock gem
        ("inetutils" ,inetutils)))
     (arguments
      `(#:phases
        (modify-phases %standard-phases
          (add-after 'install 'replace-database.yml
                     ,(use-blank-database.yml))
          (add-after 'install 'set-bulk-upload-zip-file-tmp
                     (lambda* (#:key outputs #:allow-other-keys)
                       (substitute* (string-append
                                     (assoc-ref outputs "out")
                                     "/config/initializers/bulk_upload_zip_file.rb")
                         (("Rails\\.root\\.join\\('bulk-upload-zip-file-tmp'\\)")
                          "\"/tmp/whitehall/bulk-upload-zip-file\"")))))))
     (synopsis "")
     (description "")
     (license #f)
     (home-page "https://github.com/alphagov/whitehall"))
   #:extra-inputs (list mariadb
                        libffi
                        curl
                        imagemagick)))
