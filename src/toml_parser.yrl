%% -*- mode: erlang -*-

Nonterminals
hash_groups group keygroup multigroup group_values multi_values value nls
array elements element_value.

Terminals
identifier string number datetime boolean
'[[' ']]' '[' ']' '=' ',' '.' nl.

Rootsymbol
hash_groups.

hash_groups -> group_values : '$1'.
hash_groups -> hash_groups group : '$1' ++ ['$2'].
hash_groups -> nl hash_groups : '$2'.

group_values -> '$empty' : [].
group_values -> group_values identifier '=' value nl : '$1' ++ [{'$2', '$4'}].
group_values -> group_values nl : '$1'.

multi_values -> '$empty' : [].
multi_values -> multi_values identifier '=' value nl : '$1' ++ [{'$2', '$4'}].
multi_values -> multi_values nl : '$1'.

group -> '[' keygroup ']' nl group_values : {group, '$2', '$5'}.
group -> '[[' multigroup ']]' nl multi_values : {multi, '$2', '$5'}.

keygroup -> value : ['$1'].
keygroup -> keygroup '.' value : '$1' ++ ['$3'].

multigroup -> value : ['$1'].
multigroup -> multigroup '.' value : '$1' ++ ['$3'].

value -> identifier : '$1'.
value -> string : '$1'.
value -> number : '$1'.
value -> datetime : '$1'.
value -> boolean : '$1'.
value -> array : '$1'.

array -> '[' elements ']' : '$2'.

elements -> '$empty' : [].
elements -> element_value : ['$1'].
elements -> element_value ',' elements : ['$1'|'$3'].
elements -> nl elements : '$2'.

element_value -> nls value nls: '$2'.

nls -> '$empty'.
nls -> nls nl.


Expect 6.
