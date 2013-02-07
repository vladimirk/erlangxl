-module(xl_json_tests).

-include_lib("eunit/include/eunit.hrl").

to_json_test() ->
    ?assertEqual("\"\"", xl_json:to_json(<<>>)),
    ?assertEqual("\"string\"", xl_json:to_json(<<"string">>)),
    ?assertEqual("\"stri\\ng\"", xl_json:to_json(<<"stri\ng">>)),
    ?assertEqual("1", xl_json:to_json(1)),
    ?assertEqual("1.2", xl_json:to_json(1.2)),
    ?assertEqual("true", xl_json:to_json(true)),
    ?assertEqual("false", xl_json:to_json(false)),
    ?assertEqual("[]", xl_json:to_json([])),
    ?assertEqual("[1,2,\"3\",false,null]",
        xl_json:to_json([1, 2, <<"3">>, false, undefined])),
    ?assertEqual("[1,[1,2]]", xl_json:to_json([1, [1, 2]])),
    ?assertEqual("{\"a\":[1],\"b\":{\"c\":null}}",
        xl_json:to_json([{"a", [1]}, {b, [{c, undefined}]}])).

from_json_test() ->
    ?assertEqual({ok, true}, xl_json:from_json("true")),
    ?assertEqual({ok, [{a, [{b, [1, 2]}]}]},
        xl_json:from_json("{\"a\":{\"b\":[1,2]}}")),
    ?assertEqual({ok, [{a, undefined}]},
        xl_json:from_json("{\"a\":null}")),
    ?assertEqual({ok, [<<"1aa">>, 1]},
        xl_json:from_json("[\"1aa\", 1]")),
    ?assertEqual({ok, [{keys, [<<"user1">>]}, {data, []}]},
        xl_json:from_json(<<"{\"keys\":[\"user1\"],\"data\":[]}">>)).


-record(r, {a, b, c, d, aa, bb, cc, dd, aaa, bbb, ccc, ddd}).
performance_comparison_record_fill_test() ->
    {ok, Doc} = xl_json_jiffy:from_json("{\"a\":1, \"b\":\"2\", \"c\":true, \"d\":1.5,"
    " \"aa\":1, \"bb\":\"2\", \"cc\":true, \"dd\":1.5, \"aaa\":1, \"bbb\":\"2\", \"ccc\":true, \"ddd\":1.5}"),
    xl_eunit:performance(json_bind_via_lists, fun(_) ->
        #r{
            a = xl_json_jiffy:get_value(a, Doc),
            b = xl_json_jiffy:get_value(b, Doc),
            c = xl_json_jiffy:get_value(c, Doc),
            d = xl_json_jiffy:get_value(d, Doc),
            aa = xl_json_jiffy:get_value(aa, Doc),
            bb = xl_json_jiffy:get_value(bb, Doc),
            cc = xl_json_jiffy:get_value(cc, Doc),
            dd = xl_json_jiffy:get_value(dd, Doc),
            aaa = xl_json_jiffy:get_value(aaa, Doc),
            bbb = xl_json_jiffy:get_value(bbb, Doc),
            ccc = xl_json_jiffy:get_value(ccc, Doc),
            ddd = xl_json_jiffy:get_value(ddd, Doc)
        }
    end, 10000),
    F  = fun
        (<<"a">>, Value, T) -> T#r{a = Value};
        (<<"b">>, Value, T) -> T#r{b = Value};
        (<<"c">>, Value, T) -> T#r{c = Value};
        (<<"d">>, Value, T) -> T#r{d = Value};
        (<<"aa">>, Value, T) -> T#r{aa = Value};
        (<<"bb">>, Value, T) -> T#r{bb = Value};
        (<<"cc">>, Value, T) -> T#r{cc = Value};
        (<<"dd">>, Value, T) -> T#r{dd = Value};
        (<<"aaa">>, Value, T) -> T#r{aa = Value};
        (<<"bbb">>, Value, T) -> T#r{bb = Value};
        (<<"ccc">>, Value, T) -> T#r{cc = Value};
        (<<"ddd">>, Value, T) -> T#r{dd = Value}
    end,
    xl_eunit:performance(json_bind_via_callback, fun(_) ->
        xl_json_jiffy:bind(F, #r{}, Doc)
    end, 10000).
