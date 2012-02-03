-module(strikead_string).
-export([split/2, empty/1, not_empty/1, strip/1, replace/2]).

split(S, Delimiter) -> lists:reverse(split(S, Delimiter, [])).

split("", _, R) -> R;
split(S, Delimiter, R) -> 
	case lists:splitwith(fun(A) -> A /= Delimiter end, S) of
		{H, ""} -> [H|R];
		{H, Rest} -> split(string:substr(Rest, 2), Delimiter, [H|R])
	end.

empty(S) -> S == "".

not_empty(S) -> S /= "".

strip(S) -> strip(S, forward).
strip("", _) -> "";
strip([$ | T], Dir) -> strip(T, Dir);
strip([$\t | T], Dir) -> strip(T, Dir);
strip([$\r | T], Dir) -> strip(T, Dir);
strip([$\n | T], Dir) -> strip(T, Dir);
strip(T, forward) -> lists:reverse(strip(lists:reverse(T), backward));
strip(T, backward) -> T.


replace(C, S) -> replace("", C, S).
replace(R, _, []) -> lists:reverse(R);
replace(R, C, [C|S]) -> replace(R, C, S);
replace(R, C, [X|S]) -> replace([X|R], C, S).

