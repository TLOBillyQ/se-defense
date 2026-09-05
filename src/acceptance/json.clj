(ns acceptance.json
  "Minimal JSON reader/writer for the acceptance pipeline. Dependency-free so
  the same code runs under Babashka and JVM Clojure. Decodes objects to maps
  with string keys; encodes keywords as their names."
  (:require [clojure.string :as str]))

(defn- read-string* [s i]
  (loop [i (inc i) acc (StringBuilder.)]
    (if (>= i (count s))
      (throw (ex-info "unterminated string" {:json-at i}))
      (let [c (.charAt s i)]
        (cond
          (= c \") [(str acc) (inc i)]
          (= c \\) (let [esc (.charAt s (inc i))]
                     (case esc
                       \" (recur (+ i 2) (.append acc \"))
                       \\ (recur (+ i 2) (.append acc \\))
                       \/ (recur (+ i 2) (.append acc \/))
                       \b (recur (+ i 2) (.append acc \backspace))
                       \f (recur (+ i 2) (.append acc \formfeed))
                       \n (recur (+ i 2) (.append acc \newline))
                       \r (recur (+ i 2) (.append acc \return))
                       \t (recur (+ i 2) (.append acc \tab))
                       \u (let [hex (subs s (+ i 2) (+ i 6))
                                code (Integer/parseInt hex 16)]
                            (recur (+ i 6) (.append acc (char code))))
                       (throw (ex-info (str "bad escape \\" esc) {:json-at i}))))
          :else (recur (inc i) (.append acc c)))))))

(defn- skip-ws [s i]
  (loop [i i]
    (if (and (< i (count s)) (Character/isWhitespace (.charAt s i)))
      (recur (inc i))
      i)))

(declare read-value)

(defn- read-number [s i]
  (let [m (re-find #"-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?" (subs s i))]
    (when-not m (throw (ex-info "bad number" {:json-at i})))
    (let [txt m
          v (if (or (str/includes? txt ".") (str/includes? txt "e") (str/includes? txt "E"))
              (Double/parseDouble txt)
              (Long/parseLong txt))]
      [v (+ i (count txt))])))

(defn- read-array [s i]
  (loop [i (skip-ws s (inc i)) acc []]
    (let [c (.charAt s i)]
      (cond
        (= c \]) [acc (inc i)]
        (= c \,) (recur (skip-ws s (inc i)) acc)
        :else (let [[v j] (read-value s i)]
                (recur (skip-ws s j) (conj acc v)))))))

(defn- read-object [s i]
  (loop [i (skip-ws s (inc i)) m {}]
    (let [c (.charAt s i)]
      (if (= c \})
        [m (inc i)]
        (let [[k j] (read-string* s i)
              j2 (skip-ws s j)
              _ (when-not (= \: (.charAt s j2))
                  (throw (ex-info "expected : after object key" {:json-at j2})))
              [v j3] (read-value s (skip-ws s (inc j2)))
              j4 (skip-ws s j3)
              c2 (.charAt s j4)]
          (case c2
            \, (recur (skip-ws s (inc j4)) (assoc m k v))
            \} [(assoc m k v) (inc j4)]
            (throw (ex-info "bad object separator" {:json-at j4}))))))))

