%%  Copyright (c) 2012-2013
%%  StrikeAd LLC http://www.strikead.com
%%
%%  All rights reserved.
%%
%%  Redistribution and use in source and binary forms, with or without
%%  modification, are permitted provided that the following conditions are met:
%%
%%      Redistributions of source code must retain the above copyright
%%  notice, this list of conditions and the following disclaimer.
%%      Redistributions in binary form must reproduce the above copyright
%%  notice, this list of conditions and the following disclaimer in the
%%  documentation and/or other materials provided with the distribution.
%%      Neither the name of the StrikeAd LLC nor the names of its
%%  contributors may be used to endorse or promote products derived from
%%  this software without specific prior written permission.
%%
%%  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
%%  IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
%%  TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
%%  PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
%%  HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
%%  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
%%  TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
%%  PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
%%  LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
%%  NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
%%  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
-module(xl_tdb_storage).

-compile({parse_transform, do}).

-export([load/3, store/3, delete/2]).

-spec(load(file:name(), pos_integer(), [{pos_integer(), fun((term()) -> term())}]) -> error_m:monad([term()])).
load(Location, Version, Migrations) ->
    VersionFile = filename:join(Location, ".version"),
    do([error_m ||
        ApplicableMigrations <- prepare_migrations(VersionFile, Version, Migrations),
        xl_file:mkdirs(Location),
        Files <- xl_file:list_dir(Location, "*.tdb"),
        Objects <- xl_lists:emap(fun(F) ->
            Filename = filename:join(Location, F),
            do([error_m ||
                Content <- xl_file:read_file(Filename),
                Object <- return(migrate(binary_to_term(Content), ApplicableMigrations)),
                xl_file:write_file(Filename, term_to_binary(Object)),
                return(Object)
            ])
        end, lists:sort(Files)),
        xl_file:write_term(VersionFile, {version, Version}),
        return(Objects)
    ]).

-spec(store(file:name(), xl_string:iostring(), term()) -> error_m:monad(ok)).
store(Location, Id, X) ->
    xl_file:write_file(xl_string:join([Location, "/", Id, ".tdb"]), term_to_binary(X)).

-spec(delete(file:name(), xl_string:iostring()) -> error_m:monad(ok)).
delete(Location, Id) ->
    xl_file:delete(xl_string:join([Location, "/", Id, ".tdb"])).

%% @hidden
migrate(Term, Migrations) -> lists:foldl(fun({_, M}, T) -> M(T) end, Term, Migrations).

%% @hidden
prepare_migrations(VersionFile, Version, Migrations) ->
    do([error_m ||
        Exists <- xl_file:exists(VersionFile),
        [{version, OldVersion}] <-
            case Exists of
                true -> xl_file:read_terms(VersionFile);
                false -> return([{version, 0}])
            end,
        return(lists:dropwhile(fun({V, _M}) -> V =< OldVersion end, Migrations))
    ]).
