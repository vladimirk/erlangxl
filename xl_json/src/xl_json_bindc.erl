-module(xl_json_bindc).

-compile({parse_transform, do}).

-export([compile/2]).

%runtime
-export([cast/4]).

compile(Path, Dest) ->
    Module = filename:basename(Path, filename:extension(Path)),
    HrlPath = filename:join([Dest, "include", Module ++ ".hrl"]),
    ModulePath = filename:join([Dest, "src", Module ++ ".erl"]),
    do([error_m ||
        io:format("compile ~p to ~p~n", [Path, Dest]),
        Records <- file:consult(Path),
        generate_file(HrlPath, fun(F) -> generate_records(Records, F) end),
        generate_file(ModulePath, fun(F) -> generate_module(Records, Module, F) end)
    ]).


generate_records(Records, Out) ->
    xl_lists:eforeach(fun({Name, Fields}) ->
        do([error_m ||
            Generated <- xl_lists:emap(fun(Field) -> generate_field(Field) end, Fields),
            io:format(Out, "~n-record(~s, {~n\t~s~n}).", [Name, xl_string:join(Generated, ",\n\t")])
        ])
    end, Records).

-define(is_primitive_type(Type), Type == integer; Type == float; Type == boolean; Type == atom; Type == binary; Type == string; Type == any).
-define(is_primitive_type(Type, Default),
is_binary(Default), Type == string;
Default == undefined, Type == string;
is_binary(Default), Type == binary;
Default == undefined, Type == binary;
is_integer(Default), Type == integer;
Default == undefined, Type == integer;
is_float(Default), Type == float;
Default == undefined, Type == float;
is_atom(Default), Type == atom;
Default == true, Type == boolean;
Default == false, Type == boolean;
is_list(Default), Type == any;
Default == undefined, Type == any
).

%lists
generate_field({Name, {list, Type}}) when ?is_primitive_type(Type) ->
    {ok, xl_string:format("~p = error({required, ~p}) :: [~p()]", [Name, Name, Type])};
generate_field({Name, {list, Type}}) when is_atom(Type) ->
    {ok, xl_string:format("~p = error({required, ~p}) :: [#~p{}]", [Name, Name, Type])};
generate_field({Name, {list, {Module, Type}}}) when is_atom(Module), is_atom(Type) ->
    {ok, xl_string:format("~p = error({required, ~p})", [Name, Name])};

%lists with defaults
generate_field({Name, {list, Type, Default}}) when is_list(Default), ?is_primitive_type(Type) ->
    {ok, xl_string:format("~p = ~p :: [~p()]", [Name, Default, Type])};
generate_field({Name, {list, Type, Default}}) when is_atom(Type), is_list(Default) ->
    {ok, xl_string:format("~p = ~p :: [#~p{}]", [Name, Default, Type])};
generate_field({Name, {list, {Module, Type}, Default}}) when is_atom(Module), is_atom(Type), is_list(Default) ->
    {ok, xl_string:format("~p = ~p", [Name, Default])};

%options
generate_field({Name, {option, Type}}) when ?is_primitive_type(Type) ->
    {ok, xl_string:format("~p :: option_m:monad(~p())", [Name, Type])};
generate_field({Name, {option, Type}}) when is_atom(Type) ->
    {ok, xl_string:format("~p :: option_m:monad(#~p{})", [Name, Type])};
generate_field({Name, {option, {Module, Type}}}) when is_atom(Module), is_atom(Type) ->
    {ok, xl_string:format("~p", [Name])};

%options with defaults
generate_field({Name, {option, Type, Default}}) when ?is_primitive_type(Type, Default) ->
    {ok, xl_string:format("~p = {ok, ~p} :: option_m:monad(~p())", [Name, Default, Type])};

%enums
generate_field({Name, {enum, Type, _Enum}}) -> generate_field({Name, Type});

