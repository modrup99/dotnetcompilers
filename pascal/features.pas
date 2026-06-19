program Features;
var i, sum: integer;

procedure swap(var x: integer; var y: integer);
var t: integer;
begin
  t := x; x := y; y := t;
end;

begin
  sum := 0;
  i := 1;
  while i <= 5 do
  begin
    sum := sum + i;
    i := i + 1;
  end;
  writeln('sum 1..5 = ', sum);
  i := 0;
  repeat
    i := i + 1;
  until i >= 3;
  writeln('repeat ended at ', i);
  i := 7; sum := 9;
  swap(i, sum);
  writeln('after swap i=', i, ' sum=', sum);
  case i of
    1: writeln('one');
    9: writeln('nine');
  else
    writeln('other');
  end;
end.
