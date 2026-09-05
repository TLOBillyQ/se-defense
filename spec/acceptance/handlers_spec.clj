(ns spec.acceptance.handlers-spec
  (:require [speclj.core :refer :all]
            [acceptance.handlers :as h]
            [acceptance.runtime :as rt]))

(defn- fake-bridge
  "Records every command; responses is a fn of the command map returning a
  decode-shaped response (string keys, \"ok\" true), defaulting to ok."
  [responses]
  (let [calls (atom [])
        state (atom nil)]
    {:calls calls
     :state state
     :send! (fn [cmd]
              (swap! calls conj cmd)
              (let [r (responses cmd)]
                (if (fn? r)
                  (r)
                  (or r {"ok" true}))))}))

(defn- world
  [bridge responses]
  {:bridge bridge
   :extras (atom {})
   :example {}})

(defn- dispatch
  [w text]
  (rt/dispatch-step w h/registry
                    {:keyword :When :text text :parameters []}))

(describe "handlers: game boot"
  (it "sends a client_ready message for 'the client is ready'"
    (let [b (fake-bridge (fn [_] {"ok" true}))
          w (world b nil)]
      (dispatch w "the client is ready")
      (should= {:cmd "send" :msg {:kind "client_ready"}} (first @(:calls b)))))

  (it "advances the game for 'the game advances N ticks'"
    (let [b (fake-bridge (fn [_] {"ok" true}))
          w (world b nil)]
      (dispatch w "the game advances 101 ticks")
      (should= {:cmd "steps" :n 101} (first @(:calls b)))))

  (it "sends a place intent with the captured key"
    (let [b (fake-bridge (fn [_] {"ok" true}))
          w (world b nil)]
      (dispatch w "the client sends a place intent for turret")
      (should= {:cmd "send" :msg {:kind "input" :itype "place" :key "turret"}}
               (first @(:calls b))))))

(describe "handlers: placement flow"
  (it "records money before a tap and sends the tap coordinates"
    (let [b (fake-bridge (fn [cmd]
                           (if (= "state" (:cmd cmd))
                             {"ok" true "state" {"money" 100}}
                             {"ok" true})))
          w (world b nil)]
      (dispatch w "the client taps the board at 3 0")
      (should= 2 (count @(:calls b)))
      (should= {:cmd "send" :msg {:kind "input" :itype "tap" :x 3 :z 0}}
               (second @(:calls b)))
      (should= 100 (:money-before-tap (deref (:extras w))))))

  (it "asserts the money decreased by the exact cost"
    (let [money (atom 100)
          b (fake-bridge (fn [cmd]
                           (if (= "state" (:cmd cmd))
                             {"ok" true "state" {"money" @money}}
                             {"ok" true})))
          w (world b nil)]
      (dispatch w "the client taps the board at 3 0")
      (reset! money 0)
      (reset! money 10)
      (should= nil (dispatch w "the money decreased by 90"))
      (let [e (try
                (dispatch w "the money decreased by 100")
                (catch clojure.lang.ExceptionInfo e e))]
        (should= "expected decrease 100, got 90 (before 100, now 10)"
                 (ex-message e)))))

  (it "asserts no building is being placed when placing is nil"
    (let [b (fake-bridge (fn [cmd]
                           (if (= "state" (:cmd cmd))
                             {"ok" true "state" {"placing" nil}}
                             {"ok" true})))
          w (world b nil)]
      (dispatch w "no building is being placed")
      (should-throw clojure.lang.ExceptionInfo
        (let [b2 (fake-bridge (fn [cmd]
                                (if (= "state" (:cmd cmd))
                                  {"ok" true "state" {"placing" "radar"}}
                                  {"ok" true})))
              w2 (world b2 nil)]
          (dispatch w2 "no building is being placed"))))))

(describe "handlers: state assertions"
  (it "asserts the game mode from state"
    (let [b (fake-bridge (fn [cmd]
                           (if (= "state" (:cmd cmd))
                             {"ok" true "state" {"mode" "Playing"}}
                             {"ok" true})))
          w (world b nil)]
      (dispatch w "the game is in Playing mode")
      (should-throw clojure.lang.ExceptionInfo
        (dispatch w "the game is in Pregame mode"))))

  (it "asserts the exact money value"
    (let [b (fake-bridge (fn [cmd]
                           (if (= "state" (:cmd cmd))
                             {"ok" true "state" {"money" 100}}
                             {"ok" true})))
          w (world b nil)]
      (dispatch w "the money is 100")
      (should-throw clojure.lang.ExceptionInfo
        (dispatch w "the money is 99")))))

(describe "handlers: entities"
  (it "asserts the building count on the board"
    (let [b (fake-bridge (fn [cmd]
                           (if (= "entities" (:cmd cmd))
                             {"ok" true "entities" {"count" 1 "items" []}}
                             {"ok" true})))
          w (world b nil)]
      (dispatch w "the relay count on the board is 1")
      (should= {:cmd "entities" :prefab "relay"} (first @(:calls b)))
      (should-throw clojure.lang.ExceptionInfo
        (dispatch w "the relay count on the board is 2"))))

  (it "asserts the total entity count"
    (let [b (fake-bridge (fn [cmd]
                           (if (= "entities" (:cmd cmd))
                             {"ok" true "entities" {"count" 7 "items" []}}
                             {"ok" true})))
          w (world b nil)]
      (dispatch w "the entity count on the board is 7")
      (should= {:cmd "entities" :prefab "__all__"} (first @(:calls b)))))

  (it "asserts a building has power"
    (let [b (fake-bridge (fn [cmd]
                           (if (= "entities" (:cmd cmd))
                             {"ok" true
                              "entities" {"count" 1
                                          "items" [{"prefab" "radar" "has_power" true}]}}
                             {"ok" true})))
          w (world b nil)]
      (dispatch w "the radar has power")
      (should-throw clojure.lang.ExceptionInfo
        (let [b2 (fake-bridge (fn [cmd]
                                (if (= "entities" (:cmd cmd))
                                  {"ok" true
                                   "entities" {"count" 1
                                               "items" [{"prefab" "radar" "has_power" false}]}}
                                  {"ok" true})))
              w2 (world b2 nil)]
          (dispatch w2 "the radar has power"))))))

(describe "handlers: GM and restart"
  (it "calls GM money with the resolved amount"
    (let [b (fake-bridge (fn [_] {"ok" true}))
          w (world b nil)]
      (dispatch w "the gm sets the money to 1000")
      (should= {:cmd "gm" :fn "money" :args ["1000"]} (first @(:calls b)))))

  (it "calls GM mine_out and kill_core"
    (let [b (fake-bridge (fn [_] {"ok" true}))
          w (world b nil)]
      (dispatch w "the gm mines out all resources")
      (dispatch w "the gm destroys the core")
      (should= [{:cmd "gm" :fn "mine_out" :args []}
                {:cmd "gm" :fn "kill_core" :args []}]
               @(:calls b))))

  (it "sends a restart intent for 'the client restarts the game'"
    (let [b (fake-bridge (fn [_] {"ok" true}))
          w (world b nil)]
      (dispatch w "the client restarts the game")
      (should= {:cmd "send" :msg {:kind "input" :itype "restart"}}
               (first @(:calls b))))))
