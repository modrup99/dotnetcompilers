with Ada.Text_IO; use Ada.Text_IO;
procedure Main is
   type Color is (Red, Green, Blue);
   X : Integer := 5;
   Total : Integer := 0;
   C : Color := Green;

   function Square (N : Integer) return Integer is
   begin
      return N * N;
   end Square;

   procedure Swap (A : in out Integer; B : in out Integer) is
      T : Integer;
   begin
      T := A;
      A := B;
      B := T;
   end Swap;

begin
   Put_Line ("Hello from Ada");
   Put_Line ("Square of 5 is" & Integer'Image (Square (X)));

   for I in 1 .. 5 loop
      Total := Total + I;
   end loop;
   Put_Line ("Sum 1..5 =" & Integer'Image (Total));

   if Total > 10 then
      Put_Line ("big");
   elsif Total > 0 then
      Put_Line ("small");
   else
      Put_Line ("zero");
   end if;

   Swap (X, Total);
   Put_Line ("After swap X =" & Integer'Image (X));

   case C is
      when Red   => Put_Line ("red");
      when Green => Put_Line ("green");
      when Blue  => Put_Line ("blue");
   end case;
end Main;
