%% -------------------------------------------------------------------
%%
%% enm_survey: test surveyor/respondent protocols for enm
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
-module(enm_survey).
-compile(export_all).

-include_lib("eunit/include/eunit.hrl").
-include("../include/enm.hrl").

surveyor_test_() ->
    {setup,
     fun enm:start_link/0,
     fun(_) -> enm:stop() end,
     fun surveyor/0}.

surveyor() ->
    Url = #nn_inproc{addr="foo"},
    Req = <<"abcdefghijklm">>,
    Rep = <<"nopqrstuvwxyz">>,
    Deadline = 5000,
    {ok, S} = enm:surveyor([{deadline,Deadline}]),
    {ok, [{deadline,Deadline}]} = enm:getopts(S, [deadline]),
    {ok, _} = enm:bind(S, Url),
    Resp = lists:seq(1,3),
    Self = self(),
    [spawn_link(?MODULE,respondent,[Url,Req,Rep,Self]) || _ <- Resp],
    [receive respondent_ready -> ok end || _ <- Resp],
    ok = enm:send(S, Req),
    ok = enm:setopts(S, [{active,true}]),
    true = lists:all(fun(ok) -> true end, collect(S, Rep, length(Resp))),
    ok = enm:close(S),
    ok.

respondent(Url, Req, Rep, Pid) ->
    {ok, R} = enm:respondent(),
    {ok, _} = enm:connect(R, Url),
    Pid ! respondent_ready,
    ok = receive
             {nnrespondent, R, Req} ->
                 ok = enm:send(R, Rep),
                 timer:sleep(1000),
                 enm:close(R);
             Request ->
                 error({unexpected_request, Request})
         after
             2000 ->
                 error(respondent_timeout)
         end.

collect(S, Rep, Count) ->
    collect(S, Rep, Count, []).
collect(_, _, 0, Acc) ->
    Acc;
collect(S, Rep, Count, Acc) ->
    ok = receive
             {nnsurveyor,S,Rep} ->
                 ok;
             {nnsurveyor_deadline,S} ->
                 ok;
             Reply ->
                 error({unexpected_reply,Reply})
         after
             3500 ->
                 error(surveyor_timeout)
         end,
    collect(S, Rep, Count-1, [ok|Acc]).
