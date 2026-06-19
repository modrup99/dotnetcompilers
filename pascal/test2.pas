program Test2;
type
  Color = (Red, Green, Blue);
  Point = record
    x, y: integer;
  end;
var
  nums: array[1..5] of integer;
  grid: array[1..2, 1..3] of integer;
  p: Point;
  c: Color;
  s: string;
  i, j: integer;
  r: real;
begin
  for i := 1 to 5 do
    nums[i] := i * i;
  writeln('squares:');
  for i := 1 to 5 do
    write(nums[i], ' ');
  writeln;

  for i := 1 to 2 do
    for j := 1 to 3 do
      grid[i, j] := i * 10 + j;
  writeln('grid[2,3] = ', grid[2, 3]);

  p.x := 3;  p.y := 4;
  writeln('point = (', p.x, ',', p.y, ')');

  c := Green;
  writeln('color ord = ', ord(c));

  s := 'Hello';
  s := s + ', ' + 'World';
  writeln(s, ' len=', length(s));
  writeln('upper first = ', upcase(s[1]));

  r := 22.0 / 7.0;
  writeln('pi approx = ', r:0:4);
  writeln('abs(-5)=', abs(-5), ' sqrt(2)=', sqrt(2.0):0:3);
end.
