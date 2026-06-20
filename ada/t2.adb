with Ada.Text_IO; use Ada.Text_IO;
procedure Main is
   A : array (1 .. 5) of Integer;
   Sum : Integer := 0;
begin
   for I in 1 .. 5 loop
      A (I) := I * I;
   end loop;
   for I in reverse 1 .. 5 loop
      Sum := Sum + A (I);
   end loop;
   Put_Line ("Squares sum 1..5 =" & Integer'Image (Sum));
end Main;
