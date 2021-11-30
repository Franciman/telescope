(fix fib
     (lambda ([: n Int])
         (if (< n 2)
             n
             (+ (fib (- n 1)) (fib (- n 2))))))
