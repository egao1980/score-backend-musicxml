(defpackage #:score-backend-musicxml/tests
  (:use #:cl #:rove))

(in-package #:score-backend-musicxml/tests)

(deftest skeleton-loads
  (ok (find-package '#:score-backend-musicxml)))
