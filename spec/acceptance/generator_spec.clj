(ns spec.acceptance.generator-spec
  (:require [speclj.core :refer :all]
            [acceptance.generator :as gen]
            [acceptance.json :as json]))

(defn- temp-ir-dir []
  (let [d (java.io.File. (str (System/getProperty "java.io.tmpdir")
                              "acceptance-gen-" (java.util.UUID/randomUUID)))]
    (.mkdirs (java.io.File. (str d "/ir")))
    (str d)))

(def fixture-ir
  (str "{\"name\":\"Base Defence flow\",\"background\":[],\"scenarios\":["
       "{\"name\":\"pregame\",\"steps\":[{\"keyword\":\"Given\",\"text\":\"a boot\"}],\"examples\":[]},"
       "{\"name\":\"placing\",\"steps\":[{\"keyword\":\"When\",\"text\":\"place <building>\"}],\"examples\":[{\"building\":\"turret\"},{\"building\":\"relay\"}]}]}"))

(describe "slugify"
  (it "maps feature paths to lowercase hyphen metadata names"
    (should= "features-hunt-the-wumpus-feature"
             (gen/slugify "features/Hunt The Wumpus.feature"))
    (should= "features-orders-cancel-order-feature"
             (gen/slugify "features/orders/Cancel Order.feature"))
    (should= "features-api-v2-happy-path-feature"
             (gen/slugify "Features/API v2/Happy Path.feature"))))

(describe "run"
  (it "writes an executable test entry point and metadata for a valid IR"
    (let [dir (temp-ir-dir)
          ir-path (str dir "/ir/base-defence.json")
          out-dir (str dir "/generated")
          _ (spit ir-path fixture-ir)
          result (gen/run [ir-path out-dir])]
      (should= 0 (:exit result))
      (let [test-file (str out-dir "/features-base-defence-feature_acceptance_test.clj")
            meta-file (str out-dir "/metadata/features-base-defence-feature.json")]
        (should= true (.exists (java.io.File. test-file)))
        (should= true (.canExecute (java.io.File. test-file)))
        (should= true (.exists (java.io.File. meta-file)))
        (let [meta (json/read-json (slurp meta-file))]
          (should= 1 (get meta "schema_version"))
          (should= "features/base-defence.feature" (get meta "feature_path"))
          (should= ir-path (get meta "ir_path"))
          (should= "generated_files" (get meta "hash_scope"))
          (should= true (boolean (re-find #"^sha256:[0-9a-f]{64}$" (get meta "implementation_hash"))))
          (should= ["features-base-defence-feature_acceptance_test.clj"]
                   (get meta "generated_files")))
        (let [src (slurp test-file)]
          (should= true (boolean (re-find #"^#!/usr/bin/env bb" src)))
          (should= true (clojure.string/includes? src "Base Defence flow"))
          (should= true (clojure.string/includes? src "acceptance.runtime"))
          (should= true (clojure.string/includes? src "acceptance.handlers"))
          (should= true (clojure.string/includes? src ir-path)))))
    ))
  (it "generates deterministic output for a fixed IR"
    (let [dir (temp-ir-dir)
          ir-path (str dir "/ir/base-defence.json")
          out1 (str dir "/generated-1")
          out2 (str dir "/generated-2")
          _ (spit ir-path fixture-ir)]
      (gen/run [ir-path out1])
      (gen/run [ir-path out2])
      (should= (slurp (str out1 "/features-base-defence-feature_acceptance_test.clj"))
               (slurp (str out2 "/features-base-defence-feature_acceptance_test.clj")))
      (should= (slurp (str out1 "/metadata/features-base-defence-feature.json"))
               (slurp (str out2 "/metadata/features-base-defence-feature.json")))))
  (it "exits with usage error 2 on wrong argument count"
    (should= 2 (:exit (gen/run [])))
    (should= 2 (:exit (gen/run ["only-one"])))
    (should= 2 (:exit (gen/run ["a" "b" "c"]))))
  (it "exits with error 1 when the IR file cannot be read"
    (let [dir (temp-ir-dir)]
      (should= 1 (:exit (gen/run [(str dir "/ir/missing.json") (str dir "/generated")])))))
