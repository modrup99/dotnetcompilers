-- A Lua module compiled as a .NET library (lua lib.lua --dll). Running the chunk
-- registers these as globals; C# then looks them up by name and calls them.
function add(a, b)
  return a + b
end

function fib(n)
  if n < 2 then return n end
  return fib(n - 1) + fib(n - 2)
end
