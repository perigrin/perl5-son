use v5.36;
package Optimizer { sub collapse ($, $phi) { return "c$phi" } }
print Optimizer->collapse(7), " ", (eval { Optimizer->collapse(); 1 } ? "ran" : "too few"), "\n";
