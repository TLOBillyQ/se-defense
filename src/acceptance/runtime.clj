(ns acceptance.runtime
  "APS acceptance runtime: expands scenario executions, dispatches steps to
  project step handlers, and reports per-execution results."
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

(defn run-execution!
  "Runs one scenario execution with a fresh world. Returns a result map."
  [{:keys [handlers world-fn]} execution]
  (let [world (assoc (world-fn)
                     :example (:example execution)
                     :execution-name (:name execution))]
    (try
      (doseq [step (:steps execution)]
        (dispatch-step world handlers step))
      {:name (:name execution) :status :passed}
      (catch Throwable e
        {:name (:name execution)
         :status (if (= :infra (:kind (ex-data e))) :infra :failed)
         :message (or (ex-message e) (str e))}))))

(defn run-iris!
  "Runs all executions of a feature IR. Prints one line per execution and
  returns {:executions N :failed N :infra N}."
  [{:keys [ir handlers world-fn]}]
  (let [results (mapv (fn [exec]
                        (run-execution! {:handlers handlers :world-fn world-fn} exec))
                      (expand-executions ir))]
    (doseq [r results]
      (case (:status r)
        :passed (println "  ok   " (:name r))
        (println "  FAIL " (:name r) ": " (:message r))))
    {:executions (count results)
     :failed (count (filter #(= :failed (:status %)) results))
     :infra (count (filter #(= :infra (:status %)) results))}))

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

(defn run-json-ir!
  "Parses an IR file (with clojure keys) and runs all of its executions."
  [path handlers world-fn]
  (run-iris! {:ir (parse-ir path) :handlers handlers :world-fn world-fn}))
