! arrays, do-loop, function and subroutine
program t2
  implicit none
  integer :: a(5), i
  integer :: fact
  do i = 1, 5
    a(i) = i * i
  end do
  print *, "squares:", a(1), a(2), a(3), a(4), a(5)
  print *, "fact(5) =", fact(5)
  call greet(3)
end program t2

integer function fact(n)
  integer :: n, r, k
  r = 1
  do k = 2, n
    r = r * k
  end do
  fact = r
end function fact

subroutine greet(count)
  integer :: count, j
  do j = 1, count
    print *, "hello", j
  end do
end subroutine greet
