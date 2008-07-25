;; @file       match.nu
;; @discussion Macros similar to destructuring-bind in Common Lisp.
;;
;; @copyright  Copyright (c) 2008 Issac Trotts
;;
;;   Licensed under the Apache License, Version 2.0 (the "License");
;;   you may not use this file except in compliance with the License.
;;   You may obtain a copy of the License at
;;
;;       http://www.apache.org/licenses/LICENSE-2.0
;;
;;   Unless required by applicable law or agreed to in writing, software
;;   distributed under the License is distributed on an "AS IS" BASIS,
;;   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
;;   See the License for the specific language governing permissions and
;;   limitations under the License.

;; Assigns variables in a template to values in a structure matching the template.
;; For example
;;
;;  (dbind ((a b) c) '((1 2) (3 4))
;;         (list a b c))
;;
;; returns
;;
;;   (1 2 (3 4))
;;
;; The implementation here is very loosely based
;; on the one on p. 232 of Paul Graham's book On Lisp.
;; The name is short for "destructuring bind."  Its semantics are similar to "let."
(macro dbind
     (set __pat (first margs))
     (set __seq (eval (second margs)))
     (set __body (cdr (cdr margs)))
     (set __bindings (destructure __pat __seq))
     (check-bindings __bindings)
     (set __result (cons 'let (cons __bindings __body)))
     (eval __result))

;; Assigns variables in a template to values in a structure matching the template.
;; For example
;;
;; (progn
;;  (dset ((a b) c) '((1 2) (3 4)))
;;  (list a b c))
;;
;; returns
;;
;;   (1 2 (3 4))
;;
;; The name is short for "destructuring set."  The semantics are similar to "set."
(macro dset
     (set __pat (first margs))
     (set __seq (eval (second margs)))
     (set __bindings (destructure __pat __seq))
     (check-bindings __bindings)
     (set __set-statements
          (__bindings map:(do (b)
                              (list 'set (first b) (second b)))))
     (eval (cons 'progn __set-statements)))

;; Given a pattern like '(a (b c)) and a sequence like '(1 (2 3)),
;; returns a list of bindings like '((a 1) (b 2) (c 3)).
(function destructure (pat seq)
     (cond
          ((and (not pat) seq)
           (throw* "NuMatchException"
                   "Attempt to match empty pattern to non-empty object"))
          ((not pat) nil)
          ((eq pat '_) '())  ; wildcard match produces no binding
          ((symbol? pat)
           (let (seq (if (or (pair? seq) (symbol? seq))
                         (then (list 'quote seq))
                         (else seq)))
                (list (list pat seq))))
          ;; Patterns like (head . tail)
          ((and (pair? pat)
                (pair? (cdr pat))
                (eq '. (second pat))
                (pair? (cdr (cdr pat)))
                (eq nil (cdr (cdr (cdr pat)))))
           (let ((bindings1 (destructure (first pat) (first seq)))
                 (bindings2 (destructure (third pat) (rest seq))))
                (append bindings1 bindings2)))
          ;; Symbolic literal patterns like 'Foo
          ((and (pair? pat)
                (eq 'quote (car pat))
                (pair? (cdr pat))
                (symbol? (second pat)))
           (if (eq (second pat) seq)
               (then '())  ; literal symbol match produces no bindings
               (else (throw* "NuMatchException"
                             "Failed match of literal symbol #{pat} to #{seq}"))))
          ((pair? pat)
           (let ((bindings1 (destructure (car pat) (car seq)))
                 (bindings2 (destructure (cdr pat) (cdr seq))))
                (append bindings1 bindings2)))
          ((eq pat seq) '())  ; literal match produces no bindings
          (else (throw* "NuMatchException"
                        "pattern is not nil, a symbol or a pair: #{pat}"))))

;; Makes sure that no key is set to two different values.
;; For example (check-bindings '((a 1) (a 1) (b 2))) just returns its argument,
;; but (check-bindings '((a 1) (a 2) (b 2))) throws a NuMatchException.
(function check-bindings (bindings)
     (set dic (dict))
     (bindings each:(do (b)
                        (set key (first b))
                        (set val (second b))
                        (set prev-val (dic key))  ; valueForKey inexplicably rejects symbols
                        (if (eq nil prev-val)
                            (then (dic setValue:val forKey:key))
                            (else
                                 (if (not (eq val prev-val))
                                     (then
                                          (throw* "NuMatchException"
                                                  "Inconsistent bindings #{prev-val} and #{val} for #{key}")))))))
     bindings)

;; Finds patterns matching an object's structure
(function _find-matches (obj patterns)
    (if (not patterns)
        (then '())
        (else 
          (set pb (car patterns))  ; pattern and body
          (set pat (first pb))
          (set body (rest pb))
          (if (eq pat 'else)
              (then body)
              (else
                  (try
                   (set bindings (destructure pat obj))
                   (check-bindings bindings)
                   (set expr (cons 'let (cons bindings body)))
                   (cons expr (_find-matches obj (cdr patterns)))
                   (catch (exception)
                       (_find-matches obj (cdr patterns)))))))))

;; Matches an object against some patterns with associated expressions.
;; TODO(ijt): boolean conditions for patterns (like "when" in ocaml)
(macro match
     (set __obj (eval (first margs)))
     (set __patterns (rest margs))
     (set __exprs (_find-matches __obj __patterns))
     (if (not __exprs)
        (then throw* "NuMatchException" "No match found"))
     (set __expr (car __exprs))
     (eval __expr))

