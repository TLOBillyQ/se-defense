(ns acceptance.handlers
  "Project step handlers connecting Gherkin step text to the headless Lua game
  through the acceptance server bridge. Regex captures are the default style;
  each capture resolves to the current example value when the example has a
  matching column name, otherwise to the capture text itself."
  (:require [acceptance.keyed :as keyed]))

(defn- check!
  [cond msg]
  (when-not cond
    (throw (ex-info msg {:kind :assertion}))))

(defn- parse-num
  [s]
  (let [v (Double/parseDouble (str s))]
    (if (== v (Math/floor v)) (long v) v)))

(defn- call!
  [world cmd]
  (let [b (:bridge world)]
    (when-not b
      (throw (ex-info "no bridge in world" {:kind :infra})))
    ((:send! b) cmd)))

(defn- state!
  [world]
  (keyed/get-k (call! world {:cmd "state"}) "state"))

(defn- entities!
  [world prefab]
  (keyed/get-k (call! world {:cmd "entities" :prefab prefab}) "entities"))

(defn- send-input!
  [world msg]
  (call! world {:cmd "send" :msg msg}))

(defn- gm!
  [world fn-name args]
  (call! world {:cmd "gm" :fn fn-name :args args}))

(defn- extras!
  [world]
  (or (:extras world) (atom {})))

(def registry
  "Step handler registry, first match wins. Patterns carry optional angle
  brackets so the same handler serves placeholder and literal step forms."
  [[#"^a fresh headless game$"
    (fn [world _captures _resolve] nil)]

   [#"^the client is ready$"
    (fn [world _captures _resolve]
      (call! world {:cmd "send" :msg {:kind "client_ready"}}))]

   [#"^the game advances ([0-9]+) ticks?$"
    (fn [world captures _resolve]
      (call! world {:cmd "steps" :n (parse-num (first captures))}))]

   [#"^the client sends a place intent for <?([A-Za-z0-9_]+)>?$"
    (fn [world captures resolve]
      (send-input! world {:kind "input" :itype "place" :key (resolve (first captures))}))]

   [#"^the client taps the board at <?(-?[A-Za-z0-9_.]+)>? <?(-?[A-Za-z0-9_.]+)>?$"
    (fn [world captures resolve]
      (let [state (state! world)]
        (swap! (extras! world) assoc :money-before-tap (keyed/get-k state "money")))
      (send-input! world {:kind "input" :itype "tap"
                          :x (parse-num (resolve (first captures)))
                          :z (parse-num (resolve (second captures)))}))]

   [#"^no building is being placed$"
    (fn [world _captures _resolve]
      (check! (nil? (keyed/get-k (state! world) "placing")) "expected no placing selection"))]

   [#"^the gm sets the money to <?([A-Za-z0-9_]+)>?$"
    (fn [world captures resolve]
      (gm! world "money" [(resolve (first captures))]))]

   [#"^the gm mines out all resources$"
    (fn [world _captures _resolve]
      (gm! world "mine_out" []))]

   [#"^the gm destroys the core$"
    (fn [world _captures _resolve]
      (gm! world "kill_core" []))]

   [#"^the client restarts the game$"
    (fn [world _captures _resolve]
      (send-input! world {:kind "input" :itype "restart"}))]

   [#"^the game is in <?([A-Za-z0-9_]+)>? mode$"
    (fn [world captures resolve]
      (let [mode (keyed/get-k (state! world) "mode")
            expected (resolve (first captures))]
        (check! (= expected mode)
                (str "expected mode " expected ", got " (pr-str mode)))))]

   [#"^the money is <?([A-Za-z0-9_]+)>?$"
    (fn [world captures resolve]
      (let [money (keyed/get-k (state! world) "money")
            expected (parse-num (resolve (first captures)))]
        (check! (= expected money)
                (str "expected money " expected ", got " money))))]

   [#"^the money decreased by <?([A-Za-z0-9_]+)>?$"
    (fn [world captures resolve]
      (let [before (keyed/get-k @(extras! world) :money-before-tap)
            now (keyed/get-k (state! world) "money")
            cost (parse-num (resolve (first captures)))]
        (check! (some? before) "no recorded money before the tap")
        (check! (= cost (- before now))
                (str "expected decrease " cost ", got " (- before now) " (before " before ", now " now ")"))))]

   [#"^the entity count on the board is <?([A-Za-z0-9_]+)>?$"
    (fn [world captures resolve]
      (let [count (keyed/get-k (entities! world "__all__") "count")
            expected (parse-num (resolve (first captures)))]
        (check! (= expected count)
                (str "expected entity count " expected ", got " count))))]

   [#"^the <?([A-Za-z0-9_]+)>? count on the board is <?([A-Za-z0-9_]+)>?$"
    (fn [world captures resolve]
      (let [prefab (resolve (first captures))
            count (keyed/get-k (entities! world prefab) "count")
            expected (parse-num (resolve (second captures)))]
        (check! (= expected count)
                (str "expected " prefab " count " expected ", got " count))))]

   [#"^the <?([A-Za-z0-9_]+)>? has power$"
    (fn [world captures resolve]
      (let [prefab (resolve (first captures))
            entities (keyed/get-k (entities! world prefab) "items")]
        (check! (boolean (some #(true? (keyed/get-k % :has_power)) entities))
                (str "expected a live " prefab " with power"))))]

   [#"^the (victory|gameover|pregame) banner is visible$"
    (fn [world captures _resolve]
      (let [name (first captures)
            node (keyed/get-k (call! world {:cmd "node" :path (str "sidebar/" name)}) "node")]
        (check! (and node (true? (keyed/get-k node "visible")))
                (str "expected sidebar/" name " banner visible"))))]])
