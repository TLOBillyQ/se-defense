(ns acceptance.bb-process
  "babashka.process entry points resolved lazily so this project's namespaces
  (and their specs under JVM Clojure) load without the babashka runtime.")

(defn process!
  ([] (requiring-resolve 'babashka.process/process))
  ([& args] (apply (requiring-resolve 'babashka.process/process) args)))

(defn destroy!
  [proc]
  (try ((requiring-resolve 'babashka.process/destroy-process) proc)
       (catch Throwable _ nil)))