%primitives with defaults
generate_field({Name, {Type, Default}}) when ?is_primitive_type(Type, Default) ->
    {ok, xl_string:format("~p = ~p :: ~p()", [Name, Default, Type])};
generate_field({Name, {string, Default}}) ->
    generate_field({Name, {binary, Default}});

%primitives
%% generate_field({Name, string}) -> generate_field({Name, binary});
generate_field({Name, Type}) when ?is_primitive_type(Type) ->
    {ok, xl_string:format("~p = error({required, ~p}) :: ~p()", [Name, Name, Type])};
generate_field({Name, Type}) when is_atom(Type) ->
    {ok, xl_string:format("~p = error({required, ~p}) :: #~p{}", [Name, Name, Type])};
generate_field({Name, {Type, undefined}}) when is_atom(Type) ->
    {ok, xl_string:format("~p :: #~p{}", [Name, Type])};
generate_field({Name, {Module, Type}}) when is_atom(Module), is_atom(Type) ->
    {ok, xl_string:format("~p = error({required, ~p}) ", [Name, Name])};
generate_field({Name, {{Module, Type}, undefined}}) when is_atom(Module), is_atom(Type) ->
    {ok, xl_string:format("~p", [Name])};

%wtf
generate_field(D) -> {error, {dont_understand, D}}.

generate_file(Path, Generate) ->
    io:format("Generate ~s~n", [Path]),
    do([error_m ||
        filelib:ensure_dir(Path),
        Out <- file:open(Path, [write]),
        file:write(Out, "%% Generated by " ++ atom_to_list(?MODULE) ++ "\n"),
        try
            Generate(Out)
        after
            file:close(Out)
        end
    ]).

generate_module(Records, Name, Out) ->
    do([error_m ||
        file:write(Out, "-module(" ++ Name ++ ").\n\n"),
        file:write(Out, "-include(\"" ++ Name ++ ".hrl\").\n\n"),
        file:write(Out, "-define(JSON_API, xl_json_jiffy).\n\n"),
        file:write(Out, "-export([to_json/1, from_json/2, from_json_/2]).\n\n"),
        file:write(Out, "to_json(undefined) -> \"null\";\n\n"),
        file:write(Out, "to_json({ok, X}) -> to_json(X);\n\n"),
        file:write(Out, "to_json(L) when is_list(L) -> \"[\" ++ string:join([to_json(R) || R <- L], \",\") ++ \"]\";\n\n"),
        generate_to_json(Records, Out),
        file:write(Out, "from_json(Json, Type) ->\n"
        "\tcase ?JSON_API:from_json(Json) of\n"
        "\t\t{ok, List} when is_list(List)->\n"
        "\t\t\ttry\n"
        "\t\t\t\t{ok, [from_json_(R, Type) || R <- List]}\n"
        "\t\t\tcatch\n"
        "\t\t\t\terror:X -> {error, X}\n"
        "\t\t\tend;\n"
        "\t\t{ok, Document} ->\n"
        "\t\t\ttry\n"
        "\t\t\t\t{ok, from_json_(Document, Type)}\n"
        "\t\t\tcatch\n"
        "\t\t\t\terror:X -> {error, X}\n"
        "\t\t\tend;\n"
        "\t\tError -> Error\n"
        "end.\n\n"),
        file:write(Out, "from_json_(undefined, _Type)  -> undefined;\n\n"),
        generate_from_json(Records, Out)
    ]).

generate_to_json(Records, Out) ->
    do([error_m ||
        Functions <- xl_lists:emap(fun({RecordName, Fields}) ->
            do([error_m ||
                Generated <- xl_lists:emap(fun(Field) -> generate_to_json_field(RecordName, Field) end, Fields),
                return(
                    xl_string:format(
                        "to_json(R=#~p{}) ->\n\txl_string:join([\"{\",\n~s\n\t\"}\"])", [RecordName,
                            xl_string:join([xl_string:format("\t\t~s,", [F]) || F <- Generated], " \",\",\n")
                        ]
                    )
                )
            ])
        end, Records),
        file:write(Out, xl_string:join(Functions, ";\n") ++ ".\n\n")
    ]).

