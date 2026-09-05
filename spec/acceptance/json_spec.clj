(ns spec.acceptance.json-spec
  (:require [speclj.core :refer :all]
            [acceptance.json :as json]))

(describe "read-json"
  (it "parses objects, arrays, strings, numbers, booleans and nulls"
    (should= {"a" 1 "b" [true false nil "x"]} (json/read-json "{\"a\":1,\"b\":[true,false,null,\"x\"]}"))
    (should= 42 (json/read-json "42"))
    (should= -3 (json/read-json " -3 "))
    (should= 3.5 (json/read-json "3.5"))
    (should= 1e3 (json/read-json "1e3"))
    (should= true (json/read-json "true"))
    (should= nil (json/read-json "null")))

  (it "tolerates trailing separator before a closing bracket"
    (should= {"a" 1} (json/read-json "{\"a\":1,}"))
    (should= [1 2] (json/read-json "[1,2,]")))

  (it "parses string escapes"
    (should= "a\"b" (json/read-json "\"a\\\"b\""))
    (should= "a\\b" (json/read-json "\"a\\\\b\""))
    (should= "a/b" (json/read-json "\"a\\/b\""))
    (should= "a\nb" (json/read-json "\"a\\nb\""))
    (should= "a\rb" (json/read-json "\"a\\rb\""))
    (should= "a\tb" (json/read-json "\"a\\tb\""))
    (should= "a\bb" (json/read-json "\"a\\bb\""))
    (should= "a\fb" (json/read-json "\"a\\fb\""))
    (should= "a\u0001b" (json/read-json "\"a\\u0001b\"")))

  (it "rejects malformed documents"
    (should-throw clojure.lang.ExceptionInfo (json/read-json "{\"a\":}"))
    (should-throw clojure.lang.ExceptionInfo (json/read-json "{\"a\" 1}"))
    (should-throw clojure.lang.ExceptionInfo (json/read-json "\"unterminated"))
    (should-throw clojure.lang.ExceptionInfo (json/read-json "\"bad \\q escape\""))
    (should-throw IndexOutOfBoundsException (json/read-json "tru"))
    (should-throw clojure.lang.ExceptionInfo (json/read-json "01"))
    (should-throw clojure.lang.ExceptionInfo (json/read-json "{\"a\":1} trailing"))))

(describe "write-json"
  (it "encodes scalars"
    (should= "null" (json/write-json nil))
    (should= "true" (json/write-json true))
    (should= "\"hi\"" (json/write-json "hi"))
    (should= "5" (json/write-json 5))
    (should= "5" (json/write-json 5.0))
    (should= "5.5" (json/write-json 5.5)))

  (it "encodes keywords and symbols as their names"
    (should= "\"ready\"" (json/write-json :ready))
    (should= "\"ready\"" (json/write-json 'ready)))

  (it "escapes strings"
    (should= "\"a\\\"b\"" (json/write-json "a\"b"))
    (should= "\"a\\\\b\"" (json/write-json "a\\b"))
    (should= "\"a\\nb\"" (json/write-json "a\nb"))
    (should= "\"a\\rb\"" (json/write-json "a\rb"))
    (should= "\"a\\tb\"" (json/write-json "a\tb")))

  (it "encodes collections and nested structures"
    (should= "[1,\"a\",true]" (json/write-json [1 "a" true]))
    (should= "{\"a\":1}" (json/write-json (array-map :a 1)))
    (should= "{\"x\":{\"y\":[false]}}" (json/write-json {:x {:y [false]}}))
    (should= "[\"a\",\"b\"]" (json/write-json (list "a" "b")))))

(describe "number formatting"
  (it "writes longs and integers as decimal digits"
    (should= "5" (json/write-json 5))
    (should= "-5" (json/write-json -5))
    (should= "5" (json/write-json (int 5))))

  (it "writes integral doubles as rounded digits within range"
    (should= "5" (json/write-json 5.0))
    (should= "-5" (json/write-json -5.0))
    (should= "0" (json/write-json -0.0))
    (should= "1000000000000000" (json/write-json 1e15)))

  (it "writes fractional and out-of-range doubles as doubles"
    (should= "5.5" (json/write-json 5.5))
    (should= "1.0E16" (json/write-json 1e16))
    (should= "0.1" (json/write-json 0.1)))

  (it "delegates floats to double formatting"
    (should= "5.5" (json/write-json (float 5.5))))

  (it "stringifies other number types"
    (should= "5.5" (json/write-json 5.5M))
    (should= "3/2" (json/write-json 3/2))))

(describe "round trips"
  (it "read-json of write-json restores the value"
    (should= {"name" "Base Defence" "values" [1 2.5 true nil "a\"b"]}
             (json/read-json (json/write-json {"name" "Base Defence"
                                               "values" [1 2.5 true nil "a\"b"]})))
    (should= "" (json/read-json (json/write-json "")))))
