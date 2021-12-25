((fix (lambda (sum n)
         (if (#builtin_< n 1)
             n
             (#builtin_+ (sum (builtin_- n 1)) n)))) 10000000)
