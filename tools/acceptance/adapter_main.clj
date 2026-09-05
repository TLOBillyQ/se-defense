(require '[acceptance.adapter :as adapter])

(adapter/handle-jobs *in* *out* {:exec adapter/default-exec})
