(ns acceptance.handlers
  "Project step handlers connecting Gherkin step text to the headless Lua game
  through the acceptance server bridge. Regex captures are the default style;
  each capture resolves to the current example value when the example has a
  matching column name, otherwise to the capture text itself.")

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
  (get (call! world {:cmd "state"}) "state"))

(defn- entities!
  [world prefab]
  (get (call! world {:cmd "entities" :prefab prefab}) "entities"))

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
        (swap! (extras! world) assoc :money-before-tap (get state "money")))
      (send-input! world {:kind "input" :itype "tap"
                          :x (parse-num (resolve (first captures)))
                          :z (parse-num (resolve (second captures)))}))]

   [#"^no building is being placed$"
    (fn [world _captures _resolve]
      (check! (nil? (get (state! world) "placing")) "expected no placing selection"))]

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
      (let [mode (get (state! world) "mode")
            expected (resolve (first captures))]
        (check! (= expected mode)
                (str "expected mode " expected ", got " (pr-str mode)))))]

   [#"^the money is <?([A-Za-z0-9_]+)>?$"
    (fn [world captures resolve]
      (let [money (get (state! world) "money")
            expected (parse-num (resolve (first captures)))]
        (check! (= expected money)
                (str "expected money " expected ", got " money))))]

   [#"^the money decreased by <?([A-Za-z0-9_]+)>?$"
    (fn [world captures resolve]
      (let [before (get @(extras! world) :money-before-tap)
            now (get (state! world) "money")
            cost (parse-num (resolve (first captures)))]
        (check! (some? before) "no recorded money before the tap")
        (check! (= cost (- before now))
                (str "expected decrease " cost ", got " (- before now) " (before " before ", now " now ")"))))]

   [#"^the entity count on the board is <?([A-Za-z0-9_]+)>?$"
    (fn [world captures resolve]
      (let [count (get (entities! world "__all__") "count")
            expected (parse-num (resolve (first captures)))]
        (check! (= expected count)
                (str "expected entity count " expected ", got " count))))]

   [#"^the <?([A-Za-z0-9_]+)>? count on the board is <?([A-Za-z0-9_]+)>?$"
    (fn [world captures resolve]
      (let [prefab (resolve (first captures))
            count (get (entities! world prefab) "count")
            expected (parse-num (resolve (second captures)))]
        (check! (= expected count)
                (str "expected " prefab " count " expected ", got " count))))]

   [#"^the <?([A-Za-z0-9_]+)>? has power$"
    (fn [world captures resolve]
      (let [prefab (resolve (first captures))
            entities (get (entities! world prefab) "items")]
        (check! (boolean (some #(true? (get % "has_power")) entities))
                (str "expected a live " prefab " with power"))))]

   [#"^the (victory|gameover|pregame) banner is visible$"
    (fn [world captures _resolve]
      (let [name (first captures)
            node (get (call! world {:cmd "node" :path (str "sidebar/" name)}) "node")]
        (check! (and node (true? (get node "visible")))
                (str "expected sidebar/" name " banner visible"))))]])

;; clj-mutate-manifest-begin
;; {:version 2, :hash-algorithm :sha256-source-v1, :verified? true, :tested-at "2026-09-05T11:14:40.201847+08:00", :module-hash "8eb20c62be6fcbe8ff99aa36a9636a551100802811593c43a60f951cd6eb9733", :provenance {:mutation-rules-version "3", :test-command "speclj -f documentation spec", :test-roots ["spec"], :test-profile-fingerprint "41f17b24aa38e88cefaa35ae3a902ecb76222ad0f99aa027bcda6b7f2fda1dc8"}, :forms [{:id "form/0/ns", :kind "ns", :line 1, :end-line 5, :hash "963bd5ab70e37a4eebcb720beb22339c8ce7a15133e2e2fc25377dde5ac3bf2b"} {:id "defn-/check!", :kind "defn-", :line 7, :end-line 10, :hash "4bda5c4e6b0fd00863763f8bd24061d0208d2d4f93e14d3ea89e61f95da1e962"} {:id "defn-/parse-num", :kind "defn-", :line 12, :end-line 15, :hash "3703ccc2cd9a8e3747eac2d974e6de7ab78d4f1779bf1033a2bcb68d1f058160"} {:id "defn-/call!", :kind "defn-", :line 17, :end-line 22, :hash "047f2eb3b690311c5a907d6cd6d4cd9c3c2ddb6e77ed05d829a02aabde97dc75"} {:id "defn-/state!", :kind "defn-", :line 24, :end-line 26, :hash "f5c1252fa431364a16e8095cf2f244ec1aedf98d015c75ae823da3cf439cd813"} {:id "defn-/entities!", :kind "defn-", :line 28, :end-line 30, :hash "7e455915ba0723cfba98167a3d471198bfe0abdfd82ca3261ca8c1f2b9d76517"} {:id "defn-/send-input!", :kind "defn-", :line 32, :end-line 34, :hash "c28fa9db4c47a0940a85a29cc44b43d034e883ddc1c0c29bd84ac74543953b1e"} {:id "defn-/gm!", :kind "defn-", :line 36, :end-line 38, :hash "5e8bd43783acd747d803104455b073db4627f8665cfb3e132cccdf3e44c21924"} {:id "defn-/extras!", :kind "defn-", :line 40, :end-line 42, :hash "66571f9c73c96783c978b2f50d07e0136fb88348003b344ce3a804c2ac17a032"} {:id "def/registry", :kind "def", :line 44, :end-line 140, :hash "bf33f3772c891d4c34234cc7a4d150a60d106b4716ec32e8607ac792fa3345ed"}]}
;; clj-mutate-manifest-end
