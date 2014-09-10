%% -------------------------------------------------------------------
%%
%% request_reply: example of enm request/reply support
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
-module(request_reply).
-export([start/0]).

start() ->
    enm:start_link(),
    Url = "inproc://request_reply",
    {ok,Rep} = enm:rep([{bind,Url}]),
    {ok,Req} = enm:req([{connect,Url}]),
    DateReq = <<"DATE">>,
    io:format("sending date request~n"),
    ok = enm:send(Req, DateReq),
    receive
        {nnrep,Rep,DateReq} ->
            io:format("received date request~n"),
            Now = httpd_util:rfc1123_date(),
            io:format("sending date ~s~n", [Now]),
            ok = enm:send(Rep, Now)
    end,
    receive
        {nnreq,Req,Date} ->
            io:format("received date ~s~n", [Date])
    end,
    enm:close(Req),
    enm:close(Rep),
    enm:stop().
