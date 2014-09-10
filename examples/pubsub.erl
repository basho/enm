%% -------------------------------------------------------------------
%%
%% pubsub: example of enm pub/sub support
%%
%% Copyright (c) 2014 Basho Technologies, Inc.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------
-module(pubsub).
-export([start/0]).

-define(COUNT, 3).

start() ->
    enm:start_link(),
    Url = "inproc://pubsub",
    Pub = pub(Url),
    collect(subs(Url, self())),
    enm:close(Pub),
    enm:stop().

pub(Url) ->
    {ok,Pub} = enm:pub([{bind,Url}]),
    spawn_link(fun() -> pub(Pub, ?COUNT) end),
    Pub.
pub(_, 0) ->
    ok;
pub(Pub, Count) ->
    Now = httpd_util:rfc1123_date(),
    io:format("publishing date \"~s\"~n", [Now]),
    ok = enm:send(Pub, ["DATE: ", Now]),
    timer:sleep(1000),
    pub(Pub, Count-1).

subs(Url, Parent) ->
    subs(Url, Parent, ?COUNT, []).
subs(_, _, 0, Acc) ->
    Acc;
subs(Url, Parent, Count, Acc) ->
    {ok, Sub} = enm:sub([{connect,Url},{subscribe,"DATE:"},{active,false}]),
    Name = "Subscriber" ++ integer_to_list(Count),
    spawn_link(fun() -> sub(Sub, Parent, Name) end),
    subs(Url, Parent, Count-1, [Name|Acc]).
sub(Sub, Parent, Name) ->
    case enm:recv(Sub, 2000) of
        {ok,Data} ->
            io:format("~s received \"~s\"~n", [Name, Data]),
            sub(Sub, Parent, Name);
        {error,etimedout} ->
            enm:close(Sub),
            Parent ! {done, Name},
            ok
    end.

collect([Sub|Subs]) ->
    receive
        {done,Sub} ->
            collect(Subs)
    end;
collect([]) ->
    ok.
