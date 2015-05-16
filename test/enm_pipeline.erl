%% -------------------------------------------------------------------
%%
%% enm_pipeline: test pipeline protocol for enm
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
-module(enm_pipeline).
-compile(export_all).

-include_lib("eunit/include/eunit.hrl").
-include("../include/enm.hrl").

-define(URL, #nn_inproc{addr="a"}).

pipeline_test_() ->
    {setup,
     fun enm:start_link/0,
     fun(_) -> enm:stop() end,
     [fun fan_out/0,
      fun fan_in/0,
      fun no_server/0]}.

fan_out() ->
    {ok, Push1} = enm:push(),
    {ok, _} = enm:bind(Push1, ?URL),
    {ok, Pull1} = enm:pull(),
    {ok, _} = enm:connect(Pull1, ?URL),
    {ok, Pull2} = enm:pull(),
    {ok, _} = enm:connect(Pull2, ?URL),
    ok = out_active_true_pipeline(Push1, Pull1, Pull2),
    ok = out_active_once_pipeline(Push1, Pull1, Pull2),
    ok = out_passive_pipeline(Push1, Pull1, Pull2),
    [ok,ok,ok] = [try enm:setopts(Push1, [{active,Active}])
                  catch error:badarg -> ok end || Active <- [true,false,once]],
    ok = enm:close(Push1),
    ok = enm:close(Pull1),
    ok = enm:close(Pull2),
    ok.

fan_in() ->
    {ok, Pull1} = enm:pull(),
    {ok, _} = enm:bind(Pull1, ?URL),
    {ok, Push1} = enm:push(),
    {ok, _} = enm:connect(Push1, ?URL),
    {ok, Push2} = enm:push(),
    {ok, _} = enm:connect(Push2, ?URL),
    ok = in_active_true_pipeline(Pull1, Push1, Push2),
    ok = in_active_once_pipeline(Pull1, Push1, Push2),
    ok = in_passive_pipeline(Pull1, Push1, Push2),
    ok = enm:close(Pull1),
    ok = enm:close(Push1),
    ok = enm:close(Push2),
    ok.

out_active_true_pipeline(Push1, Pull1, Pull2) ->
    ok = enm:setopts(Pull1, [{active,true}]),
    ok = enm:setopts(Pull2, [{active,true}]),
    ok = out_active_push_pull(Push1, Pull1, Pull2),
    ?assertMatch({ok, [{active,true}]}, enm:getopts(Pull1, [active])),
    ?assertMatch({ok, [{active,true}]}, enm:getopts(Pull2, [active])),
    ok.

out_active_once_pipeline(Push1, Pull1, Pull2) ->
    ok = enm:setopts(Pull1, [{active,once}]),
    ok = enm:setopts(Pull2, [{active,once}]),
    ok = out_active_push_pull(Push1, Pull1, Pull2),
    ?assertMatch({ok, [{active,false}]}, enm:getopts(Pull1, [active])),
    ?assertMatch({ok, [{active,false}]}, enm:getopts(Pull2, [active])),
    ok.

out_passive_pipeline(Push1, Pull1, Pull2) ->
    Data = <<"passive request">>,
    ok = enm:setopts(Pull1, [{active,false}]),
    ok = enm:setopts(Pull2, [{active,false}]),
    ok = enm:send(Push1, Data),
    ok = enm:send(Push1, Data),
    ?assertMatch({ok, Data}, enm:recv(Pull1)),
    ?assertMatch({ok, Data}, enm:recv(Pull2)),
    ok.

out_active_push_pull(Push1, Pull1, Pull2) ->
    Data = <<"active pushpull">>,
    ok = enm:send(Push1, Data),
    ok = enm:send(Push1, Data),
    true = lists:all(fun(ok) -> true end, do_pull([Pull1, Pull2], Data)),
    ok.

in_active_true_pipeline(Pull1, Push1, Push2) ->
    ok = enm:setopts(Pull1, [{active,true}]),
    ok = in_active_push_pull(Pull1, Push1, Push2),
    ?assertMatch({ok, [{active,true}]}, enm:getopts(Pull1, [active])),
    ok.

in_active_once_pipeline(Pull1, Push1, Push2) ->
    F = fun() -> ok = enm:setopts(Pull1, [{active,once}]), Pull1 end,
    ok = in_active_push_pull(F, Push1, Push2),
    ?assertMatch({ok, [{active,false}]}, enm:getopts(Pull1, [active])),
    ok.

in_passive_pipeline(Pull1, Push1, Push2) ->
    Data = <<"passive request">>,
    ok = enm:setopts(Pull1, [{active,false}]),
    ok = enm:send(Push1, Data),
    ok = enm:send(Push2, Data),
    ?assertMatch({ok, Data}, enm:recv(Pull1)),
    ?assertMatch({ok, Data}, enm:recv(Pull1)),
    ok.

in_active_push_pull(Pull1, Push1, Push2) ->
    Data = <<"active pushpull">>,
    ok = enm:send(Push1, Data),
    ok = enm:send(Push2, Data),
    true = lists:all(fun(ok) -> true end, do_pull([Pull1, Pull1], Data)),
    ok.

do_pull(Pulls, Data) ->
    do_pull(Pulls, Data, []).
do_pull([], _, Acc) ->
    Acc;
do_pull([Pull|Pulls], Data, Acc) when is_function(Pull) ->
    do_pull([Pull()|Pulls], Data, Acc);
do_pull([_|Pulls], Data, Acc) ->
    receive
        {nnpull, _, Data} ->
            do_pull(Pulls, Data, [ok|Acc]);
        BadPull ->
            error({unexpected_push, BadPull})
    after
        2000 ->
            error(pull_timeout)
    end.

no_server() ->
    %% This test checks that attempts to push to a TCP endpoint that's not
    %% there fails (github enm issue #7). The test requires the remote
    %% endpoint to not have anything listening and accepting, so the
    %% following fold attempts to find such an endpoint. The test won't
    %% work if something actually answers at the endpoint the fold chooses.
    Port = (catch lists:foldl(
                    fun(P, _) ->
                            case gen_tcp:connect("localhost", P, []) of
                                {error, econnrefused} ->
                                    throw(P);
                                {ok, S} ->
                                    gen_tcp:close(S),
                                    P;
                                _ ->
                                    P
                            end
                    end, ok, lists:seq(47000,60000))),
    Url = "tcp://localhost:"++integer_to_list(Port),
    {ok,Push} = enm:push([{connect,Url},list]),
    enm:send(Push, "sending the first message"),
    ?assertMatch({error,closed}, enm:send(Push, "sending the second message")),
    ok.
