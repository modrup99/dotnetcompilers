-- tables: array part, hash part, length, iteration, and table-based OOP
local t = {10, 20, 30}
print(#t, t[1], t[3])
t[4] = 40
print(#t)

local p = {name = "Ada", year = 1983}
print(p.name, p.year)
p.year = 2012
print(p.year)

-- iterate (for-in over a table)
local colors = {"red", "green", "blue"}
for i, c in ipairs(colors) do print(i, c) end

-- a table-based object: methods stored on the instance, called with : sugar (adds self)
local acc = {balance = 100}
function acc.deposit(self, n) self.balance = self.balance + n end
function acc:withdraw(n) self.balance = self.balance - n end   -- : sugar adds self
acc.deposit(acc, 50)
acc:withdraw(30)             -- method-call sugar: acc passed as self
print(acc.balance)

print(type(t), type(p.name), type(acc.deposit))
