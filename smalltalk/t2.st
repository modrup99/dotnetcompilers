"Classes: instance variables, methods, dynamic message dispatch"
Object subclass: Counter [
   | count |
   init       [ count := 0 ]
   increment  [ count := count + 1 ]
   add: n     [ count := count + n ]
   count      [ ^ count ]
]

Object subclass: Account [
   | balance |
   init           [ balance := 0 ]
   deposit: n     [ balance := balance + n ]
   withdraw: n    [ (n <= balance) ifTrue: [balance := balance - n]
                                   ifFalse: ['insufficient funds' printNl] ]
   balance        [ ^ balance ]
]

| c a |
c := Counter new.
c init.
c increment.  c increment.  c increment.
c add: 10.
c count printNl.

a := Account new.
a init.
a deposit: 100.
a withdraw: 30.
a withdraw: 1000.
a balance printNl.