generate_to_json_field(RecordName, {Name, {enum, Type, _Enumeration}}) -> generate_to_json_field(RecordName, {Name, Type});
generate_to_json_field(RecordName, {Name, Type}) when ?is_primitive_type(Type) ->
    {ok, xl_string:format("\"\\\"~p\\\":\", xl_json:to_json(R#~p.~p)", [Name, RecordName, Name])};
generate_to_json_field(RecordName, {Name, {Type, _Default}}) when ?is_primitive_type(Type) ->
    generate_to_json_field(RecordName, {Name, Type});
generate_to_json_field(RecordName, {Name, {list, Type}}) when ?is_primitive_type(Type) ->
    generate_to_json_field(RecordName, {Name, Type});
generate_to_json_field(RecordName, {Name, {list, Type, _Default}}) when ?is_primitive_type(Type) ->
    generate_to_json_field(RecordName, {Name, Type});
generate_to_json_field(RecordName, {Name, {option, Type}}) when ?is_primitive_type(Type) ->
    generate_to_json_field(RecordName, {Name, Type});
generate_to_json_field(RecordName, {Name, {option, Type, _Default}}) when ?is_primitive_type(Type) ->
    generate_to_json_field(RecordName, {Name, Type});

generate_to_json_field(RecordName, {Name, {option, Type}}) when is_atom(Type) ->
    {ok, xl_string:format("\"\\\"~p\\\":\", to_json(R#~p.~p)", [Name, RecordName, Name])};
generate_to_json_field(RecordName, {Name, {option, {Module, Type}}}) when is_atom(Module), is_atom(Type) ->
    {ok, xl_string:format("\"\\\"~p\\\":\", ~p:to_json(R#~p.~p)", [Name, Module, RecordName, Name])};

generate_to_json_field(RecordName, {Name, {list, Type}}) when is_atom(Type) ->
    {ok, xl_string:format("\"\\\"~p\\\":\", \"[\" ++ string:join([to_json(X)||X <- R#~p.~p], \",\") ++ \"]\"", [Name, RecordName, Name])};
generate_to_json_field(RecordName, {Name, {list, Type, _Default}}) when is_atom(Type) ->
    generate_to_json_field(RecordName, {Name, {list, Type}});

generate_to_json_field(RecordName, {Name, {list, {Module, Type}}}) when is_atom(Module), is_atom(Type) ->
    {ok, xl_string:format("\"\\\"~p\\\":\", \"[\" ++ string:join([~p:to_json(X)||X <- R#~p.~p], \",\") ++ \"]\"", [Name, Module, RecordName, Name])};
generate_to_json_field(RecordName, {Name, {list, {Module, Type}, _Default}}) when is_atom(Module), is_atom(Type) ->
    generate_to_json_field(RecordName, {Name, {list, {Module, Type}}});

generate_to_json_field(RecordName, {Name, Type}) when is_atom(Type) ->
    {ok, xl_string:format("\"\\\"~p\\\":\", to_json(R#~p.~p)", [Name, RecordName, Name])};
generate_to_json_field(RecordName, {Name, {Type, undefined}}) when is_atom(Type) ->
    generate_to_json_field(RecordName, {Name, Type});
generate_to_json_field(RecordName, {Name, {Module, Type}}) when is_atom(Module), is_atom(Type) ->
    {ok, xl_string:format("\"\\\"~p\\\":\", ~p:to_json(R#~p.~p)", [Name, Module, RecordName, Name])};
generate_to_json_field(RecordName, {Name, {{Module, Type}, undefined}}) when is_atom(Module), is_atom(Type) ->
    generate_to_json_field(RecordName, {Name, {Module, Type}});

generate_to_json_field(_RecordName, Field) ->
    {error, {dont_understand, Field}}.

