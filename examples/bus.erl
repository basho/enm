%% -------------------------------------------------------------------
%%
%% bus: example of enm bus support
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
-module(bus).
-export([start/0]).

-define(COUNT, 4).

start() ->
    enm:start_link(),
    UrlBase = "inproc://bus",
    Buses = connect_buses(UrlBase),
    Pids = send_and_receive(Buses, self()),
    wait_for_pids(Pids),
    enm:stop().

connect_buses(UrlBase) ->
    connect_buses(UrlBase, lists:seq(1,?COUNT), []).
connect_buses(UrlBase, [1=Node|Nodes], Buses) ->
    Url = make_url(UrlBase, Node),
    {ok,Bus} = enm:bus([{bind,Url},{active,false}]),
    {ok,_} = enm:connect(Bus, make_url(UrlBase, 2)),
    {ok,_} = enm:connect(Bus, make_url(UrlBase, 3)),
    connect_buses(UrlBase, Nodes, [{Bus,Node}|Buses]);
connect_buses(UrlBase, [?COUNT=Node|Nodes], Buses) ->
    Url = make_url(UrlBase, Node),
    {ok,Bus} = enm:bus([{bind,Url},{active,false}]),
    {ok,_} = enm:connect(Bus, make_url(UrlBase, 1)),
    connect_buses(UrlBase, Nodes, [{Bus,Node}|Buses]);
connect_buses(UrlBase, [Node|Nodes], Buses) ->
    Url = make_url(UrlBase, Node),
    {ok,Bus} = enm:bus([{bind,Url},{active,false}]),
    Urls = [make_url(UrlBase,N) || N <- lists:seq(Node+1,?COUNT)],
    [{ok,_} = enm:connect(Bus,U) || U <- Urls],
    connect_buses(UrlBase, Nodes, [{Bus,Node}|Buses]);
connect_buses(_, [], Buses) ->
    Buses.

send_and_receive(Buses, Parent) ->
    send_and_receive(Buses, Parent, []).
send_and_receive([{Bus,Id}|Buses], Parent, Acc) ->
    Pid = spawn_link(fun() -> bus(Bus, Id, Parent) end),
    send_and_receive(Buses, Parent, [Pid|Acc]);
send_and_receive([], _, Acc) ->
    Acc.

bus(Bus, Id, Parent) ->
    Name = "node"++integer_to_list(Id),
    io:format("node ~w sending \"~s\"~n", [Id, Name]),
    ok = enm:send(Bus, Name),
    collect(Bus, Id, Parent).

collect(Bus, Id, Parent) ->
    case enm:recv(Bus, 1000) of
        {ok,Data} ->
            io:format("node ~w received \"~s\"~n", [Id, Data]),
            collect(Bus, Id, Parent);
        {error,etimedout} ->
            Parent ! {done, self(), Bus}
    end.

wait_for_pids([Pid|Pids]) ->
    receive
        {done,Pid,Bus} ->
            enm:close(Bus),
            wait_for_pids(Pids)
    end;
wait_for_pids([]) ->
    ok.

make_url(Base,N) ->
    Base++integer_to_list(N).
