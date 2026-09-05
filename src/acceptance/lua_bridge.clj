(ns acceptance.lua-bridge
  "Spawns one headless Lua acceptance server per scenario execution and
  exchanges NDJSON commands with it. babashka.process is resolved lazily so the
  namespace also loads under JVM Clojure (unit specs inject fake processes)."
  (:require [acceptance.bb-process :as bbp]
            [acceptance.json :as json]))

(defn- write-command!
  [in cmd]
  (.write in (json/write-json cmd))
  (.write in "\n")
  (.flush in))

(defn- read-response!
  [out]
  (let [line (.readLine out)]
    (when-not line
      (throw (ex-info "acceptance server closed" {:kind :infra})))
    (json/read-json line)))

(defn- send-command!
  "Writes one command to the server and reads its response, enforcing the
  timeout and classifying server errors as infrastructure failures."
  [in out proc timeout-ms destroy cmd]
  (let [answer (future
                 (write-command! in cmd)
                 (read-response! out))
        resp (try
               (deref answer timeout-ms ::timeout)
               (catch Throwable e
                 (throw (ex-info (str "bridge error: " (or (ex-message e) (str e)))
                                 {:kind :infra} e))))]
    (when (= ::timeout resp)
      (destroy proc)
      (throw (ex-info (str "bridge timeout after " timeout-ms "ms")
                      {:kind :infra})))
    (when-not (= true (get resp "ok"))
      (throw (ex-info (str "server error: " (or (get resp "error") "unknown"))
                      {:kind :infra})))
    resp))

(defn- spawn*
  [{:keys [timeout-ms spawn destroy]
    :or {timeout-ms 30000
         spawn (fn [argv opts] (bbp/process! argv opts))
         destroy bbp/destroy!}}]
  (let [lua (or (System/getenv "ACCEPTANCE_LUA") "lua")
        server "tools/headless/acceptance_server.lua"
        proc (spawn [lua server] {:in :pipe :out :pipe :err :inherit})
        in (java.io.OutputStreamWriter. (:in proc) "UTF-8")
        out (java.io.BufferedReader. (java.io.InputStreamReader. (:out proc) "UTF-8"))]
    {:proc proc
     :timeout-ms timeout-ms
     :close! (fn []
               (try
                 (destroy proc)
                 (finally
                   (try (.close in) (catch Throwable _ nil))
                   (try (.close out) (catch Throwable _ nil)))))
     :send! (fn [cmd] (send-command! in out proc timeout-ms destroy cmd))}))

(defn spawn-bridge!
  "Starts the acceptance server as a child process. Returns a bridge map with
  :send! (command -> response map) and :close!. opts: :timeout-ms, and for
  tests :spawn (argv opts -> process map) and :destroy (process -> nil)."
  ([] (spawn* {}))
  ([timeout-ms]
   (spawn* (if (map? timeout-ms)
             timeout-ms
             {:timeout-ms timeout-ms}))))

;; clj-mutate-manifest-begin
;; {:version 2, :hash-algorithm :sha256-source-v1, :verified? true, :tested-at "2026-09-05T11:14:53.961683+08:00", :module-hash "d3b1c07ee5eb9032ae451e443b6fd7d430950144834f8a4ff4250c82cdb60809", :provenance {:mutation-rules-version "3", :test-command "speclj -f documentation spec", :test-roots ["spec"], :test-profile-fingerprint "41f17b24aa38e88cefaa35ae3a902ecb76222ad0f99aa027bcda6b7f2fda1dc8"}, :forms [{:id "form/0/ns", :kind "ns", :line 1, :end-line 6, :hash "265b1230dc1c245156f554d0d138caab2a10c5bf82c4535da4e0e8779eade1ce"} {:id "defn-/write-command!", :kind "defn-", :line 8, :end-line 12, :hash "87b041a355c39fe09bf44646c60b5f7d56fd1f3f35bd0d5bb34d0d42c83128c1"} {:id "defn-/read-response!", :kind "defn-", :line 14, :end-line 19, :hash "502775b9b00466da03a9b69bf5cacc376c5b45af963660a4556bea0ceeaf4006"} {:id "defn-/send-command!", :kind "defn-", :line 21, :end-line 40, :hash "3e9682f6e926ad0d0a6e6c0f20429e00f4d224946076724ae1774c110cd51e9c"} {:id "defn-/spawn*", :kind "defn-", :line 42, :end-line 60, :hash "d00e43c04c87aa5dcd2d1d6f03afe8f992420481dd0973c21d667bdc67c79ad9"} {:id "defn/spawn-bridge!", :kind "defn", :line 62, :end-line 70, :hash "7914a5b4f5a8bbe03a3ba0db756f9b4851feac53461cd0afdc49b8046ff7e000"}]}
;; clj-mutate-manifest-end