generate_from_json(Records, Out) ->
    do([error_m ||
        Functions <- xl_lists:emap(fun({RecordName, Fields}) ->
            do([error_m ||
                Generated <- xl_lists:emap(fun(Field) -> generate_from_json_field(Field) end, Fields),
                return(
                    xl_string:format(
                        "from_json_(J, ~p) ->\n\t#~p{\n~s\n\t}",
                        [RecordName, RecordName, xl_string:join([xl_string:format("\t\t~s", [F]) || F <- Generated], ",\n")]
                    )
                )
            ])
        end, Records),
        file:write(Out, xl_string:join(Functions, ";\n") ++ ".\n\n")
    ]).

generate_from_json_field({Name, Qualified = {enum, Type, _Enumeration}}) when ?is_primitive_type(Type) ->
    {ok, xl_string:format("~p = xl_json_bindc:cast(?JSON_API, ?JSON_API:get_value(~p, J), ~p, ~p)", [Name, Name, Qualified, {required, Name}])};
generate_from_json_field({Name, {enum, {Type, Default}, Enumeration}}) when ?is_primitive_type(Type) ->
    {ok, xl_string:format("~p = xl_json_bindc:cast(?JSON_API, ?JSON_API:get_value(~p, J), ~p, ~p)", [Name, Name, {enum, Type, Enumeration}, Default])};
generate_from_json_field({Name, Type}) when ?is_primitive_type(Type) ->
    {ok, xl_string:format("~p = xl_json_bindc:cast(?JSON_API, ?JSON_API:get_value(~p, J), ~p, ~p)", [Name, Name, Type, {required, Name}])};
generate_from_json_field({Name, Qualified = {enum, {list, Type}, _Enumeration}}) when ?is_primitive_type(Type) ->
    {ok, xl_string:format("~p = xl_json_bindc:cast(?JSON_API, ?JSON_API:get_value(~p, J), ~p, ~p)", [Name, Name, Qualified, {required, Name}])};
generate_from_json_field({Name, Qualified = {list, Type}}) when ?is_primitive_type(Type) ->
    {ok, xl_string:format("~p = xl_json_bindc:cast(?JSON_API, ?JSON_API:get_value(~p, J), ~p, ~p)", [Name, Name, Qualified, {required, Name}])};
generate_from_json_field({Name, Qualified = {option, Type}}) when ?is_primitive_type(Type) ->
    {ok, xl_string:format("~p = xl_json_bindc:cast(?JSON_API, ?JSON_API:get_value(~p, J), ~p, ~p)", [Name, Name, Qualified, undefined])};
generate_from_json_field({Name, {option, Type, Default}}) when ?is_primitive_type(Type) ->
    {ok, xl_string:format("~p = xl_json_bindc:cast(?JSON_API, ?JSON_API:get_value(~p, J), ~p, ~p)", [Name, Name, {option, Type}, Default])};
generate_from_json_field({Name, {Type, Default}}) when ?is_primitive_type(Type) ->
    {ok, xl_string:format("~p = xl_json_bindc:cast(?JSON_API, ?JSON_API:get_value(~p, J), ~p, ~p)", [Name, Name, Type, Default])};
generate_from_json_field({Name, {list, Type, Default}}) when ?is_primitive_type(Type) ->
    {ok, xl_string:format("~p = xl_json_bindc:cast(?JSON_API, ?JSON_API:get_value(~p, J), ~p, ~p)", [Name, Name, {list, Type}, Default])};
generate_from_json_field({Name, {enum, {list, Type, Default}, Enumeration}}) when ?is_primitive_type(Type) ->
    {ok, xl_string:format("~p = xl_json_bindc:cast(?JSON_API, ?JSON_API:get_value(~p, J), ~p, ~p)", [Name, Name, {enum, {list, Type}, Enumeration}, Default])};

generate_from_json_field({Name, {list, {Module, Type}, Default}}) when is_atom(Module), is_atom(Type) ->
    {ok, xl_string:format("~p = xl_json_bindc:cast(?JSON_API, ?JSON_API:get_value(~p, J), ~p, ~p)", [Name, Name, {list, {Module, Type}}, Default])};

