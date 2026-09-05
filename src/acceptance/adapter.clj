(ns acceptance.adapter
  "Runner adapter for APS Gherkin acceptance mutation: a persistent worker
  reading newline-delimited JSON jobs on stdin and answering with one JSON
  response per job. Spawns generated test entry points against the supplied
  (mutated) IR and classifies test_success / test_failure /
  infrastructure_error."
  (:require [acceptance.bb-process :as bbp]
            [acceptance.json :as json]
            [clojure.string :as str])
  (:import (java.io BufferedReader BufferedWriter File InputStreamReader
                    OutputStreamWriter)))

(defn parse-timeout
  "Parses <duration>s or <duration>ms into milliseconds; defaults to 30s."
  [s]
  (if-let [m (re-matches #"(\d+)(ms|s)?" (str (or s "30s")))]
    (let [n (Long/parseLong (nth m 1))
          unit (or (nth m 2) "s")]
      (* n (if (= unit "ms") 1 1000)))
    30000))

(defn generated-tests
  "Test entry points under the generated dir, sorted for determinism."
  [dir]
  (let [files (or (.listFiles (File. (str dir))) (make-array File 0))]
    (->> files
         (keep (fn [f] (when (and (.isFile f)
                                  (re-find #"_acceptance_test\.clj$" (.getName f)))
                         (.getPath f))))
         vec
         sort)))

(defn- classify
  [exit]
  (case (int exit)
    0 "test_success"
    1 "test_failure"
    "infrastructure_error"))

(defn- combine-results
  [results]
  (let [classes (mapv #(classify (:exit %)) results)
        output (str/join (map :out results))
        err (str/join (map :err results))]
    (cond
      (some #{"infrastructure_error"} classes)
      {"outcome" "infrastructure_error" "output" output "error" err}
      (some #{"test_failure"} classes)
      {"outcome" "test_failure" "output" output "error" ""}
      :else
      {"outcome" "test_success" "output" output "error" ""})))

(defn run-job
  "Runs every generated test entry point against the job's mutated IR and
  classifies the outcome. opts: {:exec f}; f is called with
  [command-vector timeout-ms] and returns {:exit N :out s :err s}."
  [job {:keys [exec]}]
  (let [feature-json (get job "feature_json")
        gen-dir (get job "generated_dir")
        timeout (parse-timeout (get job "timeout"))
        id (get job "id")
        started (System/nanoTime)]
    (try
      (let [tests (generated-tests gen-dir)]
        (if (seq tests)
          (let [results (mapv (fn [test] (exec [test feature-json] timeout)) tests)
                outcome (combine-results results)]
            (assoc outcome
                   "id" id
                   "duration" (- (System/nanoTime) started)))
          {:id id "outcome" "infrastructure_error"
           "output" "" "error" (str "no generated tests in " gen-dir)
           "duration" (- (System/nanoTime) started)}))
      (catch Throwable e
        {:id id "outcome" "infrastructure_error"
         "output" "" "error" (or (ex-message e) (str e))
         "duration" (- (System/nanoTime) started)}))))

(defn- as-reader
  [in]
  (if (instance? BufferedReader in)
    in
    (BufferedReader. (if (instance? java.io.Reader in)
                       in
                       (InputStreamReader. in)))))

(defn- as-writer
  [out]
  (if (instance? BufferedWriter out)
    out
    (BufferedWriter. (if (instance? java.io.Writer out)
                       out
                       (OutputStreamWriter. out)))))

(defn handle-jobs
  "One response line per job line; blank lines skipped; malformed jobs answer
  with an infrastructure error."
  [in out opts]
  (let [rdr (as-reader in)
        wr (as-writer out)]
    (loop [line (.readLine rdr)]
      (when line
        (let [trimmed (str/trim line)]
          (when-not (str/blank? trimmed)
            (let [resp (try
                         (let [job (json/read-json trimmed)]
                           (if (map? job)
                             (run-job job opts)
                             (throw (ex-info "job is not a JSON object" {}))))
                         (catch Throwable e
                           {"id" nil "outcome" "infrastructure_error"
                            "output" "" "error" (or (ex-message e) (str e))
                            "duration" 0}))]
              (.write wr (json/write-json resp))
              (.newLine wr)
              (.flush wr))))
        (recur (.readLine rdr))))))

(defn default-exec
  "Babashka exec: runs a command as a child process, collecting output and
  enforcing the timeout (kills the process on expiry). opts: :spawn (cmd opts ->
  process), :destroy (process -> nil), :dir; defaults to babashka.process."
  ([cmd timeout-ms] (default-exec cmd timeout-ms {}))
  ([cmd timeout-ms {:keys [spawn destroy dir]
                    :or {spawn (fn [cmd opts] (bbp/process! cmd opts))
                         destroy bbp/destroy!
                         dir (System/getProperty "user.dir")}}]
   (let [proc (spawn cmd {:dir dir :out :string :err :string})
         jproc (:proc proc)
         out-f (future (deref (:out proc)))
         err-f (future (deref (:err proc)))
         exited (try (.waitFor jproc (long timeout-ms)
                               java.util.concurrent.TimeUnit/MILLISECONDS)
                     (catch Throwable _ false))]
     (if exited
       {:exit (.exitValue jproc)
        :out (deref out-f 10000 "") :err (deref err-f 10000 "")}
       (do (destroy proc)
           (throw (ex-info (str "test runner timeout after " timeout-ms "ms") {})))))))

;; clj-mutate-manifest-begin
;; {:version 2, :hash-algorithm :sha256-source-v1, :verified? true, :tested-at "2026-09-05T11:14:16.489168+08:00", :module-hash "91e844de62725088aaff4454a8992a1dc1506a8796cacb07d3ccd767d956d010", :provenance {:mutation-rules-version "3", :test-command "speclj -f documentation spec", :test-roots ["spec"], :test-profile-fingerprint "41f17b24aa38e88cefaa35ae3a902ecb76222ad0f99aa027bcda6b7f2fda1dc8"}, :forms [{:id "form/0/ns", :kind "ns", :line 1, :end-line 11, :hash "0c347704b3dfc1eb151ed84de6ec8d7de9f69bf885c71b91599b833be3873433"} {:id "defn/parse-timeout", :kind "defn", :line 13, :end-line 20, :hash "b99a9c9efdca6ae258135393caa2bc9c4cab4868a8f4a9495abb1b4b68a0c98f"} {:id "defn/generated-tests", :kind "defn", :line 22, :end-line 31, :hash "cb559f0a2de1d5f4bd922db35795ae170f9a3f790f5988550df0703c8d06ed02"} {:id "defn-/classify", :kind "defn-", :line 33, :end-line 38, :hash "5f82eb99bba7f7f56e819ab94523f20d7bb712deaafb32ce9d2655e2e9f6ec76"} {:id "defn-/combine-results", :kind "defn-", :line 40, :end-line 51, :hash "c570a9311a116f11b67a0e36014fb7c2a2a3af695edb7b5f68b2dda71b156335"} {:id "defn/run-job", :kind "defn", :line 53, :end-line 77, :hash "aee9a043f1d40dc17b55a4751be1919ffae4702598b90c515567ad49f3fa74ed"} {:id "defn-/as-reader", :kind "defn-", :line 79, :end-line 85, :hash "dfc8d1947bd0a46c24a113db67341722c524175d14c11621018ad9e382b9eb18"} {:id "defn-/as-writer", :kind "defn-", :line 87, :end-line 93, :hash "f3d9f8679861d499343cdd4e796323b05000ac822535bc0e7377533cb0e310b5"} {:id "defn/handle-jobs", :kind "defn", :line 95, :end-line 117, :hash "e5654c45b4a9eaeb53034d0952b51e12b74ff6369299a3a01f5521d8322f4c49"} {:id "defn/default-exec", :kind "defn", :line 119, :end-line 139, :hash "3fe1a33074818a6ab65ceb87b062dd7571b5195a25e35accf2c0136d43073622"}]}
;; clj-mutate-manifest-end
