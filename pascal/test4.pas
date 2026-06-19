program Test4;
var ch: char; i, vowels: integer; s: string;
begin
  s := 'Hello World 123';
  vowels := 0;
  for i := 1 to length(s) do
  begin
    ch := s[i];
    if ch in ['a'..'z', 'A'..'Z'] then
    begin
      if upcase(ch) in ['A', 'E', 'I', 'O', 'U'] then
        vowels := vowels + 1;
    end;
  end;
  writeln('vowels = ', vowels);
  for i := 0 to 9 do
    if i in [2, 3, 5, 7] then
      write(i, ' ');
  writeln('are prime-ish');
end.