generate_from_json_field({Name, {list, Type, Default}}) when is_atom(Type) ->
    {ok, xl_string:format("~p = xl_json_bindc:cast(?JSON_API, ?JSON_API:get_value(~p, J), {list, {?MODULE, ~p}}, ~p)", [Name, Name, Type, Default])};

generate_from_json_field({Name, {list, {Module, Type}}}) when is_atom(Module), is_atom(Type) ->
    generate_from_json_field({Name, {list, {Module, Type}, {required, Name}}});

generate_from_json_field({Name, {list, Type}}) when is_atom(Type) ->
    generate_from_json_field({Name, {list, Type, {required, Name}}});

generate_from_json_field({Name, Qualified = {option, {Module, Type}}}) when is_atom(Module), is_atom(Type) ->
    {ok, xl_string:format("~p = xl_json_bindc:cast(?JSON_API, ?JSON_API:get_value(~p, J), ~p, ~p)", [Name, Name, Qualified, undefined])};

generate_from_json_field({Name, {option, Type}}) when is_atom(Type) ->
    {ok, xl_string:format("~p = xl_json_bindc:cast(?JSON_API, ?JSON_API:get_value(~p, J), {option, {?MODULE, ~p}}, ~p)", [Name, Name, Type, undefined])};

generate_from_json_field({Name, {Type, undefined}}) when is_atom(Type) ->
    {ok, xl_string:format("~p = xl_json_bindc:cast(?JSON_API, ?JSON_API:get_value(~p, J), {?MODULE, ~p}, ~p)", [Name, Name, Type, undefined])};

generate_from_json_field({Name, Type}) when is_atom(Type) ->
    {ok, xl_string:format("~p = xl_json_bindc:cast(?JSON_API, ?JSON_API:get_value(~p, J), {?MODULE, ~p}, ~p)", [Name, Name, Type, {required, Name}])};

generate_from_json_field({Name, {Qualified = {Module, Type}, undefined}}) when is_atom(Module), is_atom(Type) ->
    {ok, xl_string:format("~p = xl_json_bindc:cast(?JSON_API, ?JSON_API:get_value(~p, J), ~p, ~p)", [Name, Name, Qualified, undefined])};

generate_from_json_field({Name, Qualified = {Module, Type}}) when is_atom(Module), is_atom(Type) ->
    {ok, xl_string:format("~p = xl_json_bindc:cast(?JSON_API, ?JSON_API:get_value(~p, J), ~p, ~p)", [Name, Name, Qualified, {required, Name}])};

generate_from_json_field(Field) -> {error, {dont_understand, Field}}.

% runtime functions

check_enumeration(Value, Enumeration) ->
    case lists:member(Value, Enumeration) of
        true -> Value;
        false -> error({illegal_enum_value, Value})
    end.

-spec(cast(module(), option_m:monad(any()), term(), any()) -> any()).
cast(_JsonApi, {ok, null}, _Type, _Default) -> undefined;

cast(_JsonApi, {ok, V}, {enum, atom, Enumeration}, _Default) -> check_enumeration(xl_convert:to(atom, V), Enumeration);
cast(_JsonApi, {ok, V}, {enum, {list, atom}, Enumeration}, _Default) when is_list(V) ->
    lists:map(fun(X) -> check_enumeration(xl_convert:to(atom, X), Enumeration) end, V);
cast(_JsonApi, {ok, V}, atom, _Default) -> xl_convert:to(atom, V);
cast(_JsonApi, {ok, V}, {list, atom}, _Default) -> lists:map(fun(X) -> xl_convert:to(atom, X) end, V);
cast(_JsonApi, {ok, V}, {option, atom}, _Default) -> {ok, xl_convert:to(atom, V)};

