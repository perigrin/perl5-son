our $g = 0; sub inc { if ($g >= 0) { $g = $g + 1 } return $g } inc(); print inc(), " $g\n";
