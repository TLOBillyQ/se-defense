(ns spec.acceptance.lua-bridge-spec
  (:require [speclj.core :refer :all]
            [acceptance.lua-bridge :as bridge]))

(defn- fake-proc-map
  "Process map shaped like babashka.process's: :in/:out streams plus :proc."
  [response-str]
  {:in (java.io.ByteArrayOutputStream.)
   :out (java.io.ByteArrayInputStream.
         (.getBytes (or response-str "") "UTF-8"))
   :proc :fake-proc})

(defn- spawn-bridge-with
  "Bridge with injected process factory and destroy recorder."
  [response-str]
  (let [destroyed (atom [])
        b (bridge/spawn-bridge!
           {:spawn (fn [argv opts]
                     (assoc (fake-proc-map response-str)
                            :argv argv :opts opts))
            :destroy (fn [proc] (swap! destroyed conj (:argv proc)))})
        proc (:proc b)]
    {:bridge b
     :destroyed destroyed
     :argv (:argv proc)
     :opts (:opts proc)
     :out-stream (:out proc)
     :in-stream (:in proc)}))

(describe "spawn-bridge!"
  (it "spawns the acceptance server with pipe streams"
    (let [{:keys [argv opts]} (spawn-bridge-with "{\"ok\":true}\n")]
      (should= ["tools/headless/acceptance_server.lua"] (rest argv))
      (should= {:in :pipe :out :pipe :err :inherit} opts)))

  (it "answers commands by writing a JSON line and reading the response"
    (let [{:keys [bridge in-stream]} (spawn-bridge-with "{\"ok\":true}\n")]
      (let [resp ((:send! bridge) {:cmd "state"})]
        (should= {"ok" true} resp)
        (should= "{\"cmd\":\"state\"}\n"
                 (.toString in-stream "UTF-8")))))

  (it "parses response bodies with string keys"
    (let [{:keys [bridge]} (spawn-bridge-with "{\"ok\":true,\"state\":{\"money\":100}}\n")]
      (should= {"ok" true "state" {"money" 100}} ((:send! bridge) {:cmd "state"}))))

  (it "classifies a closed server as an infrastructure error"
    (let [{:keys [bridge]} (spawn-bridge-with "")]
      (let [e (try ((:send! bridge) {:cmd "state"}) (catch clojure.lang.ExceptionInfo e e))]
        (should= :infra (:kind (ex-data e)))
        (should= true (boolean (re-find #"acceptance server closed" (ex-message e)))))))

  (it "classifies a non-ok response as a server error"
    (let [{:keys [bridge]} (spawn-bridge-with "{\"ok\":false,\"error\":\"boom\"}\n")]
      (let [e (try ((:send! bridge) {:cmd "state"}) (catch clojure.lang.ExceptionInfo e e))]
        (should= :infra (:kind (ex-data e)))
        (should= true (boolean (re-find #"server error: boom" (ex-message e)))))))

  (it "destroys the process and raises on timeout"
    (let [os (java.io.PipedOutputStream.)
          destroyed (atom 0)
          b (bridge/spawn-bridge!
             {:timeout-ms 100
              :spawn (fn [_ _] {:in (java.io.ByteArrayOutputStream.)
                                :out (java.io.PipedInputStream. os)
                                :proc :fake})
              :destroy (fn [_] (swap! destroyed inc))})]
      (try
        (let [e (try ((:send! b) {:cmd "state"}) (catch clojure.lang.ExceptionInfo e e))]
          (should= :infra (:kind (ex-data e)))
          (should= true (boolean (re-find #"bridge timeout after 100ms" (ex-message e))))
          (should= 1 @destroyed))
        (finally
          ;; unblock the reader thread the bridge left waiting on the pipe
          (.close os)))))

  (it "closes the input and destroys the process on close!"
    (let [{:keys [bridge destroyed]} (spawn-bridge-with "{\"ok\":true}\n")]
      ((:close! bridge))
      (should= 1 (count @destroyed))
      ;; a second close! destroys again, as before the refactor
      ((:close! bridge))
      (should= 2 (count @destroyed)))))
