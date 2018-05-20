(define-module (gds services utils databases)
  #:use-module (srfi srfi-1)
  #:use-module (gnu services)
  #:use-module (gnu services shepherd)
  #:use-module (gnu system shadow)
  #:use-module ((gnu packages admin)
                #:select (shadow sudo))
  #:use-module (guix records)
  #:use-module (guix gexp)
  #:use-module (guix utils)
  #:use-module (ice-9 match)
  #:use-module (guix packages)
  #:use-module (guix gexp)
  #:use-module (system foreign)
  #:use-module (rnrs bytevectors)
  #:use-module (guix gcrypt)
  #:use-module (gnu packages base)
  #:use-module (gnu packages databases)
  #:use-module (gds packages govuk)
  #:use-module (gds services)
  #:use-module (gds services utils databases postgresql)
  #:use-module (gds services utils databases mysql)
  #:use-module (gds services utils databases mongodb)
  #:use-module (gds services utils databases elasticsearch)
  #:use-module (gds services utils databases rabbitmq)
  #:export (<redis-connection-config>
            redis-connection-config
            redis-connection-config?
            redis-connection-config-port
            redis-connection-config-namespace

            <memcached-connection-config>
            memcached-connection-config
            memcached-connection-config?
            memcached-connection-config-servers
            memcached-connection-config-port

            database-connection-config?
            database-connection-config->environment-variables
            update-database-connection-config-port
            ensure-database-user-exists-on-service-startup
            database-connection-config->database-name))

