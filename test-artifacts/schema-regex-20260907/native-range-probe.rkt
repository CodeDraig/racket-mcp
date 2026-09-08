#lang racket/base
(printf "Racket ~a\n" (version))
(for ([pattern (list #px"[\uff00-\uffff]"
                     #px"(?:[\uff00-\uff3f]|[\uff40-\uff7f]|[\uff80-\uffbf]|[\uffc0-\uffff])"
                     #px"(?:(?>[\uff00-\uff3f])|(?>[\uff40-\uff7f])|(?>[\uff80-\uffbf])|(?>[\uffc0-\uffff]))")]
      [description '(wide-range merged-intervals protected-intervals)])
  (printf "~a matches U+FF40: ~s\n" description (regexp-match? pattern "\uff40")))
