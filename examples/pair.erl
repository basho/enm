%% -------------------------------------------------------------------
%%
%% pair: example of enm pair support
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
-module(pair).
-export([start/0, node/4]).

start() ->
    enm:start_link(),
    Self = self(),
    Url = "inproc://pair",
    spawn(?MODULE, node, [Self, Url, bind, "Node0"]),
    spawn(?MODULE, node, [Self, Url, connect, "Node1"]),
    collect(["Node0","Node1"]).

node(Parent, Url, F, Name) ->
    {ok,P} = enm:pair([{active,3}]),
    {ok,Id} = enm:F(P,Url),
    send_recv(P, Name),
    enm:shutdown(P, Id),
    Parent ! {done,Name}.

send_recv(Sock, Name) ->
    receive
        {_,Sock,Buf} ->
            io:format("~s received \"~s\"~n", [Name, Buf])
    after
        100 ->
            ok
    end,
    case enm:getopts(Sock, [active]) of
        {ok, [{active,false}]} ->
            ok;
        {error, Error} ->
            error(Error);
        _ ->
            timer:sleep(1000),
            io:format("~s sending \"~s\"~n", [Name, Name]),
            ok = enm:send(Sock, Name),
            send_recv(Sock, Name)
    end.

collect([]) ->
    ok;
collect([Name|Names]) ->
    receive
        {done,Name} ->
            collect(Names)
    end.
