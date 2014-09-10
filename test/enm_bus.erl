%% -------------------------------------------------------------------
%%
%% enm_bus: test bus protocol for enm
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
-module(enm_bus).
-compile(export_all).

-include_lib("eunit/include/eunit.hrl").
-include("../include/enm.hrl").

-define(URLA, #nn_inproc{addr="a"}).
-define(URLB, #nn_inproc{addr="b"}).

bus_test_() ->
    {setup,
     fun enm:start_link/0,
     fun(_) -> enm:stop() end,
     fun bus/0}.

bus() ->
    {ok, Bus1} = enm:bus([{bind, ?URLA}]),
    {ok, Bus2} = enm:bus([{bind, ?URLB}]),
    {ok, _} = enm:connect(Bus2, ?URLA),
    {ok, Bus3} = enm:bus(),
    {ok, _} = enm:connect(Bus3, ?URLA),
    {ok, _} = enm:connect(Bus3, ?URLB),
    ok = bus_active_true(Bus1, Bus2, Bus3),
    ok = bus_active_once(Bus1, Bus2, Bus3),
    ok = bus_passive(Bus1, Bus2, Bus3),
    ok = enm:close(Bus1),
    ok = enm:close(Bus2),
    ok = enm:close(Bus3),
    ok.

bus_active_true(Bus1, Bus2, Bus3) ->
    ok = enm:setopts(Bus1, [{active,true}]),
    ok = enm:setopts(Bus2, [{active,true}]),
    ok = enm:setopts(Bus3, [{active,true}]),
    ok = bus_active(Bus1, Bus2, Bus3),
    ?assertMatch({ok, [{active,true}]}, enm:getopts(Bus1, [active])),
    ?assertMatch({ok, [{active,true}]}, enm:getopts(Bus2, [active])),
    ?assertMatch({ok, [{active,true}]}, enm:getopts(Bus3, [active])),
    ok.

bus_active_once(Bus1, Bus2, Bus3) ->
    ok = enm:setopts(Bus1, [{active,true}]),
    ok = enm:setopts(Bus2, [{active,true}]),
    ok = enm:setopts(Bus3, [{active,true}]),
    FBus1 = fun() -> ok = enm:setopts(Bus1, [{active,once}]), Bus1 end,
    FBus2 = fun() -> ok = enm:setopts(Bus2, [{active,once}]), Bus2 end,
    FBus3 = fun() -> ok = enm:setopts(Bus3, [{active,once}]), Bus3 end,
    ok = bus_active(FBus1, FBus2, FBus3),
    ?assertMatch({ok, [{active,false}]}, enm:getopts(Bus1, [active])),
    ?assertMatch({ok, [{active,false}]}, enm:getopts(Bus2, [active])),
    ?assertMatch({ok, [{active,false}]}, enm:getopts(Bus3, [active])),
    ok.

bus_active(Bus1, Bus2, Bus3) ->
    Data1 = <<"data packet 1">>,
    Data2 = <<"data packet 2">>,
    Data3 = <<"data packet 3">>,
    Buses = [Bus1,Bus2,Bus3],
    [B1,B2,B3] = [if is_function(B) -> B(); true -> B end || B <- Buses],
    ok = enm:send(B1, Data1),
    ok = enm:send(B2, Data2),
    ok = enm:send(B3, Data3),
    Seq = [{Bus1,[Data2,Data3]}, {Bus2,[Data1,Data3]}, {Bus3,[Data1,Data2]}],
    Results = do_send_recv(Seq),
    ?assertMatch(6, length(Results)),
    true = lists:all(fun(ok) -> true end, Results),
    ok.

bus_passive(Bus1, Bus2, Bus3) ->
    ok = enm:setopts(Bus1, [{active,false}]),
    ok = enm:setopts(Bus2, [{active,false}]),
    ok = enm:setopts(Bus3, [{active,false}]),
    Data1 = <<"passive data packet 1">>,
    Data2 = <<"passive data packet 2">>,
    Data3 = <<"passive data packet 3">>,
    ok = enm:send(Bus1, Data1),
    ok = enm:send(Bus2, Data2),
    ok = enm:send(Bus3, Data3),
    ?assertMatch({ok, Data2}, enm:recv(Bus1)),
    ?assertMatch({ok, Data3}, enm:recv(Bus1)),
    ?assertMatch({ok, Data1}, enm:recv(Bus2)),
    ?assertMatch({ok, Data3}, enm:recv(Bus2)),
    ?assertMatch({ok, Data1}, enm:recv(Bus3)),
    ?assertMatch({ok, Data2}, enm:recv(Bus3)),
    ok.

do_send_recv(Seq) ->
    do_send_recv(Seq, []).
do_send_recv([], Acc) ->
    lists:flatten(Acc);
do_send_recv([{Bus,Packets}|Seq], Acc) ->
    Res = [begin
               B = if
                       is_function(Bus) -> Bus();
                       true -> Bus
                   end,
               receive
                   {nnbus, B, Data} ->
                       ok
               after
                   1000 ->
                       error(bus_timeout)
               end
           end || Data <- Packets],
    do_send_recv(Seq, [Res|Acc]).
