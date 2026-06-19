program P;
type T = object x: integer; end;
var t: T;
begin
  t.x := 5;
  writeln(t.x);
end.
