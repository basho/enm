%% -------------------------------------------------------------------
%%
%% enm_opts: option tests for enm
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
-module(enm_opts).
-compile(export_all).

-include_lib("eunit/include/eunit.hrl").
-include("../include/enm.hrl").

opt_test_() ->
    {setup,
     fun enm:start_link/0,
     fun(_) -> enm:stop() end,
     [fun getopts/0,
      fun active/0,
      fun mode/0,
      fun misc/0]}.

getopts() ->
    {ok,P} = enm:pair(),
    {ok,Opts} = enm:getopts(P, [type,active]),
    ?assertMatch({type,nnpair}, lists:keyfind(type,1,Opts)),
    ?assertMatch({active,true}, lists:keyfind(active,1,Opts)),
    ?assertMatch({ok,[{mode,binary}]}, enm:getopts(P, [mode])),
    ok = enm:close(P),
    ok.

active() ->
    Url = #nn_inproc{addr="active"},
    Req = <<"123456789">>,
    {ok, P1} = enm:pair([{active,false}]),
    {ok, _} = enm:bind(P1, Url),
    {ok, P2} = enm:pair(),
    {ok, _} = enm:connect(P2, Url),
    ok = enm:send(P2, Req),
    ok = receive
             Reply1 ->
                 error({unexpected_reply, Reply1})
         after
             0 ->
                 ok
         end,
    {ok, Req} = enm:recv(P1),
    ok = enm:setopts(P1, [{active,once}]),
    ok = receive
             Reply2 ->
                 error({unexpected_reply, Reply2})
         after
             0 ->
                 ok
         end,
    ok = enm:send(P2, Req),
    ok = receive
             {nnpair,P1,Req} ->
                 ok;
             Reply3 ->
                 error({unexpected_reply, Reply3})
         after
             1000 ->
                 error(reply_timeout)
         end,
    ok = enm:send(P2, Req),
    ok = receive
             Reply4 ->
                 error({unexpected_reply, Reply4})
         after
             0 ->
                 ok
         end,
    {ok, [{active,false}]} = enm:getopts(P1, [active]),
    ok = enm:setopts(P1, [{active,once}]),
    ok = receive
             {nnpair,P1,Req} ->
                 ok;
             Reply5 ->
                 error({unexpected_reply, Reply5})
         after
             1000 ->
                 error(reply_timeout)
         end,
    ok = enm:setopts(P1,[{active,1}]),
    ?assertMatch({ok,[{active,1}]}, enm:getopts(P1,[active])),
    ok = enm:setopts(P1,[{active,-1}]),
    ok = receive
             {nnpair_passive,P1} ->
                 ok;
             Reply6 ->
                 error({unexpected_reply, Reply6})
         after
             1000 ->
                 error(reply_timeout)
         end,
    ?assertMatch({ok, [{active,false}]}, enm:getopts(P1, [active])),
    ok = enm:setopts(P1,[{active,-1}]),
    ok = receive
             {nnpair_passive,P1} ->
                 ok;
             Reply7 ->
                 error({unexpected_reply, Reply7})
         after
             1000 ->
                 error(reply_timeout)
         end,
    ?assertMatch({ok, [{active,false}]}, enm:getopts(P1, [active])),
    ok = enm:setopts(P1,[{active,2}]),
    ok = enm:send(P2, Req),
    ok = receive
             {nnpair,P1,Req} ->
                 ok;
             Reply8 ->
                 error({unexpected_reply, Reply8})
         after
             1000 ->
                 error(reply_timeout)
         end,
    ?assertMatch({ok,[{active,1}]}, enm:getopts(P1,[active])),
    ok = enm:send(P2, Req),
    ok = receive
             {nnpair,P1,Req} ->
                 ok;
             Reply9 ->
                 error({unexpected_reply, Reply9})
         after
             1000 ->
                 error(reply_timeout)
         end,
    ok = receive
             {nnpair_passive,P1} ->
                 ok;
             Reply10 ->
                 error({unexpected_reply, Reply10})
         after
             1000 ->
                 error(reply_timeout)
         end,
    ?assertMatch({ok, [{active,false}]}, enm:getopts(P1, [active])),
    ok = enm:close(P2),
    ok = enm:close(P1),
    ok.

mode() ->
    Url = <<"inproc://mode">>,
    {ok,Rep} = enm:rep([{bind,Url},{mode,list}]),
    {ok,Req} = enm:req([{connect,Url},{active,false}]),
    Data = <<"data data data data">>,
    DataList = binary_to_list(Data),
    ok = enm:send(Req, Data),
    ok = receive
             {nnrep,Rep,DataList} ->
                 ok = enm:send(Rep, "ok");
             Reply1 ->
                 error({unexpected_reply,Reply1})
         end,
    ok = enm:setopts(Rep,[{mode,binary}]),
    ok = enm:send(Req, Data),
    ok = receive
             {nnrep,Rep,Data} ->
                 ok = enm:send(Rep, "ok");
             Reply2 ->
                 error({unexpected_reply,Reply2})
         end,
    ok = enm:setopts(Rep,[{active,false}]),
    ok = enm:send(Req, Data),
    ?assertMatch({ok, Data}, enm:recv(Rep, 2000)),
    ok = enm:send(Rep, "ok"),
    ok = enm:setopts(Rep,[{mode,list}]),
    ok = enm:send(Req, Data),
    ?assertMatch({ok, DataList}, enm:recv(Rep, 2000)),
    ok = enm:setopts(Rep,[binary]),
    {ok, [{mode,binary}]} = enm:getopts(Rep, [mode]),
    ok = enm:setopts(Rep,[list]),
    ?assertMatch({ok, [{mode,list}]}, enm:getopts(Rep, [mode])),
    ok = enm:close(Req),
    ok = enm:close(Rep),
    ok.

misc() ->
    {ok,Req} = enm:req([{resend_ivl,5000}]),
    ?assertMatch({ok,[{resend_ivl,5000}]}, enm:getopts(Req, [resend_ivl])),
    ok = enm:setopts(Req, [{sndbuf,345678}]),
    ?assertMatch({ok,[{sndbuf,345678}]}, enm:getopts(Req, [sndbuf])),
    ok = enm:setopts(Req, [{rcvbuf,456789}]),
    ?assertMatch({ok,[{rcvbuf,456789}]}, enm:getopts(Req, [rcvbuf])),
    ok = try enm:pull([{sndbuf,12345678}]) of
             _ -> error(should_have_failed)
         catch error:badarg -> ok end,
    ok = try enm:sub([{sndbuf,12345678}]) of
             _ -> error(should_have_failed)
         catch error:badarg -> ok end,
    ok = try enm:push([{rcvbuf,12345678}]) of
             _ -> error(should_have_failed)
         catch error:badarg -> ok end,
    ok = try enm:pub([{rcvbuf,12345678}]) of
             _ -> error(should_have_failed)
         catch error:badarg -> ok end,
    ok = enm:close(Req),
    ok.