(defn- read-value [s i]
  (let [i (skip-ws s i)
        c (.charAt s i)]
    (case c
      \" (read-string* s i)
      \[ (read-array s i)
      \{ (read-object s i)
      \t (if (= "true" (subs s i (+ i 4))) [true (+ i 4)] (throw (ex-info "bad token" {:json-at i})))
      \f (if (= "false" (subs s i (+ i 5))) [false (+ i 5)] (throw (ex-info "bad token" {:json-at i})))
      \n (if (= "null" (subs s i (+ i 4))) [nil (+ i 4)] (throw (ex-info "bad token" {:json-at i})))
      (read-number s i))))

(defn read-json
  "Parses a JSON document. Returns maps with string keys and vectors for arrays."
  [s]
  (let [s (str s)
        [v j] (read-value s 0)
        j2 (skip-ws s j)]
    (when-not (= j2 (count s))
      (throw (ex-info "trailing data after JSON document" {})))
    v))

(defn- write-number [v]
  (cond
    (instance? Long v) (str v)
    (instance? Integer v) (str v)
    (instance? Double v) (let [d (double v)
                               r (Math/round d)]
                           (if (and (== d r) (<= (Math/abs d) 1e15)) (str r) (str d)))
    (instance? Float v) (write-number (double v))
    :else (str v)))

(defn- write-string [v]
  (str \" (-> (str v)
              (str/replace "\\" "\\\\")
              (str/replace "\"" "\\\"")
              (str/replace "\n" "\\n")
              (str/replace "\r" "\\r")
              (str/replace "\t" "\\t")) \"))

(defn write-json
  "Serializes a value to JSON. Map keys are emitted as strings (keywords by
  name); map order follows the map's iteration order."
  [v]
  (letfn [(emit [v]
            (cond
              (nil? v) "null"
              (string? v) (write-string v)
              (keyword? v) (write-string (name v))
              (symbol? v) (write-string (str v))
              (instance? Boolean v) (str v)
              (number? v) (write-number v)
              (vector? v) (str "[" (str/join "," (map emit v)) "]")
              (sequential? v) (str "[" (str/join "," (map emit v)) "]")
              (map? v) (str "{"
                            (str/join ","
                                      (map (fn [[k x]]
                                             (str (write-string (if (keyword? k) (name k) (str k)))
                                                  ":" (emit x)))
                                           v))
                            "}")
              :else (write-string (str v))))]
    (emit v)))

;; clj-mutate-manifest-begin
;; {:version 2, :hash-algorithm :sha256-source-v1, :verified? true, :tested-at "2026-09-05T11:09:02.856307+08:00", :module-hash "87658136683671f56776cd0ceff6bd45e75435116abf2ca99087f6661ac9b5b4", :provenance {:mutation-rules-version "3", :test-command "speclj -f documentation spec", :test-roots ["spec"], :test-profile-fingerprint "41f17b24aa38e88cefaa35ae3a902ecb76222ad0f99aa027bcda6b7f2fda1dc8"}, :forms [{:id "form/0/ns", :kind "ns", :line 1, :end-line 5, :hash "4ed8c1ae6cdf3024179751ee3c1c892421bafb1d45aff23ef6e83855b0ea4d62"} {:id "defn-/read-string*", :kind "defn-", :line 7, :end-line 28, :hash "6cab4d0b2329fa813b0b95adce6b56596eda3d694661f3c39ac076ed2abd6dea"} {:id "defn-/skip-ws", :kind "defn-", :line 30, :end-line 34, :hash "e6d5c86d5261bc72c108e73da60fa7f927fd1357186c855d413496c3df4870ad"} {:id "form/3/declare", :kind "declare", :line 36, :end-line 36, :hash "01e96fd1b35c4bc932b9c7598227c4c1a0858ca296197a35ed275760fd19923a"} {:id "defn-/read-number", :kind "defn-", :line 38, :end-line 45, :hash "9b71ae9a5ff39dca899ae2c7379e7535ab092d918ab74cf2e69b3a4fd71bb54c"} {:id "defn-/read-array", :kind "defn-", :line 47, :end-line 54, :hash "c762c2c9d0fcf2d411d49002783d0596ea7e9a2915ecd0539a64a370461d56d5"} {:id "defn-/read-object", :kind "defn-", :line 56, :end-line 71, :hash "4979f56ce9ee06d22044f47999d2ee4cf8f74b025feec67f8bfd2464ce586e18"} {:id "defn-/read-value", :kind "defn-", :line 73, :end-line 83, :hash "d31ff9c7709e66e907bd45071f375701a50415ba3c3991aef75f95cade18a05c"} {:id "defn/read-json", :kind "defn", :line 85, :end-line 93, :hash "bb27f221d0785cd052dee9d8b0312a3d40e6c02ad0cc7dcd06188bd4ecb7074f"} {:id "defn-/write-number", :kind "defn-", :line 95, :end-line 103, :hash "98db7871bec7a6d87563027762436603bd947b764c1da5f2157d4ac5bec573e0"} {:id "defn-/write-string", :kind "defn-", :line 105, :end-line 111, :hash "54cab99416f02913168f67d6e3cb413cb1a6a3fabad1b61b79ab2d38bf122d36"} {:id "defn/write-json", :kind "defn", :line 113, :end-line 135, :hash "18b71b6210f48a962f437b2b2657384c2acaa0e0cc640fbd0491c00ef6e6fda4"}]}
;; clj-mutate-manifest-end
