program UseTest;
uses MathUtil;
var i: integer;
begin
  for i := 1 to 4 do
    writeln(i, ': sq=', Square(i), ' cube=', Cube(i));
end.
