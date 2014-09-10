%% -------------------------------------------------------------------
%%
%% enm_start_stop: start/stop tests for enm
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
-module(enm_start_stop).
-compile(export_all).

-include_lib("eunit/include/eunit.hrl").

start_stop_test() ->
    {ok,_} = enm:start(),
    ok = enm:stop(),
    {ok,_} = enm:start_link(),
    ok = enm:stop(),
    ok.
