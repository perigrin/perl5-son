use v5.42; use experimental "class"; class K { field %h = (s => [1, 2]); method g { scalar($h{s}->@*) } } print K->new->g, "\n";
