-module(enm_eqc).

%% ---------------------------------------------------------------------
%%
%% Copyright (c) 2007-2013 Basho Technologies, Inc.  All Rights Reserved.
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
%% ---------------------------------------------------------------------

%% @doc Quickcheck test module for `enm_eqc'.
%% Ideas:
%% * Use eqc_fsm to model states of socket
%%      * `init' state: Open random type of socket
%%      * `send' state: send message
%%      * `recv' state: receive message
%%      * `close' state: close socket
%% * Permit any transition from `init' state
%%
%% * Other interesting things to do
%%     * Random selection of address record type
%%     * Combination of different socket options

-ifdef(TEST).

-ifdef(EQC).

-include_lib("eqc/include/eqc.hrl").
-include_lib("eqc/include/eqc_fsm.hrl").
-include_lib("eunit/include/eunit.hrl").

%% eqc properties
-export([prop_enm/0]).

%% States
-export([init/1,
         msg_sent/1,
         msg_received/1,
         closed/1]).

%% eqc_fsm callbacks
-export([initial_state/0,
         initial_state_data/0,
         next_state_data/5,
         precondition/4,
         postcondition/5]).

-export([recv/1,
         close/2,
         test/0,
         test/1]).

-define(QC_OUT(P),
        eqc:on_output(fun(Str, Args) ->
                              io:format(user, Str, Args) end, P)).

-define(ENM_MODULE, enm).
-define(TEST_ITERATIONS, 100).

-define(P(EXPR), PPP = (EXPR),
        case PPP of
            true -> ok;
            _ -> io:format(user, "PPP=~p at line ~p: ~s~n", [PPP, ?LINE, ??EXPR])
        end,
        PPP).

-record(state, {sent_messages=[] :: [term()],
                write_socket :: term(),
                read_socket :: term(),
                socket_closed=false :: boolean()
               }).

%% ====================================================================
%% EQC Properties
%% ====================================================================

prop_enm() ->
    ?FORALL(Cmds,
            commands(?MODULE),
            begin
                {Read, Write} = sockets(),
                {H, {_F, _S}, Res} =
                    run_commands(?MODULE, Cmds, [{read_socket, Read},
                                                 {write_socket, Write}]),
                close(Read, Write),
                aggregate(zip(state_names(H), command_names(Cmds)),
                          ?WHENFAIL(
                             begin
                                 eqc:format("Cmds: ~p~n~n",
                                            [zip(state_names(H),
                                                 command_names(Cmds))]),
                                 eqc:format("Result: ~p~n~n", [Res]),
                                 eqc:format("History: ~p~n~n", [H])
                             end,
                             equals(ok, Res)))
            end).

%%====================================================================
%% Eunit shite
%%====================================================================

eqc_test_() ->
    {spawn,
     [{setup,
       fun setup/0,
       fun cleanup/1,
       [%% Run the quickcheck tests
        {timeout, 600,
         ?_assertEqual(true, eqc:quickcheck(
                               eqc:numtests(?TEST_ITERATIONS,
                                            ?QC_OUT(prop_enm()))))}
       ]}
     ]}.

setup() ->
    error_logger:tty(false),
    error_logger:logfile({open, "enm_eqc.log"}),
    enm:start().

cleanup(_) ->
    enm:stop().

%%====================================================================
%% eqc_fsm callbacks
%%====================================================================

%% TODO: Test other protocol types
%% Just testing pipeline initially
%% Protocols: [reqrep, pair, pubsub, pipeline, survey]
%% Open question whether or not each protocol should
%% have it's own eqc module or they should be rolled into
%% one.

