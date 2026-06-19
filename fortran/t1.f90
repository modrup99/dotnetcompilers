program t1
  implicit none
  integer :: i, n, total
  real :: x
  n = 5
  total = 0
  do i = 1, n
    total = total + i
  end do
  print *, "sum 1..", n, "=", total
  x = sqrt(2.0)
  print *, "sqrt(2) =", x
  if (total > 10) then
    print *, "big"
  else
    print *, "small"
  end if
end program t1
