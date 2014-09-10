%% -------------------------------------------------------------------
%%
%% enm_pair: test pair protocol for enm
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
-module(enm_pair).
-compile(export_all).

-include_lib("eunit/include/eunit.hrl").
-include("../include/enm.hrl").

pair_test_() ->
    {setup,
     fun enm:start_link/0,
     fun(_) -> enm:stop() end,
     fun pair/0}.

pair() ->
    Url = #nn_inproc{addr="a"},
    {ok, SB} = enm:pair([{bind, Url}]),
    {ok, SC} = enm:pair([{connect, Url}]),
    ok = active_true_pair(SB, SC),
    ok = active_once_pair(SB, SC),
    ok = passive_pair(SB, SC),
    ok.

active_true_pair(SB, SC) ->
    ok = enm:setopts(SB, [{active,true}]),
    ok = enm:setopts(SC, [{active,true}]),
    ok = active_req_rep(SB, SC),
    ?assertMatch({ok, [{active,true}]}, enm:getopts(SB, [active])),
    ?assertMatch({ok, [{active,true}]}, enm:getopts(SC, [active])),
    ok.

active_once_pair(SB, SC) ->
    ok = enm:setopts(SB, [{active,once}]),
    ok = enm:setopts(SC, [{active,once}]),
    ok = active_req_rep(SB, SC),
    ?assertMatch({ok, [{active,false}]}, enm:getopts(SB, [active])),
    ?assertMatch({ok, [{active,false}]}, enm:getopts(SC, [active])),
    ok.

passive_pair(SB, SC) ->
    Req = <<"passive request">>,
    Rep = <<"passive reply">>,
    ok = enm:setopts(SB, [{active,false}]),
    ok = enm:setopts(SC, [{active,false}]),
    ok = enm:send(SC, Req),
    ?assertMatch({ok, Req}, enm:recv(SB)),
    ok = enm:send(SB, Rep),
    ?assertMatch({ok, Rep}, enm:recv(SC)),
    ok.

active_req_rep(SB, SC) ->
    Req = <<"active request">>,
    Rep = <<"active reply">>,
    ok = enm:send(SC, Req),
    ok = receive
             {nnpair, SB, Req} ->
                 ok = enm:send(SB, Rep);
             BadReq ->
                 error({unexpected_request, BadReq})
         after
             2000 ->
                 error(request_timeout)
         end,
    ok = receive
             {nnpair, SC, Rep} ->
                 ok;
             BadRep ->
                 error({unexpected_reply, BadRep})
         after
             2000 ->
                 error(reply_timeout)
         end,
    ok.
