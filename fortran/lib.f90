! A Fortran 90 library (compile with --dll). Each FUNCTION becomes a public static
! method on CProgram, so C#/VB.NET can call it like any .NET API. Function arguments
! are by value, so the signatures are clean (int add(int,int), double, ...).

integer function add(a, b)
  integer :: a, b
  add = a + b
end function add

real function circle_area(r)
  real :: r
  circle_area = 3.14159265 * r * r
end function circle_area

integer function fib(n)
  integer :: n, a, b, t, i
  a = 0
  b = 1
  do i = 1, n
    t = a + b
    a = b
    b = t
  end do
  fib = a
end function fib
