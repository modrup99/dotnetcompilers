-- basics: variables, arithmetic, strings, control flow, functions
local x = 6
print(x * 7)
print(3 + 4 * 2)            -- precedence: 11
print("Lua" .. " " .. "rocks")
print(2 ^ 10)

local function fact(n)
  if n <= 1 then return 1 end
  return n * fact(n - 1)
end
print(fact(5))

local sum = 0
for i = 1, 10 do sum = sum + i end
print(sum)

local i = 1
while i < 100 do i = i * 2 end
print(i)

local a, b = 1, 2
a, b = b, a                  -- swap via multiple assignment
print(a, b)

local function fib(n)
  if n < 2 then return n end
  return fib(n - 1) + fib(n - 2)
end
print(fib(15))
