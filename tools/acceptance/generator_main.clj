(require '[acceptance.generator :as generator])

(System/exit (:exit (generator/run (vec *command-line-args*))))
