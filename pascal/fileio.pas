program FileIO;
var f: text; line: string; i: integer;
begin
  assign(f, 'out/ptest.txt');
  rewrite(f);
  for i := 1 to 3 do
    writeln(f, 'line ', i);
  writeln(f, 'done');
  close(f);
  assign(f, 'out/ptest.txt');
  reset(f);
  while not eof(f) do
  begin
    readln(f, line);
    writeln('read: ', line);
  end;
  close(f);
end.
