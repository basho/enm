%% -------------------------------------------------------------------
%%
%% survey: example of enm survey support
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
-module(survey).
-export([start/0]).

-define(COUNT, 3).

start() ->
    enm:start_link(),
    Url = "inproc://survey",
    Self = self(),
    {ok,Survey} = enm:surveyor([{bind,Url},{deadline,3000}]),
    Clients = clients(Url, Self),
    ok = enm:send(Survey, httpd_util:rfc1123_date()),
    get_responses(Survey),
    wait_for_clients(Clients),
    enm:close(Survey),
    enm:stop().

clients(Url, Parent) ->
    clients(Url, Parent, ?COUNT, []).
clients(_, _, 0, Acc) ->
    Acc;
clients(Url, Parent, Count, Acc) ->
    {ok, Respondent} = enm:respondent([{connect,Url},{active,false},list]),
    Name = "Respondent" ++ integer_to_list(Count),
    Pid = spawn_link(fun() -> client(Respondent, Name, Parent) end),
    clients(Url, Parent, Count-1, [Pid|Acc]).

client(Respondent, Name, Parent) ->
    {ok,Msg} = enm:recv(Respondent, 5000),
    Date = httpd_util:convert_request_date(Msg),
    ok = enm:send(Respondent, term_to_binary(Date)),
    io:format("~s got \"~s\"~n", [Name, Msg]),
    Parent ! {done, self(), Respondent}.

get_responses(Survey) ->
    get_responses(Survey, ?COUNT+1).
get_responses(_, 0) ->
    ok;
get_responses(Survey, Count) ->
    receive
        {nnsurveyor,Survey,BinResp} ->
            Response = binary_to_term(BinResp),
            io:format("received survey response ~p~n", [Response]);
        {nnsurveyor_deadline,Survey} ->
            io:format("survey has expired~n")
    end,
    get_responses(Survey, Count-1).

wait_for_clients([Client|Clients]) ->
    receive
        {done,Client,Respondent} ->
            enm:close(Respondent),
            wait_for_clients(Clients)
    end;
wait_for_clients([]) ->
    ok.
