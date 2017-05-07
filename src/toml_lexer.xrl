%% -*- mode: erlang -*-

Definitions.

ALPHA = [a-zA-Z]
ALNUM = [a-zA-Z0-9]
GRAPH = [!--/-Z\\^-~]
SPACING = (\s|\t|\f|\r)

YEAR = ([0-9][0-9][0-9][0-9])
MON = ([01][0-9])
DAY = ([0-3][0-9])
HOUR = ([0-2][0-9])
MIN = ([0-5][0-9])
SEC = {MIN}
TZD = (Z|(\+|-){HOUR}:{MIN})


Rules.

#[^\n]* : skip_token.
{SPACING}+ : skip_token.

= : {token, {'=', TokenLine}}.
\[\[ : {token, {'[[', TokenLine}}.
]] : {token, {']]', TokenLine}}.
\[ : {token, {'[', TokenLine}}.
] : {token, {']', TokenLine}}.
, : {token, {',', TokenLine}}.
\. : {token, {'.', TokenLine}}.
\n : {token, {nl, TokenLine}}.

(true|false) : {token, {boolean, list_to_atom(TokenChars)}}.
{ALPHA}{GRAPH}* : {token, {identifier, TokenChars}}.
{YEAR}-{MON}-{DAY}T{HOUR}:{MIN}:{SEC}{TZD}? : {token, {datetime, scan_datetime(TokenChars)}}.
(\+|-)?[0-9]+ : {token, {number, list_to_integer(TokenChars)}}.
(\+|-)?[0-9]+\.[0-9]+((E|e)(\+|-)?[0-9]+)? : {token, {number, list_to_float(TokenChars)}}.
"([^\"]|\\.)*" : {token, {string, scan_string(TokenChars)}}.

Erlang code.

scan_string([$"|S]) ->
    unescape(S, []).

unescape([], [$"|Acc]) ->
    lists:reverse(Acc);
unescape([$\\|S], Acc) ->
    {C, S1} = unescape(S),
    unescape(S1, [C|Acc]);
unescape([C|S], Acc) ->
    unescape(S, [C|Acc]).

unescape([$\\|S]) ->
    {$\\, S};
unescape([$t|S]) ->
    {$\t, S};
unescape([$n|S]) ->
    {$\n, S};
unescape([$r|S]) ->
    {$\r, S};
unescape([$"|S]) ->
    {$", S};
unescape([$x, X, Y|S]) ->
    {list_to_integer([X, Y], 16), S}.

scan_datetime(S) ->
    [Year, Month, Day, Hour, Min, Sec|_Tzd] =
        string:tokens(string:strip(S, right, $Z), "-:T"),
    %% TODO adjust time from timezone to UTC, if _Tzd /= []
    {{list_to_integer(Year), list_to_integer(Month), list_to_integer(Day)},
     {list_to_integer(Hour), list_to_integer(Min), list_to_integer(Sec)}}.