(define-record-type* <redis-connection-config>
  redis-connection-config make-redis-connection-config
  redis-connection-config?
  (host redis-connection-config-host
        (default "localhost"))
  (port redis-connection-config-port
        (default 6379))
  (db-number redis-connection-config-db-number
             (default 0))
  (namespace redis-connection-config-namespace
             (default #f)))

(define-record-type* <memcached-connection-config>
  memcached-connection-config make-memcached-connection-config
  memcached-connection-config?
  (servers       memcached-connection-config-servers
                 (default '(("localhost" "11211")))))

(define (memcached-connection-config-port config)
  (second (first (memcached-connection-config-servers config))))

(define (database-connection-config? config)
  (or (postgresql-connection-config? config)
      (mysql-connection-config? config)
      (mongodb-connection-config? config)
      (redis-connection-config? config)
      (elasticsearch-connection-config? config)
      (memcached-connection-config? config)
      (rabbitmq-connection-config? config)))

(define database-connection-config->environment-variables
  (match-lambda
    (($ <postgresql-connection-config> host user port database)
     `(("DATABASE_URL" .
        ,(simple-format
          #f
          "postgres://~A@~A:~A/~A"
          user
          host
          port
          database))))
    (($ <mysql-connection-config> host user port database password)
     `(("DATABASE_URL" .
        ,(simple-format
          #f
          "mysql2://~A~A@~A:~A/~A"
          user
          (or (and=> password
                     (lambda (password)
                       (string-append ":" password)))
              "")
          host
          port
          database))))
    (($ <mongodb-connection-config> user password host port database)
     `(("MONGO_URL" . ,host)
       ("MONGO_DB" . ,database)
       ("MONGODB_URI" .
        ,(simple-format
          #f
          "mongodb://~A:~A/~A"
          host
          port
          database))))
    (($ <redis-connection-config> host port db-number namespace)
     `(("REDIS_URL" .
        ,(simple-format
          #f
          "redis://~A:~A/~A"
          host
          port
          db-number))
       ("REDIS_HOST" . ,host)
       ("REDIS_PORT" . ,(number->string port))
       ,@(if namespace
             `("REDIS_NAMESPACE" . ,namespace)
             '())))
    (($ <elasticsearch-connection-config> host port)
     `(("ELASTICSEARCH_URI" . ,(simple-format #f "http://~A:~A" host port))))
    (($ <memcached-connection-config> servers)
     `(("MEMCACHE_SERVERS" . ,(string-join
                               (map
                                (match-lambda
                                  ((host) host)
                                  ((host port) (simple-format #f "~A:~A" host port))
                                  ((host port weight) (simple-format #f "~A:~A:~A" host port weight)))
                                servers)))))
    (($ <rabbitmq-connection-config> hosts vhost user password)
     `(("RABBITMQ_HOSTS" . ,(string-join hosts))
       ("RABBITMQ_VHOST" . ,vhost)
       ("RABBITMQ_USER" . ,user)
       ("RABBITMQ_PASSWORD" . ,password)))
    (unmatched
     (error "get-database-environment-variables no match for ~A"
            unmatched))))

(define database-connection-config->database-name
  (match-lambda
    (($ <postgresql-connection-config> host user port database) database)
    (($ <mysql-connection-config> host user port database) database)
    (($ <mongodb-connection-config> user password host port database) database)
    (($ <redis-connection-config> host port db-number namespace) namespace)
    (unmatched
     (error "database-connection-config->database-name no match for ~A"
            unmatched))))

(define (update-database-connection-config-port port-for config)
  (cond
   ((postgresql-connection-config? config)
    (postgresql-connection-config
     (inherit config)
     (port (port-for 'postgresql))))
   ((mysql-connection-config? config)
    (mysql-connection-config
     (inherit config)
     (port (port-for 'mysql))))
   ((mongodb-connection-config? config)
    (mongodb-connection-config
     (inherit config)
     (port (port-for 'mongodb))))
   ((elasticsearch-connection-config? config)
    (elasticsearch-connection-config
     (inherit config)
     (port (port-for 'elasticsearch))))
   ((redis-connection-config? config)
    (redis-connection-config
     (inherit config)
     (port (port-for 'redis))))
   ((elasticsearch-connection-config? config)
    (elasticsearch-connection-config
     (inherit config)
     (port (port-for 'elasticsearch))))
   ((memcached-connection-config? config)
    (memcached-connection-config
     (servers (map (match-lambda*
                     (((host))
                      (list host (port-for 'memcached)))
                     (((host old-port))
                      (list host (port-for 'memcached)))
                     (((host old-port weight))
                      (list host (port-for 'memcached) weight)))
                   (memcached-connection-config-servers config)))))
   ((rabbitmq-connection-config? config)
    ;; TODO
    config)
   (else (backtrace)
         (error "unknown database connection config " config))))

(define (ensure-database-user-exists-on-service-startup s)
  (let
      ((parameters (service-parameters s)))
    (if (not (list? parameters))
        s
        (let* ((ssc (find service-startup-config? parameters))
               (database-connection-configs
                (filter database-connection-config? parameters)))
          (service
           (service-kind s)
           (map
            (lambda (parameter)
              (if (service-startup-config? parameter)
                  (service-startup-config-add-pre-startup-scripts
                   parameter
                   (concatenate
                    (map
                     (lambda (config)
                       (cond
                        ((postgresql-connection-config? config)
                         `((postgresql
                            .
                            ,(postgresql-create-user-for-database-connection
                              config))))
                        ((mysql-connection-config? config)
                         `((mysql
                            .
                            ,(mysql-create-user-for-database-connection
                              config))))
                        ((mongodb-connection-config? config)
                         '()) ;; TODO
                        ((redis-connection-config? config)
                         '()) ;; redis does not require any setup
                        ((memcached-connection-config? config)
                         '()) ;; memcache does not require any setup
                        ((elasticsearch-connection-config? config)
                         '()) ;; TODO
                        ((rabbitmq-connection-config? config)
                         `((rabbitmq
                            .
                            ,(rabbitmq-create-user-for-connection-config
                              config))))
                        (else
                         (error "Unrecognised database config"))))
                     database-connection-configs))
                   #:run-as-root #t)
                  parameter))
            parameters))))))
