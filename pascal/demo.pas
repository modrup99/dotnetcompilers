program Demo;
var i, n: integer;

function fact(n: integer): integer;
begin
  if n <= 1 then
    fact := 1
  else
    fact := n * fact(n - 1);
end;

begin
  n := 5;
  for i := 1 to n do
    writeln('fact(', i, ') = ', fact(i));
end.
