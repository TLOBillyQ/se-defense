(ns acceptance.adapter
  "Runner adapter for APS Gherkin acceptance mutation: a persistent worker
  reading newline-delimited JSON jobs on stdin and answering with one JSON
  response per job. Spawns generated test entry points against the supplied
  (mutated) IR and classifies test_success / test_failure /
  infrastructure_error."
  (:require [acceptance.bb-process :as bbp]
            [acceptance.json :as json]
            [acceptance.keyed :as keyed]
            [clojure.string :as str])
  (:import (java.io BufferedReader BufferedWriter File FileReader
                    InputStreamReader OutputStreamWriter StringReader
                    StringWriter)))

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
  classifies the outcome. opts: {:exec f :root dir}; f is called with
  [command-vector timeout-ms] and returns {:exit N :out s :err s}."
  [job {:keys [exec]}]
  (let [feature-json (keyed/get-k job "feature_json")
        gen-dir (keyed/get-k job "generated_dir")
        timeout (parse-timeout (keyed/get-k job "timeout"))
        id (keyed/get-k job "id")
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

(defn -main
  [& _]
  (handle-jobs *in* *out*
               {:exec default-exec
                :root (or (System/getenv "ACCEPTANCE_PROJECT_ROOT")
                          (System/getProperty "user.dir"))}))

(when (= (str *file*) (System/getProperty "babashka.file"))
  (apply -main *command-line-args*))
