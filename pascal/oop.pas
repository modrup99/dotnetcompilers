program OOPDemo;
type
  TAnimal = object
    name: string;
    legs: integer;
    procedure Init(n: string; l: integer);
    function Describe: string;
    function Legs2: integer;
  end;
  TDog = object(TAnimal)
    procedure Bark;
  end;

procedure TAnimal.Init(n: string; l: integer);
begin
  name := n;
  legs := l;
end;

function TAnimal.Describe: string;
begin
  Describe := name;
end;

function TAnimal.Legs2: integer;
begin
  Legs2 := legs * 2;
end;

procedure TDog.Bark;
begin
  writeln(name, ' says woof! (', legs, ' legs, legs2=', Legs2, ')');
end;

var d: TDog;
begin
  d.Init('Rex', 4);
  writeln('describe: ', d.Describe);
  d.Bark();
end.
