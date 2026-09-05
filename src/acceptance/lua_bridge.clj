(ns acceptance.lua-bridge
  "Spawns one headless Lua acceptance server per scenario execution and
  exchanges NDJSON commands with it. babashka.process is resolved lazily so the
  namespace also loads under JVM Clojure (unit specs use fake bridges)."
  (:require [acceptance.json :as json]))

(defn- process!
  ([] (requiring-resolve 'babashka.process/process))
  ([& args] (apply (requiring-resolve 'babashka.process/process) args)))

(defn- destroy!
  [proc]
  (try ((requiring-resolve 'babashka.process/destroy-process) proc)
       (catch Throwable _ nil)))

(defn spawn-bridge!
  "Starts the acceptance server as a child process. Returns a bridge map with
  :send! (command -> response map) and :close!."
  ([] (spawn-bridge! 30000))
  ([timeout-ms]
   (let [lua (or (System/getenv "ACCEPTANCE_LUA") "lua")
         server "tools/headless/acceptance_server.lua"
         proc (process! [lua server] {:in :pipe :out :pipe :err :inherit})
         in (java.io.OutputStreamWriter. (:in proc) "UTF-8")
         out (java.io.BufferedReader. (java.io.InputStreamReader. (:out proc) "UTF-8"))]
     {:proc proc
      :timeout-ms timeout-ms
      :close! (fn []
                (try (.close in) (catch Throwable _ nil))
                (destroy! proc))
      :send! (fn [cmd]
               (let [answer (future
                              (.write in (json/write-json cmd))
                              (.write in "\n")
                              (.flush in)
                              (let [line (.readLine out)]
                                (when-not line
                                  (throw (ex-info "acceptance server closed" {:kind :infra})))
                                (json/read-json line)))
                     resp (try
                            (deref answer timeout-ms ::timeout)
                            (catch Throwable e
                              (throw (ex-info (str "bridge error: " (or (ex-message e) (str e)))
                                              {:kind :infra} e))))]
                 (when (= ::timeout resp)
                   (destroy! proc)
                   (throw (ex-info (str "bridge timeout after " timeout-ms "ms")
                                   {:kind :infra})))
                 (when-not (= true (get resp "ok"))
                   (throw (ex-info (str "server error: " (or (get resp "error") "unknown"))
                                   {:kind :infra})))
                 resp))})))
