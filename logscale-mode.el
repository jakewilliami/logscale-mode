;;; logscale-mode.el --- Major Mode for editing LogScale Query Language source code -*- lexical-binding: t -*-

;; Copyright (C) 2024 Jake Ireland

;; Author: Jake Ireland <jakewilliami@icloud.com>
;; URL: https://github.com/jakewilliami/logscale-mode/
;; Version: 0.1
;; Keywords: languages logscale mode crowdstrike falcon humio query cql kql
;; Package-Requires: ((emacs "27.1")) TODO: require 29.1 because tree-sitter is now part of it

;;; Usage:
;;
;; Put the following code in your .emacs, site-load.el, or other relevant file
;; (add-to-list 'load-path "path-to-logscale-mode")
;; (require 'logscale-mode)

;;; Licence:
;;
;; This file is not part of GNU Emacs.
;;
;; Permission is hereby granted, free of charge, to any person
;; obtaining a copy of this software and associated documentation
;; files (the "Software"), to deal in the Software without
;; restriction, including without limitation the rights to use, copy,
;; modify, merge, publish, distribute, sublicense, and/or sell copies
;; of the Software, and to permit persons to whom the Software is
;; furnished to do so, subject to the following conditions:
;;
;; The above copyright notice and this permission notice shall be
;; included in all copies or substantial portions of the Software.
;;
;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
;; EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
;; MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
;; NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
;; BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
;; ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
;; CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
;; SOFTWARE.

;;; Commentary:
;;
;; Major Mode for editing LogScale Query Language source code.
;;
;; This package provides syntax highlighting and indentation support for
;; SPL source code.
;;
;; Syntax resources:
;;   - https://github.com/splunk/vscode-extension-splunk/
;; 
;; The following resources are from
;; https://docs.splunk.com/Documentation/Splunk/9.1.1/: (or latest)
;;   - SPL: Search/Aboutthesearchlanguage
;;   - SPL Syntax: SearchReference/UnderstandingSPLsyntax
;;
;; Specific resources are referenced where relevant within the code.

;;; Notes:
;;
;; TODO:
;;   - only highlight transforming and eval functions after parentheses added
;;   - I need to go through and actually test things at some point, but I should probably prioritise releasing this and doing small touch-ups later
;;   - Electric indent mode (see below)
;;
;; NOTE: Feature possibilities:
;;   - Operator highlighting
;;   - Comparison or assignment highlighting
;;   - Different brackets colours when nested
;;   - Make keyword highlighting more similar to official Splunk
;;     highlighting (i.e., most things are function highlights.)
;;   - Linting
;;   - Autocomplete

;; NOTE: features required (https://library.humio.com/data-analysis/syntax.html, https://library.humio.com/data-analysis/functions.html):
;;   - filter (light blue)
;;   - function (dark blue, includes : in function name, and apparently =>)
;;   - operator (grey, includes pipe, >, :=, etc., but not ;)
;;   - variables (orange, inclluding strings and numbers)
;;   - regex (pink)
;;   - new fields
;;   - conditions
;;   - joins
;;   - array
;;   - rel time
;;   - grammar subset
;;   - comments (C style)
;;   - macros?  preprocessors?  symbols?  escape characters?
;;   - field names when used in a function is one colour (orange) but another in a filter (light blue)

;;; Code



;;; Main

;;; Code:

(eval-when-compile
  (require 'rx)
  (require 'regexp-opt)
  (require 'treesit))

(defvar logscale-mode-hook nil)

(defgroup logscale ()
  "Major mode for LogScale Query Language code."
  :link '(url-link "https://docs.splunk.com/")
  :version "0.1"
  :group 'languages
  :prefix "logscale-")



;;; Faces
;;
;; Custom font faces for LogScale syntax.
;;
;; After some trial and error, and taking inspiration from different places, here are
;; some possible colour schemes:*
;;
;;  ----------------------------------------------------------------------------
;; | font-lock-*-face  | Apt              | Falcon           | VS Code          |
;; |-------------------|------------------|------------------|------------------|
;; | warning           | —                | —                | —                |
;; | function-name     | Trans/Eval/Macro | Builtin          | Constants        |
;; | [n] function-call | —                | —                | —                |
;; | variable-name     | Keyword          | —                | Keyword          |
;; | [n] variable-use  | —                | —                | —                |
;; | keyword           | —                | Trans/Eval/Macro | —                |
;; | type              | —                | Constants        | Trans/Eval/Macro |
;; | constant          | Constants        | Keyword          | Builtin          |
;; | builtin           | Builtin          | —                | —                |
;; | preprocessor      | —                | —                | —                |
;; | [n] property-name | —                | —                | —                |
;; | [n] number        | —                | —                | —                |
;; | [n] escape        | —                | —                | —                |
;;  ----------------------------------------------------------------------------
;;
;; Note: font-lock faces prefixed with [n] have been considered too new to use here,
;; as they do not yet have enough widespread support.
;;
;; Ref:
;;   - https://www.gnu.org/software/emacs/manual/html_node/elisp/Faces-for-Font-Lock.html

(defface logscale-comment-face
  '((t :inherit font-lock-comment-face))
  "Face for alternative comment syntax in LogScale."
  :group 'logscale)

(defface logscale-builtin-functions-face
  '((t :inherit font-lock-builtin-face))
  ;; '((t :inherit font-lock-function-name-face))
  ;; '((t :inherit font-lock-constant-face))
  "Face for builtin functions such as `rename', `table', and `stat' in LogScale."
  :group 'logscale)

(defface logscale-eval-functions-face
  '((t :inherit font-lock-function-name-face))
  ;; '((t :inherit font-lock-keyword-face))
  ;; '((t :inherit font-lock-type-face))
  "Face for eval functions such as `abs' and `mvindex' in LogScale."
  :group 'logscale)

(defface logscale-transforming-functions-face
  '((t :inherit font-lock-function-name-face))
  ;; '((t :inherit font-lock-keyword-face))
  ;; '((t :inherit font-lock-type-face))
  "Face for transforming functions such as `count' and `values' in LogScale."
  :group 'logscale)

(defface logscale-language-constants-face
  '((t :inherit font-lock-constant-face))
  ;; '((t :inherit font-lock-type-face))
  ;; '((t :inherit font-lock-function-name-face))
  "Face for language constants such as `as' and `by' in LogScale."
  :group 'logscale)

(defface logscale-macros-face
  '((t :inherit font-lock-function-name-face))
  ;; '((t :inherit font-lock-keyword-face))
  ;; '((t :inherit font-lock-type-face))
  "Face for macros in LogScale."
  :group 'logscale)

(defface logscale-keyword-face
  '((t :inherit font-lock-variable-name-face))
  ;; '((t :inherit font-lock-constant-face))
  ;; '((t :inherit font-lock-variable-name-face))
  "Face for keywords (e.g. `sourcetype=*') in LogScale."
  :group 'logscale)

(defface logscale-digits-face
  ;; '((t :inherit font-lock-number-face))  ;; Added too recently
  '((t :inherit font-lock-type-face))
  "Face for digits in LogScale."
  :group 'logscale)

(defface logscale-escape-chars-face
  ;; '((t :inherit font-lock-escape-face))  ;; Added too recently
  '((t :inherit font-lock-constant-face))
  "Face for escape characters in LogScale."
  :group 'logscale)

(defface logscale-operators-face
  '((t :inherit font-lock-builtin-face
       :weight bold))
  "Face for operators in LogScale."
  :group 'logscale)



;;; Syntax

;; Update syntax table; refs:
;;   - https://www.gnu.org/software/emacs/manual/html_node/elisp/Syntax-Table-Functions.html
;;   - https://www.gnu.org/software/emacs/manual/html_node/elisp/Syntax-Flags.html
;;   - https://www.gnu.org/software/emacs/manual/html_node/elisp/Syntax-Descriptors.html
;;   - https://www.gnu.org/software/emacs/manual/html_node/elisp/Syntax-Class-Table.html
(defconst logscale-mode-syntax-table
  (with-syntax-table (copy-syntax-table)
    ;; C/C++ style comments
	(modify-syntax-entry ?/ ". 124b")
	(modify-syntax-entry ?* ". 23")
	(modify-syntax-entry ?\n "> b")

    ;; The pipe character needs to be counted as a symbol-constituent
    ;; character, so that symbols are broken up by pipes; refs:
    ;; TODO: do I need this?
    (modify-syntax-entry ?| " ")

    ;; Chars are the same as strings
    ;; TODO: do I need this?
    (modify-syntax-entry ?' "\"")

    ;; Syntax table
    (syntax-table))
  "Syntax table for `logscale-mode'.")

(eval-and-compile
  (defconst logscale-functions
    '("array:append" "array:contains" "array:eval" "array:filter"
      "array:length" "array:reduceAll" "array:regex" "asn" "avg"
      "base64Decode" "bitfield:extractFlags" "bucket" "callFunction"
      "cidr" "collect" "communityId" "concat" "concatArray" "copyEvent"
      "count" "counterAsRate" "createEvents" "crypto:md5" "default"
      "drop" "dropEvent" "duration" "end" "eval" "eventFieldCount"
      "eventInternals" "eventSize" "fieldset" "fieldstats"
      "findTimestamp" "format" "formatDuration" "formatTime"
      "geography:distance" "geohash" "getField" "groupBy" "hash"
      "hashMatch" "hashRewrite" "head" "if" "in" "ioc:lookup"
      "ipLocation" "join" "json:prettyPrint" "kvParse" "length"
      "linReg" "lower" "lowercase" "match" "math:abs" "math:arccos"
      "math:arcsin" "math:arctan" "math:arctan2" "math:ceil" "math:cos"
      "math:cosh" "math:deg2rad" "math:exp" "math:expm1" "math:floor"
      "math:log" "math:log10" "math:log1p" "math:log2" "math:mod"
      "math:pow" "math:rad2deg" "math:sin" "math:sinh" "math:sqrt"
      "math:tan" "math:tanh" "max" "min" "now" "parseCEF" "parseCsv"
      "parseFixedWidth" "parseHexString" "parseInt" "parseJson" "parseLEEF"
      "parseTimestamp" "parseUri" "parseUrl" "parseXml" "percentile"
      "range" "rdns" "readFile" "regex" "rename" "replace" "round"
      "sample" "sankey" "select" "selectFromMax" "selectFromMin"
      "selectLast" "selfJoin" "selfJoinFilter" "series" "session"
      "setField" "shannonEntropy" "sort" "split" "splitString" "start"
      "stats" "stdDev" "stripAnsiCodes" "subnet" "sum" "table" "tail"
      "test" "text:contains" "time:dayOfMonth" "time:dayOfWeek"
      "time:dayOfWeekName" "time:dayOfYear" "time:hour" "time:millisecond"
      "time:minute" "time:month" "time:monthName" "time:second"
      "time:weekOfYear" "time:year" "timeChart" "tokenHash" "top"
      "transpose" "unit:convert" "upper" "urlDecode" "urlEncode"
      "wildcard" "window" "worldMap" "writeJson" "xml:prettyPrint"
      "=>"))

  ;; TODO: = is an operator if used in filter but not in kwargs
  ;; TODO: is ! an operator?
  (defconst logscale-operators
    '("|" ":=" ">" "<" ">=" "<=" "=")))

;; A LogScale word can contain underscores.  To use in the place of `word'
;;
;; Reference on extending rx:
;;   - https://www.gnu.org/software/emacs/manual/html_node/elisp/Extending-Rx.html
;;   - https://emacs.stackexchange.com/q/79050
;;   - https://emacsdocs.org/docs/elisp/Rx-Notation#macro-rx-define-name-arglist-rx-form
(rx-define logscale-word
  (or word "_"))  ;;; TODO: do we need any of the following?: #, :, _, -

;; Pattern for regular expression definition in Logscale
(rx-define logscale-regexp-syntax
  (and "/" (zero-or-more (not "/")) "/"))

;; Match a logscale operator with word boundaries
;;
;; NOTE: The core group matching operators (which is required to denote that the statement
;; is doing filtering) required the `paren' argument of `regexp-opt' to be `nil' or
;; `not-nil' ; it does *not* work with `words' or `symbols' for some reason:
;;   - https://www.gnu.org/software/emacs/manual/html_node/elisp/Regexp-Functions.html#index-regexp_002dopt
(rx-define logscale-operator
  ;; TODO: get working!  Was working with word-boundary
  ;; TODO: NOTE: that 'nil works with word boundary but only not-nil with no word boundary
  ;; (and word-boundary (regexp (regexp-opt logscale-operators 'not-nil)) word-boundary)
  (regexp (regexp-opt logscale-operators 'not-nil)))

;; A variable/value by which to filter can be:
;;   - A number;
;;   - A word/string; or
;;   - A regular expresison.
;;
;; I believe this is sufficient
(rx-define logscale-value
  (or (one-or-more digit)
      (and (optional "\"") (one-or-more (or "*" logscale-word)) (optional "\""))
      logscale-regexp-syntax))

;; NOTE: features required (https://library.humio.com/data-analysis/syntax.html, https://library.humio.com/data-analysis/functions.html):
;;   - filter (light blue)
;;   - function (dark blue, includes : in function name, and apparently =>)
;;   - operator (grey, includes pipe, >, :=, etc., but not ;)
;;   - variables (orange, including strings and numbers)
;;   - regex (pink)
;;   - new fields
;;   - conditions
;;   - joins
;;   - array
;;   - rel time
;;   - grammar subset
;;   - comments (C style)
;;   - macros?  preprocessors?  symbols?  escape characters?
;;   - field names when used in a function is one colour (orange) but another in a filter (light blue)
;;   - urls (underlined) - need to test if scheme is required or not - see https://github.com/JuliaWeb/URIs.jl/blob/dce395c3/src/URIs.jl#L91-L108

;; A filter has some word and a non-pipe operator after it (the word preceeding the operator is the field you are filtering by)
;; TODO: (better) documentation
;; TODO OOOOOOOOOOOOOOOOOOO: DO NOT MATCH IF INSIDE FUNCTION: https://chatgpt.com/c/6710e658-edb8-800e-87e5-05bee9ba7091
(defconst logscale-filter-regexp
  (rx
   (group (one-or-more (or "#" "@" logscale-word)))
   (zero-or-more space)
   ;; TODO: should we just use operator regex in here rather than defining its own logscale-operator-regexp?
   logscale-operator
   (zero-or-more space)
   logscale-value))

;; TODO: document
;; TODO: do * work in filter variable?  E.g., `sourcetype=access_*'  I think they do
;; variables can also exist in match statements etc.
(defconst logscale-variable-regexp
  ())

;; A function is one of the functions defined above with parentheses indicating the function call
(defconst logscale-function-regexp
  (rx (group (regexp (regexp-opt logscale-functions 'words))) "(" (zero-or-more any) ")"))



;; TODO: need to handle function arguments as well as function names, maybe I can do this in one go, and have zero or more inner groups in the function where the variable is a matching group
;; (defconst logscale-function-regexp
  ;; (rx (group (regexp (regexp-opt logscale-functions 'words))) "(" (zero-or-more (group (TODO)) ")"))

;; TODO: (optional (and "," (zero-or-more space))) (group (one-or-more logscale-word)) (zero-or-more space)  "=" (zero-or-more space) (group (zero-or-more any))

;; [(rx-define logscale-function-argument
  ;; Optional argument separator
  ;; (optional (and "," (zero-or-more space)))
  
  ;; Optional keyword for argument
  ;; (optional (and
             ;; (one-or-more logscale-word)
             ;; (zero-or-more space)
             ;; "="
             ;; (zero-or-more space)))

  ;; Variable itself
  ;; We should exclude [ and (, and also inner functions, which are recursive...
  ;; (any)
  ;; )

(rx-define logscale-value
  (or (one-or-more digit)
      (and (optional "\"") (one-or-more (or "*" logscale-word)) (optional "\""))
      logscale-regexp-syntax))


(defconst logscale-function-regexp
  (rx (group (regexp (regexp-opt logscale-functions 'words))) "(" (optional (zero-or-more logscale-function-argument)) ")"))

;(zero-or-more (group (optional (and "," (zero-or-more space))) (group (one-or-more logscale-word)) (zero-or-more space)  "=" (zero-or-more space) (group (zero-or-more any))))

(zero-or-more (group (optional (and "," (zero-or-more space))) (group (one-or-more logscale-word)) (zero-or-more space)  "=" (zero-or-more space) (group (zero-or-more any))))

;; TODO: THIS IS KEWORD ONLY; OR positional
;; (optional (one-or-more logscale-word) (zero-or-more space) "=" (zero-or-more space)) (one-or-more any)

;; TODO: this will not work because you can have arrays and suff but we only want to highlight words!
;; (optional (group (one-or-more logscale-word)) (zero-or-more space) "=" (zero-or-more space)) (group (one-or-more any))

;; TODO: this isn't working.  I need some kind of parser that understands where all different variables are.  The options appear to be:
;;   - After a filter
;;   - Inside a function
;;   - Inside match statements
;;
;; Also note that the only variables that have different highlighting are regex.  Also note that kwargs in functions should be highlighted differently to filters
;;
;; This feels like a big task.  It somehow needs to be syntax-aware, rather than just pattern matching


;; TODO: document
;; (defconst logscale-operator-regexp
;; (rx word-boundary (group (regexp (regexp-opt logscale-operators 'words))) word-boundary))

;; (defconst logscale-operator-regexp
;; (rx word-boundary (group (regexp (regexp-opt logscale-operators 'nil))) word-boundary))

(defconst logscale-operator-regexp
  (rx word-boundary logscale-operator word-boundary))

;; (when (string-match  "hello := 1")
;; (match-string 0 "hello := 1"))

;; Specify regular expressions between forward slashes
(defconst logscale-regexp-regexp
  (rx logscale-regexp-syntax))

;; Relevant refs
;;   - Font faces: https://www.gnu.org/software/emacs/manual/html_node/elisp/Faces-for-Font-Lock.html
;;   - Regex: https://www.gnu.org/software/emacs/manual/html_node/elisp/Rx-Constructs.html
;;
;; Note the double apostrophe before providing custom type faces:
;;   - https://emacs.stackexchange.com/a/3587
(defconst logscale-font-lock-keywords
  (list
   ;; Syntax defined by keyword lists
   ;; (cons (regexp-opt logscale-builtin-functions 'symbols) ''logscale-builtin-functions-face)
   ;; (cons (regexp-opt logscale-transforming-functions 'symbols) ''logscale-transforming-functions-face)
   ;; (cons (regexp-opt logscale-language-constants 'symbols) ''logscale-language-constants-face)
   ;; (cons (regexp-opt logscale-operators 'symbols) ''logscale-operators-face)
   ;; (list logscale-operator-regexp 1 ''logscale-operators-face)
   (list logscale-operator-regexp 1 ''logscale-escape-chars-face)

   ;; Eval functions
   ;; (cons splunk-eval-regexp ''splunk-eval-functions-face)
   ;; (list logscale-eval-regexp 2 ''logscale-eval-functions-face)

   ;; Alternative comment styles
   ;;
   ;; Note the syntax-level override:
   ;;   - https://emacs.stackexchange.com/a/79049
   ;;   - https://stackoverflow.com/a/24107675
   ;;   - https://emacs.stackexchange.com/a/61891
   ;; (list logscale-alt-comment-regexp 0 ''logscale-comment-face t)

   ;; Syntax defined by regex
   ;;
   ;; Note the extraction of specific groups from the regex:
   ;;   - https://emacs.stackexchange.com/a/79044
   (list logscale-filter-regexp 1 ''logscale-macros-face)
   ;; (cons logscale-variable-regexp ''logscale-digits-face)
   (list logscale-function-regexp 1 ''logscale-escape-chars-face)
   (list logscale-function-regexp 4 ''logscale-digits-face)
   (cons logscale-regexp-regexp ''logscale-keyword-face)))



;;; Mode

;;;###autoload
(define-derived-mode logscale-mode prog-mode "LogScale"
  "Major Mode for editing LogScale Query Language source code.

\\{logscale-mode-map}"
  :syntax-table logscale-mode-syntax-table
  (setq-local font-lock-defaults '(logscale-font-lock-keywords))
  (setq-local comment-start "//")
  (setq-local indent-line-function 'logscale-indent-line))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.logscale\\'" . logscale-mode))
(add-to-list 'auto-mode-alist '("\\.ls\\'" . logscale-mode))
(add-to-list 'auto-mode-alist '("\\.lsq\\'" . logscale-mode))
(add-to-list 'auto-mode-alist '("\\.lsql\\'" . logscale-mode))
(add-to-list 'auto-mode-alist '("\\.lsqlq\\'" . logscale-mode))
(add-to-list 'auto-mode-alist '("\\.lql\\'" . logscale-mode))
(add-to-list 'auto-mode-alist '("\\.lqlq\\'" . logscale-mode))
(add-to-list 'auto-mode-alist '("\\.cql\\'" . logscale-mode))
(add-to-list 'auto-mode-alist '("\\.csql\\'" . logscale-mode))
(add-to-list 'auto-mode-alist '("\\.fls\\'" . logscale-mode))
(add-to-list 'auto-mode-alist '("\\.flsq\\'" . logscale-mode))
(add-to-list 'auto-mode-alist '("\\.flsql\\'" . logscale-mode))
(add-to-list 'auto-mode-alist '("\\.flsqlq\\'" . logscale-mode))
(add-to-list 'auto-mode-alist '("\\.flq\\'" . logscale-mode))
(add-to-list 'auto-mode-alist '("\\.flql\\'" . logscale-mode))
(add-to-list 'auto-mode-alist '("\\.humio\\'" . logscale-mode))
;; TODO: we don't need all of these of course

(provide 'logscale-mode)



;; Local Variables:
;; coding: utf-8
;; checkdoc-major-mode: t
;; End:

;;; logscale-mode.el ends here
