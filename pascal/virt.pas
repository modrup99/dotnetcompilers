program VirtDemo;
type
  TShape = object
    name: string;
    constructor Init(n: string);
    function Area: integer; virtual;
    procedure Show;
  end;
  TSquare = object(TShape)
    side: integer;
    constructor Init(s: integer);
    function Area: integer; virtual;
  end;
  TCircle = object(TShape)
    r: integer;
    constructor Init(rad: integer);
    function Area: integer; virtual;
  end;
constructor TShape.Init(n: string);
begin name := n; end;
function TShape.Area: integer;
begin Area := 0; end;
procedure TShape.Show;
begin writeln(name, ' area = ', Area); end;
constructor TSquare.Init(s: integer);
begin name := 'square'; side := s; end;
function TSquare.Area: integer;
begin Area := side * side; end;
constructor TCircle.Init(rad: integer);
begin name := 'circle'; r := rad; end;
function TCircle.Area: integer;
begin Area := 3 * r * r; end;
var sq: TSquare; ci: TCircle; p: ^TShape;
begin
  sq.Init(5);
  ci.Init(10);
  sq.Show();
  ci.Show();
  p := @sq;  writeln('via ptr: ', p^.Area);
  p := @ci;  writeln('via ptr: ', p^.Area);
end.