cast(_JsonApi, {ok, V}, {enum, string, Enumeration}, _Default) -> check_enumeration(V, Enumeration);
cast(_JsonApi, {ok, V}, {enum, {list, string}, Enumeration}, _Default) when is_list(V) ->
    lists:map(fun(X) -> check_enumeration(X, Enumeration) end, V);
cast(_JsonApi, {ok, V}, string, _Default) when is_binary(V) -> V;
cast(_JsonApi, {ok, V}, {list, string}, _Default) when is_list(V) -> V;
cast(_JsonApi, {ok, V}, {option, string}, _Default) when is_binary(V) -> {ok, V};

cast(_JsonApi, {ok, V}, {enum, binary, Enumeration}, _Default) -> check_enumeration(V, Enumeration);
cast(_JsonApi, {ok, V}, {enum, {list, binary}, Enumeration}, _Default) when is_list(V) ->
    lists:map(fun(X) -> check_enumeration(X, Enumeration) end, V);
cast(_JsonApi, {ok, V}, binary, _Default) when is_binary(V) -> V;
cast(_JsonApi, {ok, V}, {list, binary}, _Default) when is_list(V) -> V;
cast(_JsonApi, {ok, V}, {option, binary}, _Default) when is_binary(V) -> {ok, V};

cast(_JsonApi, {ok, V}, {enum, integer, Enumeration}, _Default) -> check_enumeration(V, Enumeration);
cast(_JsonApi, {ok, V}, {enum, {list, integer}, Enumeration}, _Default) when is_list(V) ->
    lists:map(fun(X) -> check_enumeration(X, Enumeration) end, V);
cast(_JsonApi, {ok, V}, integer, _Default) when is_integer(V) -> V;
cast(_JsonApi, {ok, V}, {list, integer}, _Default) when is_list(V) -> V;
cast(_JsonApi, {ok, V}, {option, integer}, _Default) when is_integer(V) -> {ok, V};

cast(_JsonApi, {ok, V}, {enum, float, Enumeration}, _Default) -> check_enumeration(V, Enumeration);
cast(_JsonApi, {ok, V}, {enum, {list, float}, Enumeration}, _Default) when is_list(V) ->
    lists:map(fun(X) -> check_enumeration(X, Enumeration) end, V);
cast(_JsonApi, {ok, V}, float, _Default) when is_float(V) -> V;
cast(_JsonApi, {ok, V}, {list, float}, _Default) when is_list(V) -> V;
cast(_JsonApi, {ok, V}, {option, float}, _Default) when is_float(V) -> {ok, V};

cast(_JsonApi, {ok, V}, boolean, _Default) when V == true; V == false -> V;
cast(_JsonApi, {ok, V}, {list, boolean}, _Default) when is_list(V) -> V;
cast(_JsonApi, {ok, V}, {option, boolean}, _Default) when V == true; V == false -> {ok, V};

cast(JsonApi, {ok, V}, any, _Default) -> JsonApi:to_abstract(V);
cast(JsonApi, {ok, V}, {list, any}, _Default) when is_list(V) -> [JsonApi:to_abstract(X) || X <- V];
cast(JsonApi, {ok, V}, {option, any}, _Default) -> {ok, JsonApi:to_abstract(V)};

cast(_JsonApi, {ok, V}, {list, {Module, Record}}, _Default) when is_list(V) -> [Module:from_json_(O, Record) || O <- V];
cast(_JsonApi, {ok, V}, {option, {Module, Record}}, _Default) -> {ok, Module:from_json_(V, Record)};
cast(_JsonApi, {ok, V}, {Module, Record}, _Default) -> Module:from_json_(V, Record);

cast(_JsonApi, undefined, _Type, E = {required, _}) -> error(E);

cast(_JsonApi, undefined, {option, _}, undefined) -> undefined;
cast(_JsonApi, undefined, {option, _}, Default) -> {ok, Default};
cast(_JsonApi, undefined, _Type, Default) -> Default;

cast(_JsonApi, X, Y, _Default) -> error({cannot_cast, {X, Y}}).

