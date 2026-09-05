(ns spec.acceptance.keyed-spec
  (:require [speclj.core :refer :all]
            [acceptance.keyed :as keyed]))

(describe "get-k"
  (it "reads a keyword key from a string-keyed map"
    (should= "a" (keyed/get-k {"money" "a"} :money))
    (should= "a" (keyed/get-k {"money" "a"} "money")))

  (it "reads a string key from a keyword-keyed map"
    (should= 1 (keyed/get-k {:money 1} "money"))
    (should= 1 (keyed/get-k {:money 1} :money)))

  (it "returns nil for missing keys and non-maps"
    (should= nil (keyed/get-k {"money" 1} :mode))
    (should= nil (keyed/get-k {:money 1} "mode"))
    (should= nil (keyed/get-k nil :money))
    (should= nil (keyed/get-k "not a map" :money))))
