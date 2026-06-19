program Test3;
type
  IntPtr = ^integer;
  Rec = record a, b: integer; end;
var
  p: IntPtr;
  r: Rec;
  i: integer;
begin
  new(p);
  p^ := 42;
  writeln('deref = ', p^);
  dispose(p);
  r.a := 10; r.b := 20;
  with r do
    writeln('with sum = ', a + b);
  for i := 1 to 5 do
    case i of
      1, 2: writeln(i, ' low');
      3..5: writeln(i, ' high');
    end;
  i := 0;
  goto 10;
  i := 999;
10:
  writeln('after goto i=', i);
end.
