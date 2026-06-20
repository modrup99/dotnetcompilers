"A Smalltalk class compiled as a .NET library (smalltalk lib.st --dll).
 Counter is the first class defined, so its runtime class id is 10."
Object subclass: Counter [
   | count |
   init      [ count := 0 ]
   add: n    [ count := count + n ]
   count     [ ^ count ]
]
