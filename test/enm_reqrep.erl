%% -------------------------------------------------------------------
%%
%% enm_reqrep: test request/reply protocol for enm
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
-module(enm_reqrep).
-compile(export_all).

-include_lib("eunit/include/eunit.hrl").
-include("../include/enm.hrl").

-define(URL, #nn_inproc{addr="test"}).

reqrep_test_() ->
    {setup,
     fun enm:start_link/0,
     fun(_) -> enm:stop() end,
     [fun queuing/0,
      fun loadbal/0,
      fun resend/0,
      fun peer_unavailable/0,
      fun switch_to_peer/0]}.

queuing() ->
    {ok, Rep1} = enm:rep([{bind, ?URL}]),
    {ok, Req1} = enm:req([{active,false}, {connect,?URL}]),
    {ok, Req2} = enm:req([{connect, ?URL}]),
    ?assertMatch({error, efsm}, enm:recv(Req1)),
    ok = reqrep_active_true(Rep1, Req1, Req2),
    ok = reqrep_active_once(Rep1, Req1, Req2),
    ok = reqrep_passive(Rep1, Req1, Req2),
    ok = enm:close(Rep1),
    ok = enm:close(Req1),
    ok = enm:close(Req2),
    ok.

reqrep_active_true(Rep1, Req1, Req2) ->
    ok = enm:setopts(Rep1, [{active,true}]),
    ok = enm:setopts(Req1, [{active,true}]),
    ok = enm:setopts(Req2, [{active,true}]),
    ok = reqrep_active(Rep1, Req1, Req2),
    ?assertMatch({ok, [{active,true}]}, enm:getopts(Rep1, [active])),
    ?assertMatch({ok, [{active,true}]}, enm:getopts(Req1, [active])),
    ?assertMatch({ok, [{active,true}]}, enm:getopts(Req2, [active])),
    ok.

reqrep_active_once(Rep1, Req1, Req2) ->
    ok = enm:setopts(Rep1, [{active,true}]),
    ok = enm:setopts(Req1, [{active,true}]),
    ok = enm:setopts(Req2, [{active,true}]),
    FRep1 = fun() -> ok = enm:setopts(Rep1, [{active,once}]), Rep1 end,
    FReq1 = fun() -> ok = enm:setopts(Req1, [{active,once}]), Req1 end,
    FReq2 = fun() -> ok = enm:setopts(Req2, [{active,once}]), Req2 end,
    ok = reqrep_active(FRep1, FReq1, FReq2),
    ?assertMatch({ok, [{active,once}]}, enm:getopts(Rep1, [active])),
    ?assertMatch({ok, [{active,true}]}, enm:getopts(Req1, [active])),
    ?assertMatch({ok, [{active,false}]}, enm:getopts(Req2, [active])),
    ok.

reqrep_active(Rep1, _Req1, Req2) ->
    Data = <<"reqrep active data">>,
    Seq = [{send,Req2}, {recv,Rep1}, {send,Rep1}, {recv,Req2}],
    true = lists:all(fun(ok) -> true end, do_send_recv(Seq, Data)),
    ok.

reqrep_passive(Rep1, Req1, Req2) ->
    ok = enm:setopts(Rep1, [{active,false}]),
    ok = enm:setopts(Req1, [{active,false}]),
    ok = enm:setopts(Req2, [{active,false}]),
    Data = <<"reqrep passive data">>,
    ok = enm:send(Req2, Data),
    ?assertMatch({ok, Data}, enm:recv(Rep1)),
    ok = enm:send(Rep1, Data),
    ?assertMatch({ok, Data}, enm:recv(Req2)),
    ok.

loadbal() ->
    {ok, Req1} = enm:req([{bind, ?URL}]),
    {ok, Rep1} = enm:rep([{connect, ?URL}]),
    {ok, Rep2} = enm:rep([{connect, ?URL}]),
    ok = loadbal_active_true(Req1, Rep1, Rep2),
    ok = loadbal_active_once(Req1, Rep1, Rep2),
    ok = loadbal_passive(Req1, Rep1, Rep2),
    ok = enm:close(Rep2),
    ok = enm:close(Rep1),
    ok = enm:close(Req1),
    ok.

loadbal_active_true(Req1, Rep1, Rep2) ->
    ok = enm:setopts(Req1, [{active,true}]),
    ok = enm:setopts(Rep1, [{active,true}]),
    ok = enm:setopts(Rep2, [{active,true}]),
    ok = loadbal_active(Req1, Rep1, Rep2),
    ?assertMatch({ok, [{active,true}]}, enm:getopts(Req1, [active])),
    ?assertMatch({ok, [{active,true}]}, enm:getopts(Rep1, [active])),
    ?assertMatch({ok, [{active,true}]}, enm:getopts(Rep2, [active])),
    ok.

loadbal_active_once(Req1, Rep1, Rep2) ->
    ok = enm:setopts(Req1, [{active,true}]),
    ok = enm:setopts(Rep1, [{active,true}]),
    ok = enm:setopts(Rep2, [{active,true}]),
    FReq1 = fun() -> ok = enm:setopts(Req1, [{active,once}]), Req1 end,
    FRep1 = fun() -> ok = enm:setopts(Rep1, [{active,once}]), Rep1 end,
    FRep2 = fun() -> ok = enm:setopts(Rep2, [{active,once}]), Rep2 end,
    ok = loadbal_active(FReq1, FRep1, FRep2),
    ?assertMatch({ok, [{active,false}]}, enm:getopts(Req1, [active])),
    ?assertMatch({ok, [{active,once}]}, enm:getopts(Rep1, [active])),
    ?assertMatch({ok, [{active,once}]}, enm:getopts(Rep2, [active])),
    ok.

loadbal_active(Req1, Rep1, Rep2) ->
    Data = <<"reqrep active data">>,
    Seq = [{send,Req1}, {recv,Rep1}, {send,Rep1}, {recv,Req1},
           {send,Req1}, {recv,Rep2}, {send,Rep2}, {recv,Req1}],
    true = lists:all(fun(ok) -> true end, do_send_recv(Seq, Data)),
    ok.

loadbal_passive(Req1, Rep1, Rep2) ->
    ok = enm:setopts(Req1, [{active,false}]),
    ok = enm:setopts(Rep1, [{active,false}]),
    ok = enm:setopts(Rep2, [{active,false}]),
    Data = <<"reqrep passive data">>,
    ok = enm:send(Req1, Data),
    ?assertMatch({ok, Data}, enm:recv(Rep1)),
    ok = enm:send(Rep1, Data),
    ?assertMatch({ok, Data}, enm:recv(Req1)),
    ok = enm:send(Req1, Data),
    ?assertMatch({ok, Data}, enm:recv(Rep2)),
    ok = enm:send(Rep2, Data),
    ?assertMatch({ok, Data}, enm:recv(Req1)),
    ok.

do_send_recv(ReqReps, Data) ->
    do_send_recv(ReqReps, Data, []).
do_send_recv([], _, Acc) ->
    Acc;
do_send_recv([{SR,ReqRep}|ReqReps], Data, Acc) when is_function(ReqRep) ->
    do_send_recv([{SR,ReqRep()}|ReqReps], Data, Acc);
do_send_recv([{send,ReqRep}|ReqReps], Data, Acc) ->
    do_send_recv(ReqReps, Data, [enm:send(ReqRep, Data)|Acc]);
do_send_recv([{recv,ReqRep}|ReqReps], Data, Acc) ->
    {ok, [{type,Type}]} = enm:getopts(ReqRep, [type]),
    receive
        {Type,ReqRep,Data} ->
            do_send_recv(ReqReps, Data, [ok|Acc]);
        Msg -> error({unexpected_data, Msg})
    after
        2000 ->
            error(reqrep_timeout)
    end.

resend() ->
    {ok, Rep1} = enm:rep([{active,false}, {bind,?URL}]),
    {ok, Req1} = enm:req([{connect, ?URL}]),
    ResendIvl = 100,
    ok = enm:setopts(Req1, [{resend_ivl, ResendIvl}]),
    Data = <<"resend">>,
    ok = enm:send(Req1, Data),
    ?assertMatch({ok, Data}, enm:recv(Rep1)),
    ?assertMatch({ok, Data}, enm:recv(Rep1)),
    ok = enm:close(Req1),
    ok = enm:close(Rep1),
    ok.

peer_unavailable() ->
    {ok, Req1} = enm:req([{connect, ?URL}]),
    Data = <<"peer unavailable">>,
    ok = enm:send(Req1, Data),
    {ok, Rep1} = enm:rep([{active,false}]),
    {ok, _} = enm:bind(Rep1, ?URL),
    Timeout = 200,
    ?assertMatch({ok, Data}, enm:recv(Rep1, Timeout)),
    ok = enm:close(Rep1),
    ok = enm:close(Req1),
    ok.

switch_to_peer() ->
    {ok, Req1} = enm:req([{bind, ?URL}]),
    {ok, Rep1} = enm:rep([{active,false}, {connect, ?URL}]),
    {ok, Rep2} = enm:rep([{active,false}, {connect, ?URL}]),
    Timeout = 200,
    Data = <<"switch to other peer">>,
    ok = enm:send(Req1, Data),
    ?assertMatch({ok, Data}, enm:recv(Rep1, Timeout)),
    ok = enm:close(Rep1),
    ?assertMatch({ok, Data}, enm:recv(Rep2, Timeout)),
    ok = enm:send(Rep2, "reply"),
    ok = receive
             {nnreq, Req1, <<"reply">>} ->
                 ok;
             Msg ->
                 error({unexpected_reply, Msg})
         after
             1000 ->
                 error(reply_timeout)
         end,
    ok.
