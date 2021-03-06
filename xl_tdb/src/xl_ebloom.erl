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
-module(xl_ebloom).
-author("volodymyr.kyrychenko@strikead.com").

%% API
-export([new/1, insert/2, contains/2]).
-export_type([ref/0]).

-opaque(ref() :: reference()).

-spec(new(pos_integer() | [term()]) -> {ok, ref()}).
new(Size) when is_integer(Size) -> ebloom:new(Size, 0.01, element(3, now()));
new(List) ->
    case new(length(List)) of
        {ok, Ref} ->
            lists:foreach(fun(X) ->
                ok = insert(X, Ref)
            end, List),
            {ok, Ref};
        E -> E
    end.

-spec(insert(term(), ref()) -> ok).
insert(X, Bloom) when is_binary(X) -> ebloom:insert(Bloom, X);
insert(X, Bloom) -> insert(term_to_binary(X), Bloom).

-spec(contains(term(), ref()) -> boolean()).
contains(X, Bloom) when is_binary(X) -> ebloom:contains(Bloom, X);
contains(X, Bloom) -> contains(term_to_binary(X), Bloom).