init(S) ->
    %% TODO: shutdown state?
    [
     {msg_sent, {call, ?ENM_MODULE, send, [S#state.write_socket, eqc_gen:binary(10)]}},
     {msg_received, {call, ?MODULE, recv, [S#state.read_socket]}},
     {closed, {call, ?MODULE, close, [S#state.read_socket, S#state.write_socket]}}
    ].

msg_sent(S) ->
    [
     {msg_received, {call, ?MODULE, recv, [S#state.read_socket]}},
     {closed, {call, ?MODULE, close, [S#state.read_socket, S#state.write_socket]}},
     {history, {call, ?ENM_MODULE, send, [S#state.write_socket, eqc_gen:binary(10)]}}
    ].

msg_received(S) ->
    [
     {msg_sent, {call, ?ENM_MODULE, send, [S#state.write_socket, eqc_gen:binary(10)]}},
     {closed, {call, ?MODULE, close, [S#state.read_socket, S#state.write_socket]}},
     {history, {call, ?MODULE, recv, [S#state.read_socket]}}
    ].

closed(S) ->
    [
     {msg_sent, {call, ?ENM_MODULE, send, [S#state.write_socket, eqc_gen:binary()]}},
     {msg_received, {call, ?MODULE, recv, [S#state.read_socket]}},
     {history, {call, ?MODULE, close, [S#state.read_socket, S#state.write_socket]}}
    ].


initial_state() ->
    init.

initial_state_data() ->
    #state{read_socket={var, read_socket},
           write_socket={var, write_socket}}.

next_state_data(_, msg_received, S, _Res, _C) ->
    Messages = lists:reverse(S#state.sent_messages),
    case Messages of
        [] ->
            S;
        [_Head | RestMessages] ->
            S#state{sent_messages=lists:reverse(RestMessages)}
    end;
next_state_data(closed, _, S, _Res, _C) ->
    S;
next_state_data(_, closed, S, _Res, _C) ->
    S#state{socket_closed=true};
next_state_data(_, msg_sent, S, _Res, {call, _M, _F, [_, SentMsg]}) ->
    SentMessages = S#state.sent_messages,
    S#state{sent_messages=[SentMsg | SentMessages]};

next_state_data(_From, _To, S, _R, _C) ->
    S.

precondition(_From, _To, _S, _C) ->
    true.

postcondition(_, closed, _S, _C, ok) ->
    true;
postcondition(closed, msg_received, S , _C, {ok, Msg})
  when S#state.sent_messages =/= [] ->
    ExpectedMsg = lists:last(S#state.sent_messages),
    ?P(ExpectedMsg =:= Msg);
postcondition(closed, msg_received, _S , _C, {error, timeout}) ->
    true;
postcondition(closed, _, _S , _C, {error, closed}) ->
    true;
postcondition(closed, _, _S , _C, R) ->
    ?debugFmt("Res: ~p", [R]),
    ?P(false);
postcondition(_, msg_received, S , _C, {ok, Msg})
  when S#state.socket_closed =:= true,
       S#state.sent_messages =/= [] ->
    ExpectedMsg = lists:last(S#state.sent_messages),
    ?P(ExpectedMsg =:= Msg);
postcondition(_, msg_received, S, _C, {error, timeout})
  when S#state.socket_closed =:= true ->
    true;
postcondition(_, _, S, _C, {error, closed})
  when S#state.socket_closed =:= true ->
    true;
postcondition(_, _, S, _C, R)
  when S#state.socket_closed =:= true ->
    ?debugFmt("Res2: ~p", [R]),
    ?P(false);
postcondition(_, msg_sent, _S , _C, ok) ->
    true;
postcondition(_, msg_sent, _S , _C, _R) ->
    ?P(false);
postcondition(_, msg_received, S , _C, {ok, Msg}) ->
    ExpectedMsg = lists:last(S#state.sent_messages),
    ?P(ExpectedMsg =:= Msg);
postcondition(_, msg_received, S , _C, {error, timeout}) ->
    case S#state.sent_messages of
        [] ->
            true;
        _ ->
            ?P(false)
    end;
postcondition(_, msg_received, _S , _C, _R) ->
    ?P(false);
postcondition(_From, _To, _S, _C, _R) ->
    true.

%%====================================================================
%% Helpers
%%====================================================================

sockets() ->
    Url = "inproc://pipeline",
    {ok, Read} = enm:pull([{bind, Url}]),
    {ok, Write} = enm:push([{connect, Url}]),
    {Read, Write}.

close(Read, Write) ->
    enm:close(Read),
    enm:close(Write).

recv(Socket) ->
    receive
        {nnpull, Socket, Msg} ->
            {ok, Msg}
    after
        1000 ->
            {error, timeout}
    end.

test() ->
    test(500).

test(Iterations) ->
    setup(),
    Res = eqc:quickcheck(eqc:numtests(Iterations, prop_enm())),
    cleanup(ok),
    Res.


-endif.
-endif.
