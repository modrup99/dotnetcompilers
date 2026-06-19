program Sets;
var vowels, letters, both: set of char;
    c: char; s: string; i, n: integer;
begin
  vowels := ['a', 'e', 'i', 'o', 'u'];
  letters := ['a'..'z'];
  both := letters - vowels;
  s := 'hello world';
  n := 0;
  for i := 1 to length(s) do
  begin
    c := s[i];
    if c in vowels then n := n + 1;
  end;
  writeln('vowels in "', s, '": ', n);
  if 'b' in both then writeln('b is a consonant');
  if 'a' in both then writeln('a is a consonant') else writeln('a is not a consonant');
end.
