(ns acceptance.runtime
  "APS acceptance runtime: expands scenario executions, dispatches steps to
  project step handlers, and returns per-execution results."
  (:require [acceptance.json :as json]
            [clojure.string :as str]))

(defn expand-executions
  "Turns a feature IR into scenario executions. Background steps are prepended
  to every execution; examples expand to one execution per row; scenarios
  without examples run once with an empty example object."
  [{:keys [background scenarios]}]
  (let [bg (vec (or background []))]
    (vec
     (for [scenario (vec scenarios)
           :let [ex (:examples scenario)
                 rows (if (seq ex) (vec ex) [{}])]
           i (range (count rows))]
       {:name (str (:name scenario) "/example_" (inc i))
        :scenario-name (:name scenario)
        :steps (into bg (:steps scenario))
        :example (nth rows i)}))))

(defn resolve-value
  "Resolves a capture to its example value, or keeps the literal capture text
  when the example has no such key."
  [example capture]
  (let [v (get example capture)]
    (if (some? v) v capture)))

(defn- check-placeholders!
  "Fails the execution when a placeholder has no value in the example."
  [example step]
  (when-let [missing (seq (remove #(contains? example %)
                                  (distinct (:parameters step))))]
    (throw (ex-info (str "missing example value(s): " (str/join ", " missing))
                    {:kind :assertion}))))

(defn dispatch-step
  "Routes one step to the first matching handler. Handlers receive the world,
  the regex captures, and a resolve fn (capture -> example value or literal)."
  [world handlers step]
  (let [example (:example world)]
    (check-placeholders! example step)
    (loop [hs (seq handlers)]
      (if-let [[pattern handler] (first hs)]
        (if-let [m (re-matches pattern (:text step))]
          (handler world (rest m) (partial resolve-value example))
          (recur (next hs)))
        (throw (ex-info (str "unsupported step: " (name (:keyword step))
                             " " (:text step))
                        {:kind :assertion}))))))

(defn- dispose-world!
  [world result]
  (if-let [dispose! (:dispose! world)]
    (try
      (dispose!)
      result
      (catch Throwable e
        (if (= :passed (:status result))
          (assoc result
                 :status :infra
                 :message (str "world cleanup failed: "
                               (or (ex-message e) (str e))))
          result)))
    result))

(defn run-execution!
  "Runs one scenario execution with a fresh world. The world may provide
  :dispose! for IO resources; cleanup runs after success and failure."
  [{:keys [handlers world-fn]} execution]
  (let [world (assoc (world-fn)
                     :example (:example execution)
                     :execution-name (:name execution))]
    (dispose-world!
     world
     (try
       (doseq [step (:steps execution)]
         (dispatch-step world handlers step))
       {:name (:name execution) :status :passed}
       (catch Throwable e
         {:name (:name execution)
          :status (if (= :infra (:kind (ex-data e))) :infra :failed)
          :message (or (ex-message e) (str e))})))))

(defn execute-iris!
  "Runs all executions of a feature IR and returns their result maps."
  [{:keys [ir handlers world-fn]}]
  (mapv (fn [exec]
          (run-execution! {:handlers handlers :world-fn world-fn} exec))
        (expand-executions ir)))

(defn summarize-results
  "Summarizes execution result maps into counts for an exit reporter."
  [results]
  {:executions (count results)
   :failed (count (filter #(= :failed (:status %)) results))
   :infra (count (filter #(= :infra (:status %)) results))})

(defn normalize-ir
  "Converts parser JSON IR (string keys) into the runtime shape: keyword keys
  for structure, string keys retained for example objects."
  [ir]
  (letfn [(step [s] {:keyword (keyword (get s "keyword"))
                     :text (get s "text")
                     :parameters (vec (get s "parameters" []))})
          (scenario [s] {:name (get s "name")
                         :steps (mapv step (get s "steps" []))
                         :examples (mapv (fn [row] (into {} row))
                                         (get s "examples" []))})]
    {:name (get ir "name")
     :background (mapv step (get ir "background" []))
     :scenarios (mapv scenario (get ir "scenarios"))}))

(defn parse-ir
  "Reads parser JSON IR from a file into the runtime shape."
  [path]
  (normalize-ir (json/read-json (slurp path))))

(defn execute-json-ir!
  "Parses an IR file and runs all of its executions."
  [path handlers world-fn]
  (execute-iris! {:ir (parse-ir path) :handlers handlers :world-fn world-fn}))

;; clj-mutate-manifest-begin
;; {:version 2, :hash-algorithm :sha256-source-v1, :verified? true, :tested-at "2026-09-05T11:14:01.716106+08:00", :module-hash "039740220d392c7f8e434c0f61d115e106c63364879d811b7f06fe50ee9e9f5f", :provenance {:mutation-rules-version "3", :test-command "speclj -f documentation spec", :test-roots ["spec"], :test-profile-fingerprint "41f17b24aa38e88cefaa35ae3a902ecb76222ad0f99aa027bcda6b7f2fda1dc8"}, :forms [{:id "form/0/ns", :kind "ns", :line 1, :end-line 5, :hash "b83c3247e55eb9cd63af95726a628ba04ad4347ca6d9f2059bbd3740ac107304"} {:id "defn/expand-executions", :kind "defn", :line 7, :end-line 21, :hash "ead026f8e034063682a1ec2187fbf1b0118730ee9c4ee3b70d6378850465ff69"} {:id "defn/resolve-value", :kind "defn", :line 23, :end-line 28, :hash "b27d4cb2a3f70c84df48d77cd5f1009073ec7a42c8ca74b52d2faa332a105c02"} {:id "defn-/check-placeholders!", :kind "defn-", :line 30, :end-line 36, :hash "14129b44be82d9e8190dfae9b2f82b812673199d63b850a8cccf38f504f50ceb"} {:id "defn/dispatch-step", :kind "defn", :line 38, :end-line 51, :hash "f425f6f0693b767c5afb7d64a052363992b47c8e45fb5d685dc38ba426307137"} {:id "defn-/dispose-world!", :kind "defn-", :line 53, :end-line 66, :hash "a0387478f75fccd5f31a724f29c3752a40032dd830584a967f4855e668205376"} {:id "defn/run-execution!", :kind "defn", :line 68, :end-line 84, :hash "f514740db67ae1e197a6b0ed24815182f85775e1453c1fe6f1d387dbcc633ef9"} {:id "defn/execute-iris!", :kind "defn", :line 86, :end-line 91, :hash "7dd006cd2414ddff10fc7a1c1eb57b4d75da8a9019e67c778dbd4133feaea190"} {:id "defn/summarize-results", :kind "defn", :line 93, :end-line 98, :hash "706da5251dec20a0f785c8295313a4bd3f79f3bd6683705e98ff47eed887b379"} {:id "defn/normalize-ir", :kind "defn", :line 100, :end-line 113, :hash "441c9bf5f78bcbb14cd62d2cabee6f9398ba4a2c67c204fcfda965f84427afcf"} {:id "defn/parse-ir", :kind "defn", :line 115, :end-line 118, :hash "e50d6bcd540ffbd8db0d56ccb492a4af1352db4b32eb3c4d5021a8ee6bf03839"} {:id "defn/execute-json-ir!", :kind "defn", :line 120, :end-line 123, :hash "9bdb286bb4ad7d43f976ce753fbcfae4a35a3020416b166982f3fc4580cb5bac"}]}
;; clj-mutate-manifest-end
