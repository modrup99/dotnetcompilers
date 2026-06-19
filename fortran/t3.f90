! select case, do while, by-ref subroutine, character
program t3
  implicit none
  integer :: i
  character(len=20) :: msg
  do i = 1, 4
    select case (i)
      case (1)
        print *, "one"
      case (2, 3)
        print *, "two or three"
      case default
        print *, "other"
    end select
  end do
  i = 1
  do while (i <= 3)
    print *, "count", i
    i = i + 1
  end do
  msg = "Fortran" // " 90"
  print *, msg
  call swap_demo
end program t3

subroutine swap(a, b)
  integer :: a, b, t
  t = a
  a = b
  b = t
end subroutine swap

subroutine swap_demo
  integer :: x, y
  x = 10
  y = 20
  call swap(x, y)
  print *, "after swap:", x, y
end subroutine swap_demo
