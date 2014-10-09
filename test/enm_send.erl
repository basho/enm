%% -------------------------------------------------------------------
%%
%% enm_send: send tests for enm
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
-module(enm_send).
-compile(export_all).

-include_lib("eunit/include/eunit.hrl").
-include("../include/enm.hrl").

%%
%% TODO: nanomsg currently ignores the sndbuf option for the inproc
%% transport, and it defaults the send buffer size to 128k even though
%% setting sndbuf appears to work. This test therefore won't pass with the
%% inproc transport unless we send chunks larger than 128k and set the
%% receiver's rcvbuf to a small value.
%%
%% Using the TCP transport instead of inproc makes this test work as
%% expected, since sndbuf works for that transport, but because nanomsg
%% requires fixed ports and doesn't support ephemeral ports, using TCP for
%% any test is problematic given the chance of port clashes.
%%
-define(URL, #nn_inproc{addr="foo"}).
-define(SNDBUF, 1024*128).

suspend_test_() ->
    {setup,
     fun enm:start_link/0,
     fun(_) -> enm:stop() end,
     fun() ->
             {ok,S} = enm:pair([{active,false},{bind,?URL},{rcvbuf,1}]),
             {ok,R} = enm:pair([{sndbuf,?SNDBUF},{connect,?URL}]),
             Data = lists:duplicate(?SNDBUF*2, $X),
             ok = enm:send(R, Data),
             ok = enm:send(R, Data),
             ok = enm:send(R, Data),
             ?assertMatch(false,port_command(R,Data,[nosuspend])),
             ok = enm:setopts(S, [{rcvbuf,?SNDBUF}]),
             clear_receiver(S),
             ?assertMatch(true,port_command(R,Data,[nosuspend])),
             ok = enm:close(R),
             ok = enm:close(S),
             ok
     end}.

clear_receiver(S) ->
    case enm:recv(S, 500) of
        {ok,_} ->
            clear_receiver(S);
        {error,etimedout} ->
            ok
    end.

empty_send_test_() ->
    {setup,
     fun enm:start_link/0,
     fun(_) -> enm:stop() end,
     fun() ->
             {ok,S} = enm:pair([{bind,?URL},{active,false}]),
             {ok,R} = enm:pair([{connect,?URL}]),
             %% sending an empty iolist should result in no data arriving
             %% at the receiver
             ok = enm:send(R, <<>>),
             ?assertMatch({error,etimedout},enm:recv(S,100)),
             ok = enm:close(R),
             ok = enm:close(S),
             ok
     end}.
