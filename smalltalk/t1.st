"Basics: messages, precedence, control flow"
| x sum |
x := 6.
(x * 7) printNl.
'Hello from Smalltalk' printNl.
(3 + 4 * 2) printNl.
5 factorial printNl.
sum := 0.
1 to: 10 do: [:i | sum := sum + i].
sum printNl.
(sum > 50) ifTrue: ['big sum' printNl] ifFalse: ['small sum' printNl].
| n |
n := 1.
[n < 5] whileTrue: [n := n * 2].
n printNl.
3 timesRepeat: ['tick' printNl].
