%% -------------------------------------------------------------------
%%
%% pipeline: example of enm pipeline support
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
-module(pipeline).
-export([start/0]).

start() ->
    enm:start_link(),
    Url = "inproc://pipeline",
    {ok,Pull} = enm:pull([{bind,Url},list]),
    {ok,Push} = enm:push([{connect,Url},list]),
    Send1 = "Hello, World!",
    io:format("pushing message \"~s\"~n", [Send1]),
    ok = enm:send(Push, Send1),
    receive
        {nnpull,Pull,Send1} ->
            io:format("pulling message \"~s\"~n", [Send1])
    end,
    Send2 = "Goodbye.",
    io:format("pushing message \"~s\"~n", [Send2]),
    ok = enm:send(Push, Send2),
    receive
        {nnpull,Pull,Send2} ->
            io:format("pulling message \"~s\"~n", [Send2])
    end,
    enm:close(Push),
    enm:close(Pull),
    enm:stop().
