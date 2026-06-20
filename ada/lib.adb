--  An Ada library (compile with --dll). Each subprogram becomes a public static
--  method on CProgram (prefixed ada_), callable from C#/VB.NET with .NET signatures.
function Add (A : Integer; B : Integer) return Integer is
begin
   return A + B;
end Add;

function Fib (N : Integer) return Integer is
   A : Integer := 0;
   B : Integer := 1;
   T : Integer;
begin
   for I in 1 .. N loop
      T := A + B;
      A := B;
      B := T;
   end loop;
   return A;
end Fib;
