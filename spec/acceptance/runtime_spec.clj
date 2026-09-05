(ns spec.acceptance.runtime-spec
  (:require [speclj.core :refer :all]
            [acceptance.runtime :as rt]))

(def ^:private dispatch-handlers
  [[#"^a green step$" (fn [w caps resolve] nil)]
   [#"^the value is <(\w+)>$"
    (fn [w caps resolve]
      (let [v (resolve (first caps))]
        (when-not (= v "expected")
          (throw (ex-info (str "got " v)
                          {:kind :assertion})))))]])

(describe "expand-executions"
  (it "prepends background steps to every scenario"
    (let [ir {:name "f"
              :background [{:keyword "Given" :text "a base" :parameters []}]
              :scenarios [{:name "s" :steps [{:keyword "Then" :text "a step" :parameters []}] :examples []}]}]
      (should= 1 (count (rt/expand-executions ir)))
      (let [steps (-> (rt/expand-executions ir) first :steps)]
        (should= 2 (count steps))
        (should= "a base" (-> steps first :text))
        (should= "a step" (-> steps second :text)))))

  (it "creates one execution per example row preserving row order"
    (let [ir {:name "f"
              :background []
              :scenarios [{:name "s"
                           :steps [{:keyword "When" :text "use <v>" :parameters ["v"]}]
                           :examples [{"v" "a"} {"v" "b"}]}]}]
      (should= 2 (count (rt/expand-executions ir)))
      (should= {"v" "a"} (-> (rt/expand-executions ir) first :example))
      (should= {"v" "b"} (-> (rt/expand-executions ir) second :example))))

  (it "creates one execution with an empty example when the scenario has no examples"
    (let [ir {:name "f" :background []
              :scenarios [{:name "s" :steps [] :examples []}]}]
      (let [x (first (rt/expand-executions ir))]
        (should= {} (:example x))
        (should= 1 (count (rt/expand-executions ir))))))

  (it "names executions <scenario>/example_<index>"
    (let [ir {:name "f" :background []
              :scenarios [{:name "s" :steps [] :examples [{"a" "1"} {"a" "2"}]}]}]
      (should= ["s/example_1" "s/example_2"]
               (mapv :name (rt/expand-executions ir))))))

(describe "dispatch-step"
  (it "routes a step to its handler and passes"
    (should= nil
             (rt/dispatch-step {} dispatch-handlers
                               {:keyword "Given" :text "a green step" :parameters []})))

  (it "resolves placeholder captures from the example values"
    (let [world {:example {"v" "expected"}}]
      (should= nil
               (rt/dispatch-step world dispatch-handlers
                                 {:keyword "Then" :text "the value is <v>" :parameters ["v"]}))))

  (it "fails when the resolved example value is wrong"
    (let [world {:example {"v" "wrong"}}]
      (should-throw clojure.lang.ExceptionInfo
        (rt/dispatch-step world dispatch-handlers
                          {:keyword "Then" :text "the value is <v>" :parameters ["v"]}))))

  (it "fails on unsupported step text"
    (should-throw clojure.lang.ExceptionInfo
      (rt/dispatch-step {} dispatch-handlers
                        {:keyword "Then" :text "no such step" :parameters []})))

  (it "fails when a placeholder is missing from the example"
    (let [world {:example {}}]
      (should-throw clojure.lang.ExceptionInfo
        (rt/dispatch-step world dispatch-handlers
                          {:keyword "Then" :text "the value is <v>" :parameters ["v"]})))))

(describe "run-execution!"
  (it "uses a fresh world for every execution via world-fn"
    (let [calls (atom 0)
          seen (atom [])
          world-fn (fn [] {:tag (swap! calls inc)})
          hs [[#"^tag it$" (fn [w caps resolve] (swap! seen conj (:tag w)))]]
          ir {:name "f" :background []
              :scenarios [{:name "s1" :steps [{:keyword "Given" :text "tag it" :parameters []}] :examples []}
                          {:name "s2" :steps [{:keyword "Given" :text "tag it" :parameters []}] :examples []}]}]
      (rt/execute-iris! {:ir ir :handlers hs :world-fn world-fn})
      (should= [1 2] @seen)))

  (it "disposes the world after a passing execution"
    (let [closed (atom 0)
          ir {:name "f" :background []
              :scenarios [{:name "s" :steps [] :examples []}]}
          results (rt/execute-iris!
                   {:ir ir :handlers []
                    :world-fn (fn [] {:dispose! (fn [] (swap! closed inc))})})]
      (should= :passed (:status (first results)))
      (should= 1 @closed)))

  (it "disposes the world after a failing execution"
    (let [closed (atom 0)
          hs [[#"^fail it$" (fn [_ _ _] (throw (ex-info "nope" {:kind :assertion})))]]
          ir {:name "f" :background []
              :scenarios [{:name "s" :steps [{:keyword "Then" :text "fail it" :parameters []}] :examples []}]}
          results (rt/execute-iris!
                   {:ir ir :handlers hs
                    :world-fn (fn [] {:dispose! (fn [] (swap! closed inc))})})]
      (should= :failed (:status (first results)))
      (should= 1 @closed)))

  (it "reports a cleanup failure as infrastructure error after a pass"
    (let [ir {:name "f" :background []
              :scenarios [{:name "s" :steps [] :examples []}]}
          results (rt/execute-iris!
                   {:ir ir :handlers []
                    :world-fn (fn [] {:dispose! (fn [] (throw (ex-info "close failed" {})))})})]
      (should= :infra (:status (first results)))
      (should= true (boolean (re-find #"world cleanup failed" (:message (first results))))))))

(describe "execute-iris!"
  (it "returns one pass result for a clean run"
    (let [base {:name "f" :background []
                :scenarios [{:name "s" :steps [] :examples []}]}
          results (rt/execute-iris! {:ir base :handlers [] :world-fn (fn [] {})})]
      (should= [{:name "s/example_1" :status :passed}] results)
      (should= {:executions 1 :failed 0 :infra 0}
               (rt/summarize-results results))))

  (it "returns assertion failures without aborting the run"
    (let [base {:name "f" :background []
                :scenarios [{:name "s" :steps [] :examples []}]}
          hs [[#"^fail it$" (fn [w caps r] (throw (ex-info "nope" {:kind :assertion})))]]
          ir (assoc base :scenarios [{:name "s" :steps [{:keyword "Then" :text "fail it" :parameters []}] :examples []}])
          results (rt/execute-iris! {:ir ir :handlers hs :world-fn (fn [] {})})
          summary (rt/summarize-results results)]
      (should= :failed (:status (first results)))
      (should= {:executions 1 :failed 1 :infra 0} summary)))

  (it "returns infrastructure errors separately"
    (let [base {:name "f" :background []
                :scenarios [{:name "s" :steps [] :examples []}]}
          hs [[#"^crash it$" (fn [w caps r] (throw (ex-info "boom" {:kind :infra})))]]
          ir (assoc base :scenarios [{:name "s" :steps [{:keyword "Then" :text "crash it" :parameters []}] :examples []}])
          results (rt/execute-iris! {:ir ir :handlers hs :world-fn (fn [] {})})
          summary (rt/summarize-results results)]
      (should= :infra (:status (first results)))
      (should= {:executions 1 :failed 0 :infra 1} summary)))

  (it "runs every execution from every scenario in IR order"
    (let [worlds (atom [])
          ir {:name "f" :background []
              :scenarios [{:name "s1" :steps [] :examples [{"a" "1"} {"a" "2"}]}
                          {:name "s2" :steps [] :examples []}]}]
      (rt/execute-iris! {:ir ir :handlers [] :world-fn (fn [] (swap! worlds conj :w) {})})
      (should= 3 (count @worlds)))))
