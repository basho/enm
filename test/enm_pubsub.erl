%% -------------------------------------------------------------------
%%
%% enm_pubsub: test pub/sub protocol for enm
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
-module(enm_pubsub).
-compile(export_all).

-include_lib("eunit/include/eunit.hrl").
-include("../include/enm.hrl").

-define(URL, #nn_inproc{addr="a"}).

pubsub_test_() ->
    {setup,
     fun enm:start_link/0,
     fun(_) -> enm:stop() end,
     [fun one_pub/0,
      fun two_pub/0,
      fun check_sub_filter/0]}.

one_pub() ->
    {ok, Pub1} = enm:pub(),
    {ok, _} = enm:bind(Pub1, ?URL),
    {ok, Sub1} = enm:sub(),
    ok = enm:setopts(Sub1, [{subscribe, ""}]),
    {ok, _} = enm:connect(Sub1, ?URL),
    {ok, Sub2} = enm:sub(),
    ok = enm:setopts(Sub2, [{subscribe, ""}]),
    {ok, _} = enm:connect(Sub2, ?URL),
    ok = one_pub_active_true(Pub1, Sub1, Sub2),
    ok = one_pub_active_once(Pub1, Sub1, Sub2),
    ok = one_pub_passive(Pub1, Sub1, Sub2),
    ok = enm:setopts(Sub2, [{unsubscribe, ""}]),
    ok = enm:close(Sub2),
    ok = enm:close(Sub1),
    ok = enm:close(Pub1),
    ok.

one_pub_active_true(Pub1, Sub1, Sub2) ->
    ok = enm:setopts(Sub1, [{active,true}]),
    ok = enm:setopts(Sub2, [{active,true}]),
    ok = one_pub_active(Pub1, Sub1, Sub2),
    ?assertMatch({ok, [{active,true}]}, enm:getopts(Sub1, [active])),
    ?assertMatch({ok, [{active,true}]}, enm:getopts(Sub2, [active])),
    ok.

one_pub_active_once(Pub1, Sub1, Sub2) ->
    ok = enm:setopts(Sub1, [{active,once}]),
    ok = enm:setopts(Sub2, [{active,once}]),
    ok = one_pub_active(Pub1, Sub1, Sub2),
    ?assertMatch({ok, [{active,false}]}, enm:getopts(Sub1, [active])),
    ?assertMatch({ok, [{active,false}]}, enm:getopts(Sub2, [active])),
    ok.

one_pub_active(Pub1, Sub1, Sub2) ->
    Data = <<"some important information for subscribers">>,
    ok = enm:send(Pub1, Data),
    true = lists:all(fun(ok) -> true end, do_sub([Sub1, Sub2], Data)),
    ok.

one_pub_passive(Pub1, Sub1, Sub2) ->
    ok = enm:setopts(Sub1, [{active,false}]),
    ok = enm:setopts(Sub2, [{active,false}]),
    Data = <<"some important information for subscribers">>,
    ok = enm:send(Pub1, Data),
    {ok, Data} = enm:recv(Sub1),
    {ok, Data} = enm:recv(Sub2),
    ok.

two_pub() ->
    {ok,Sub1} = enm:sub(),
    ok = enm:setopts(Sub1, [{subscribe,""}]),
    {ok,_} = enm:bind(Sub1, ?URL),
    {ok,Pub1} = enm:pub(),
    {ok,_} = enm:connect(Pub1, ?URL),
    {ok,Pub2} = enm:pub(),
    {ok,_} = enm:connect(Pub2, ?URL),
    ok = two_pub_active_true(Pub1, Pub2, Sub1),
    ok = two_pub_active_once(Pub1, Pub2, Sub1),
    ok = two_pub_passive(Pub1, Pub2, Sub1),
    ok = enm:close(Sub1),
    ok = enm:close(Pub1),
    ok = enm:close(Pub2),
    ok.

two_pub_active_true(Pub1, Pub2, Sub1) ->
    ok = enm:setopts(Sub1, [{active,true}]),
    ok = two_pub_active(Pub1, Pub2, Sub1),
    ?assertMatch({ok, [{active,true}]}, enm:getopts(Sub1, [active])),
    ok.

two_pub_active_once(Pub1, Pub2, Sub1) ->
    F = fun() -> ok = enm:setopts(Sub1, [{active,once}]), Sub1 end,
    ok = two_pub_active(Pub1, Pub2, F),
    ?assertMatch({ok, [{active,false}]}, enm:getopts(Sub1, [active])),
    ok.

two_pub_active(Pub1, Pub2, Sub1) ->
    Data = <<"some important information for subscribers">>,
    ok = enm:send(Pub1, Data),
    ok = enm:send(Pub2, Data),
    true = lists:all(fun(ok) -> true end, do_sub([Sub1, Sub1], Data)),
    ok.

two_pub_passive(Pub1, Pub2, Sub1) ->
    ok = enm:setopts(Sub1, [{active,false}]),
    Data = <<"some important information for subscribers">>,
    ok = enm:send(Pub1, Data),
    ok = enm:send(Pub2, Data),
    {ok, Data} = enm:recv(Sub1),
    {ok, Data} = enm:recv(Sub1),
    ok.

check_sub_filter() ->
    {ok, Pub} = enm:pub([{bind, ?URL}]),
    {ok, Sub} = enm:sub([{connect, ?URL}, {subscribe, "good"}]),
    ok = enm:send(Pub, "bad"),
    ok = receive
             Bad -> error({should_be_filtered, Bad})
         after
             2000 ->
                 ok
         end,
    Good = <<"good">>,
    ok = enm:send(Pub, Good),
    ok = receive
             {nnsub,Sub,Good} -> ok;
             Msg -> error({unexpected_data, Msg})
         after
             2000 ->
                 error(subscriber_timeout)
         end,
    ok = enm:close(Sub),
    ok = enm:close(Pub),
    ok.

do_sub(Subs, Data) ->
    do_sub(Subs, Data, []).
do_sub([], _, Acc) ->
    Acc;
do_sub([Sub|Subs], Data, Acc) when is_function(Sub) ->
    do_sub([Sub()|Subs], Data, Acc);
do_sub([Sub|Subs], Data, Acc) ->
    receive
        {nnsub,Sub,Data} ->
            do_sub(Subs, Data, [ok|Acc]);
        Msg -> error({unexpected_data, Msg})
    after
        2000 ->
            error(subscriber_timeout)
    end.
