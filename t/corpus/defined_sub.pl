# SubDefined: `defined &NAME` the program may change as it runs -- asked where
# it runs, with the graphs that may change it (here the program itself).
*late = sub { 1 };
print defined &late ? "y\n" : "n\n";
print defined &nope ? "y\n" : "n\n";
