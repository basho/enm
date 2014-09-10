%% -------------------------------------------------------------------
%%
%% enm_bind_connect: bind & connect tests for enm
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
-module(enm_bind_connect).
-compile(export_all).

-include_lib("eunit/include/eunit.hrl").
-include("../include/enm.hrl").

bind_test_() ->
    {setup,
     fun enm:start_link/0,
     fun(_) -> enm:stop() end,
     fun() ->
             {ok,P} = enm:pair(),
             {ok,BI1} = enm:bind(P, #nn_inproc{addr="foo"}),
             ?assert(is_integer(BI1)),
             ok = enm:shutdown(P, BI1),
             {error, einval} = enm:shutdown(P, BI1),
             {ok,BI2} = enm:bind(P, #nn_inproc{addr="foo2"}),
             ?assert(is_integer(BI2)),
             {ok,BI3} = enm:bind(P, #nn_inproc{addr="foo3"}),
             ?assert(is_integer(BI3)),
             ok = enm:close(P),
             ok
     end}.

connect_test_() ->
    {setup,
     fun enm:start_link/0,
     fun(_) -> enm:stop() end,
     fun() ->
             {ok,P1} = enm:pair(),
             {ok,_} = enm:bind(P1, #nn_inproc{addr="foo"}),
             {ok,P2} = enm:pair(),
             {ok,CI} = enm:connect(P2, #nn_inproc{addr="foo"}),
             ?assert(is_integer(CI)),
             ok = enm:shutdown(P2, CI),
             ?assertMatch({error, einval}, enm:shutdown(P2, CI)),
             ok = enm:close(P2),
             ok = enm:close(P1),
             ok
     end}.
