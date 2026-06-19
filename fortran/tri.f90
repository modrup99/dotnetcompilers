! text-art triangle: build each row by string concatenation, then print it
program tri
  implicit none
  integer :: i, j
  character(len=20) :: row
  do i = 1, 5
    row = ""
    do j = 1, i
      row = row // "*"
    end do
    print *, row
  end do
end program tri
