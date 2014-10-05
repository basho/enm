%% -------------------------------------------------------------------
%%
%% enm_recv: recv tests for enm
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
-module(enm_recv).
-compile(export_all).

-include_lib("eunit/include/eunit.hrl").
-include("../include/enm.hrl").

-define(URL, #nn_inproc{addr="foo"}).

recv_test_() ->
    {setup,
     fun enm:start_link/0,
     fun(_) -> enm:stop() end,
     fun() ->
             {ok,S} = enm:pair([{active, false}, {bind, ?URL}]),
             {ok,R} = enm:pair([{active, false}, {connect, ?URL}]),
             Self = self(),
             Data1 = <<"this is for receiver 1">>,
             Rcv1 = spawn_link(fun() -> receiver(R, Data1, Self) end),
             Data2 = <<"this is for receiver 2">>,
             Rcv2 = spawn_link(fun() -> receiver(R, Data2, Self) end),
             timer:sleep(500),
             ok = enm:send(S, Data1),
             ok = enm:send(S, Data2),
             ?assertMatch([ok,ok], [receive
                                        {Rcv1, Data1} -> ok;
                                        {Rcv2, Data2} -> ok;
                                        _ -> fail
                                    after
                                        3000 -> timeout
                                    end || _ <- [Data1, Data2]]),
             ok = enm:close(R),
             ok = enm:close(S),
             ok
     end}.

receiver(R, Data, Pid) ->
    ?assertMatch({ok, Data}, enm:recv(R, 2000)),
    Pid ! {self(), Data},
    ok.
