(ns spec-property.acceptance.property-spec
  "Property tests for the acceptance pipeline, run separately from normal
  verification via tools/acceptance/run_property.sh."
  (:require [speclj.core :refer :all]
            [acceptance.adapter :as a]
            [acceptance.generator :as gen]
            [acceptance.json :as json]
            [acceptance.runtime :as rt]
            [clojure.string :as str]
            [clojure.test.check :as tc]
            [clojure.test.check.generators :as tg]
            [clojure.test.check.properties :as prop]))

(defn- holds?
  [n property]
  (:pass? (tc/quick-check n property)))

(defn- expand-preserved?
  [ir]
  (let [{:keys [background scenarios]} ir
        execs (rt/expand-executions ir)
        expected-count (reduce + (map (fn [s]
                                        (max 1 (count (:examples s))))
                                      scenarios))
        bg (vec (or background []))]
    (and
     (= expected-count (count execs))
     (every? (fn [e]
               (let [s (first (filter #(= (:name %)
                                           (:scenario-name e))
                                      scenarios))
                     rows (if (seq (:examples s))
                            (vec (:examples s))
                            [{}])
                     i (dec (Long/parseLong
                             (second
                              (re-find #"/example_(\d+)$"
                                       (:name e)))))]
                 (and s
                      (< -1 i (count rows))
                      (= (:steps e) (into bg (:steps s)))
                      (= (:example e) (nth rows i)))))
             execs))))

(defn- in-long-range
  "Whole-number doubles canonicalize to digits; round trips then compare
  numerically. Doubles are mapped into long range so values pass through
  read-number unchanged."
  [d]
  (if (or (Double/isNaN d) (Double/isInfinite d)) 0.0 (mod d 1000000.0)))

(defn- num-eq?
  [a b]
  (if (and (number? a) (number? b)) (== a b) (= a b)))

(defn- deep-num-eq?
  [a b]
  (cond
    (and (map? a) (map? b)) (and (= (set (keys a)) (set (keys b)))
                                 (every? (fn [k] (deep-num-eq? (get a k) (get b k)))
                                         (keys a)))
    (and (vector? a) (vector? b)) (and (= (count a) (count b))
                                       (every? true? (map deep-num-eq? a b)))
    :else (num-eq? a b)))

(defn- json-leaf []
  (tg/one-of [tg/boolean
              (tg/elements [nil])
              (tg/fmap (fn [n] (- (mod n 1000000) 500000)) tg/large-integer)
              (tg/fmap in-long-range tg/double)
              tg/string]))

(defn- build-json [depth]
  (if (zero? depth)
    (json-leaf)
    (tg/one-of [(json-leaf)
                (build-json (dec depth))
                (tg/vector (build-json (dec depth)))
                (tg/map (tg/elements ["a" "b" "k" "price"]) (build-json (dec depth)))])))

(defn- json-value []
  (tg/sized (fn [size] (build-json (mod size 3)))))

(describe "json codec round trip"
  (it "write-json followed by read-json restores every JSON value numerically"
    (should= true
             (holds? 200
                     (prop/for-all [v (json-value)]
                       (deep-num-eq? v (json/read-json (json/write-json v))))))))

(describe "slugify"
  (it "is idempotent and never produces leading/trailing hyphens"
    (let [ascii-string (tg/fmap (fn [n]
                                  (apply str
                                         (repeatedly n #(char (+ 32 (rand-int 95))))))
                                (tg/choose 0 40))]
      (should= true
               (holds? 200
                       (prop/for-all [s ascii-string]
                         (let [a (gen/slugify s)]
                           (and (= a (gen/slugify a))
                                (or (str/blank? a)
                                    (boolean (re-find #"^[a-z0-9-]+$" a)))
                                (not (re-find #"^-|-$" a)))))))))

  (it "is invariant under case folding"
    (let [ascii-string (tg/fmap (fn [n]
                                  (apply str
                                         (repeatedly n #(char (+ 32 (rand-int 95))))))
                                (tg/choose 0 40))]
      (should= true
               (holds? 200
                       (prop/for-all [s ascii-string]
                         (= (gen/slugify s) (gen/slugify (str/lower-case s)))))))))

(describe "expand-executions"
  (it "preserves scenario count, row order, and step composition"
    (let [step-gen (tg/fmap (fn [[k t]] {:keyword k :text t :parameters ["v"]})
                            (tg/tuple (tg/elements ["Given" "When" "Then"]) tg/string))
          scenario-gen (tg/fmap (fn [[idx name steps nrows]]
                                  {:name (str name "__" idx)
                                   :steps steps
                                   :examples (vec (for [i (range nrows)]
                                                    {"v" (str idx i)}))})
                                 (tg/tuple tg/nat tg/string (tg/vector step-gen) (tg/choose 0 3)))
          ir-gen (tg/fmap (fn [[name bg scs]]
                             {:name name :background bg :scenarios scs})
                            (tg/tuple tg/string (tg/vector step-gen) (tg/vector scenario-gen)))]
      (should= true
               (holds? 200
                       (prop/for-all [ir ir-gen]
                         (expand-preserved? ir)))))))

(describe "parse-timeout"
  (it "scales seconds and milliseconds, defaulting to 30s"
    (should= true
             (holds? 200
                     (prop/for-all [n (tg/choose 0 3600)]
                       (and (= (* n 1000) (a/parse-timeout (str n "s")))
                            (= n (a/parse-timeout (str n "ms"))))))))
    (it "defaults on nil and non-duration text"
      (should= 30000 (a/parse-timeout nil))
      (should= 30000 (a/parse-timeout "bogus"))))
