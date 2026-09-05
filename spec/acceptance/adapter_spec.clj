(ns spec.acceptance.adapter-spec
  (:require [speclj.core :refer :all]
            [acceptance.adapter :as a]
            [acceptance.json :as json]))

(defn- fake-exec
  "exec-fn that records commands and returns a canned result."
  [result]
  (let [calls (atom [])]
    {:calls calls
     :exec (fn [cmd timeout-ms]
             (swap! calls conj {:cmd cmd :timeout timeout-ms})
             (if (fn? result) (result cmd) result))}))

(defn- make-test-dir
  []
  (let [parent (java.io.File. (System/getProperty "user.dir") "tmp")
        dir (java.io.File. parent (str "acceptance-adapter-"
                                       (java.util.UUID/randomUUID)))]
    (.mkdirs parent)
    (.mkdirs dir)
    (.deleteOnExit dir)
    (str dir)))

(defn- with-test [dir]
  (let [f (java.io.File. (str dir "/features-base-defence-feature_acceptance_test.clj"))]
    (spit (str f) "#!/usr/bin/env sh\n")
    (.setExecutable f true false)
    f))

(defn- fixture-job-line
  []
  (let [dir (make-test-dir)]
    (with-test dir)
    (json/write-json (array-map
                      :id "m1"
                      :feature_json (str dir "/mut.json")
                      :generated_dir dir
                      :work_dir dir
                      :timeout "30s"))))

(defn- fake-proc
  [exited?]
  (proxy [java.lang.Process] []
    (waitFor [timeout unit] exited?)
    (exitValue [] 0)))

(defn- fake-spawn
  [exited? calls]
  (fn [cmd opts]
    (let [proc-map {:proc (fake-proc exited?)
                    :out (future "captured out")
                    :err (future "captured err")}]
      (swap! calls conj {:cmd cmd :opts opts :proc-map proc-map})
      proc-map)))

(describe "parse-timeout"
  (it "parses seconds and milliseconds, defaulting to 30s"
    (should= 30000 (a/parse-timeout nil))
    (should= 30000 (a/parse-timeout "30s"))
    (should= 1500 (a/parse-timeout "1500ms"))
    (should= 30000 (a/parse-timeout "bogus"))))

