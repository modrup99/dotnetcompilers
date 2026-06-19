unit MathUtil;
interface
function Square(x: integer): integer;
function Cube(x: integer): integer;
implementation
function Square(x: integer): integer;
begin Square := x * x; end;
function Cube(x: integer): integer;
begin Cube := x * x * x; end;
end.
