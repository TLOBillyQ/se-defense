(ns acceptance.keyed
  "Tolerant access to decode-shaped maps (string keys as produced by the JSON
  codec) from call sites that may hold keyword or string keys.")

(defn get-k
  "Reads a key tolerant of keyword and string keys (decode vs spec fixtures)."
  [m k]
  (if (map? m)
    (if (keyword? k)
      (get m k (get m (name k)))
      (get m k (get m (keyword k))))
    nil))