(describe "generated-tests"
  (it "finds only test entry points ending in _acceptance_test.clj"
    (let [dir (make-test-dir)]
      (with-test dir)
      (spit (str dir "/other.clj") "x")
      (should= ["features-base-defence-feature_acceptance_test.clj"]
               (mapv #(.getName (java.io.File. %)) (a/generated-tests dir)))
      (should= [] (a/generated-tests (str dir "/missing"))))))

(describe "run-job"
  (it "classifies a clean test run as test_success"
    (let [dir (make-test-dir)
          _ (with-test dir)
          {calls :calls exec :exec} (fake-exec {:exit 0 :out "ok\n" :err ""})
          job {"id" "m1" "feature_json" (str dir "/mut.json")
               "generated_dir" dir "work_dir" dir "timeout" "30s"}
          result (a/run-job job {:exec exec})]
      (should= "test_success" (get result "outcome"))
      (should= "ok\n" (get result "output"))
      (should= "" (get result "error"))
      (should= "m1" (get result "id"))
      (should= true (number? (get result "duration")))
      (should= true (<= 0 (get result "duration") 100000000000))
      (should= 1 (count @calls))
      (should= [(str dir "/features-base-defence-feature_acceptance_test.clj") (str dir "/mut.json")]
               (-> @calls first :cmd))
      (should= 30000 (-> @calls first :timeout))))

  (it "classifies exit 1 as test_failure"
    (let [dir (make-test-dir)
          _ (with-test dir)
          {exec :exec} (fake-exec {:exit 1 :out "FAIL\n" :err ""})
          job {"id" "m2" "feature_json" (str dir "/mut.json")
               "generated_dir" dir "work_dir" dir "timeout" "30s"}
          result (a/run-job job {:exec exec})]
      (should= "test_failure" (get result "outcome"))
      (should= "FAIL\n" (get result "output"))))

  (it "classifies exit 2 and odd exit codes as infrastructure_error"
    (let [dir (make-test-dir)
          _ (with-test dir)
          {exec :exec} (fake-exec {:exit 2 :out "" :err "boom"})
          job {"id" "m3" "feature_json" (str dir "/mut.json")
               "generated_dir" dir "work_dir" dir "timeout" "30s"}
          result (a/run-job job {:exec exec})]
      (should= "infrastructure_error" (get result "outcome"))
      (should= true (boolean (re-find #"boom" (str (get result "error")))))))

  (it "reports infrastructure_error when a job has no generated tests"
    (let [dir (make-test-dir)
          fe (fake-exec {:exit 0 :out "" :err ""})
          job {"id" "m4" "feature_json" (str dir "/mut.json")
               "generated_dir" dir "work_dir" dir "timeout" "30s"}
          result (a/run-job job {:exec (:exec fe)})]
      (should= "infrastructure_error" (get result "outcome"))
      (should= true (<= 0 (get result "duration") 100000000000))
      (should= 0 (count @(:calls fe)))))

  (it "treats an exec exception as infrastructure_error"
    (let [dir (make-test-dir)
          _ (with-test dir)
          {exec :exec} (fake-exec (fn [_] (throw (ex-info "no process" {}))))
          job {"id" "m5" "feature_json" (str dir "/mut.json")
               "generated_dir" dir "work_dir" dir "timeout" "30s"}
          result (a/run-job job {:exec exec})]
      (should= "infrastructure_error" (get result "outcome"))
      (should= true (<= 0 (get result "duration") 100000000000)))))

(describe "handle-jobs"
  (it "emits one response line per job line with the job id"
    (let [job-line (fixture-job-line)
          {exec :exec} (fake-exec {:exit 0 :out "ok\n" :err ""})
          in (java.io.StringReader. (str job-line "\n"))
          out (java.io.StringWriter.)]
      (a/handle-jobs in out {:exec exec})
      (let [lines (clojure.string/split-lines (str out))
            resp (json/read-json (first lines))]
        (should= 1 (count lines))
        (should= "m1" (get resp "id"))
        (should= "test_success" (get resp "outcome"))
        (should= true (<= 0 (get resp "duration") 100000000000)))))

  (it "answers malformed jobs with an infrastructure error response"
    (let [{exec :exec} (fake-exec {:exit 0 :out "ok\n" :err ""})
          in (java.io.StringReader. "not json\n")
          out (java.io.StringWriter.)]
      (a/handle-jobs in out {:exec exec})
      (let [resp (json/read-json (first (clojure.string/split-lines (str out))))]
        (should= "infrastructure_error" (get resp "outcome"))
        (should= 0 (get resp "duration")))))

  (it "skips blank lines"
    (let [job-line (fixture-job-line)
          {exec :exec} (fake-exec {:exit 0 :out "ok\n" :err ""})
          in (java.io.StringReader. (str "\n" job-line "\n\n"))
          out (java.io.StringWriter.)]
      (a/handle-jobs in out {:exec exec})
      (should= 1 (count (clojure.string/split-lines (str out)))))))

(describe "default-exec"
  (it "runs the command and collects output and exit code"
    (let [calls (atom [])
          result (a/default-exec ["bb" "spec"] 1000
                                 {:spawn (fake-spawn true calls)})]
      (should= {:exit 0 :out "captured out" :err "captured err"} result)
      (let [{:keys [cmd opts]} (first @calls)]
        (should= ["bb" "spec"] cmd)
        (should= {:dir (System/getProperty "user.dir")
                  :out :string :err :string} opts))))

  (it "destroys the process and throws on timeout"
    (let [calls (atom [])
          destroyed (atom nil)
          result (try
                   (a/default-exec ["bb" "spec"] 1000
                                   {:spawn (fake-spawn false calls)
                                    :destroy (fn [proc] (reset! destroyed proc))})
                   (catch clojure.lang.ExceptionInfo e e))]
      (should= true (boolean (re-find #"timeout after 1000ms" (ex-message result))))
      (should= true (= (:proc-map (first @calls)) @destroyed))))

  (it "destroys the process and throws when waitFor fails"
    (let [destroyed (atom nil)
          result (try
                   (a/default-exec ["bb" "spec"] 1000
                                   {:spawn (fn [_ _]
                                             {:proc (proxy [java.lang.Process] []
                                                      (waitFor [timeout unit]
                                                        (throw
                                                         (java.lang.InterruptedException.
                                                          "wait failed")))
                                                      (exitValue [] 0))
                                              :out (future "")
                                              :err (future "")})
                                    :destroy (fn [proc] (reset! destroyed proc))})
                   (catch clojure.lang.ExceptionInfo e e))]
      (should= true (boolean (re-find #"timeout after 1000ms" (ex-message result))))
      (should= true (some? @destroyed)))))
