%% -------------------------------------------------------------------
%%
%% enm.hrl: data types for enm
%%
%% Copyright (c) 2014 Basho Technologies, Inc. All Rights Reserved.
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

-record(nn_inproc, {
          addr :: string() | binary()
         }).

-record(nn_ipc, {
          path :: string() | binary()
         }).

-record(nn_tcp, {
          interface :: any | inet:ip_address() | string() | undefined,
          addr :: inet:ip_address() | inet:hostname() | undefined,
          port :: inet:port_number()
         }).
