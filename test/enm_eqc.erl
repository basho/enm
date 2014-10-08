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

-export([recv/3,
         close/2,
         test/0,
         test/1,
         recheck/0]).

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
                active :: atom() | pos_integer(),
                mode :: atom(),
                msg :: binary() | list(),
                socket_closed=false :: boolean()
               }).

%% ====================================================================
%% EQC Properties
%% ====================================================================

prop_enm() ->
    ?FORALL({Protocol, Transport, Mode, Msg, Active},
            {protocol_gen(), transport_gen(), mode_gen(), iolist_gen(), active_gen()},
            ?FORALL(Cmds,
                    commands(?MODULE),
                    begin
                        {Read, Write} = sockets(Protocol, Transport, Mode, Active),
                        {H, {_F, _S}, Res} =
                            run_commands(?MODULE, Cmds, [{read_socket, Read},
                                                         {write_socket, Write},
                                                         {mode, Mode},
                                                         {msg, Msg},
                                                         {active, Active}]),
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
                    end)).

%%====================================================================
%% Generators
%%====================================================================

iolist_gen() ->
    list(oneof([binary(), byte()])).

byte() ->
    ?SUCHTHAT(X, int(), X >= 0 andalso X =< 255).

%% TODO: Expand testing to other protocols
protocol_gen() ->
    eqc_gen:oneof([pipeline]).

transport_gen() ->
    eqc_gen:oneof([inproc, tcp, ipc]).

mode_gen() ->
    eqc_gen:oneof([list, binary]).

%% TODO: Add testing for `once' and `N' options
active_gen() ->
    %% eqc_gen:oneof([true, false, once, {n, int()}]).
    eqc_gen:oneof([true, false]).

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
    error_logger:logfile({open, "enm_eqc.log"}),
    error_logger:tty(false),
    case file:make_dir("/tmp/enm-eqc") of
        ok ->
            ok;
        {error, eexist} ->
            ok;
        {error, Reason} ->
            ?debugFmt("Failed to create directory for ipc socket "
                      "testing. Reason: ~p",
                      [Reason]),
            ok
    end,
    enm:start().

cleanup(_) ->
    _ = file:del_dir("/tmp/enm-eqc"),
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
     {msg_sent, {call, ?ENM_MODULE, send, [S#state.write_socket, S#state.msg]}},
     {msg_received, {call, ?MODULE, recv, [S#state.read_socket, S#state.active, S#state.mode]}},
     {closed, {call, ?MODULE, close, [S#state.read_socket, S#state.write_socket]}}
    ].

msg_sent(S) ->
    [
     {msg_received, {call, ?MODULE, recv, [S#state.read_socket, S#state.active, S#state.mode]}},
     {closed, {call, ?MODULE, close, [S#state.read_socket, S#state.write_socket]}},
     {history, {call, ?ENM_MODULE, send, [S#state.write_socket, S#state.msg]}}
    ].

msg_received(S) ->
    [
     {msg_sent, {call, ?ENM_MODULE, send, [S#state.write_socket, S#state.msg]}},
     {closed, {call, ?MODULE, close, [S#state.read_socket, S#state.write_socket]}},
     {history, {call, ?MODULE, recv, [S#state.read_socket, S#state.active, S#state.mode]}}
    ].

closed(S) ->
    [
     {msg_sent, {call, ?ENM_MODULE, send, [S#state.write_socket, S#state.msg]}},
     {msg_received, {call, ?MODULE, recv, [S#state.read_socket, S#state.active, S#state.mode]}},
     {history, {call, ?MODULE, close, [S#state.read_socket, S#state.write_socket]}}
    ].


initial_state() ->
    init.

initial_state_data() ->
    #state{read_socket={var, read_socket},
           write_socket={var, write_socket},
           active={var, active},
           mode={var, mode},
           msg={var, msg}}.

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
postcondition(_, msg_received, S , _C, {ok, Msg})
  when S#state.socket_closed =:= true,
       S#state.sent_messages =/= [] ->
    ExpectedMsg = lists:last(S#state.sent_messages),
    ?P(maybe_convert_msg(ExpectedMsg, S#state.mode) =:= Msg);
postcondition(_, msg_received, S , _C, {error, timeout})
  when S#state.socket_closed =:= true ->
    true;
postcondition(_, _, S , _C, {error, closed})
  when S#state.socket_closed =:= true ->
    true;
postcondition(_, _, S , _C, _R)
  when S#state.socket_closed =:= true ->
    ?P(false);
postcondition(_, msg_sent, _S , _C, ok) ->
    true;
postcondition(_, msg_sent, _S , _C, _R) ->
    ?P(false);
postcondition(_, msg_received, S , _C, {ok, Msg}) ->
    ExpectedMsg = lists:last(S#state.sent_messages),
    ?P(maybe_convert_msg(ExpectedMsg, S#state.mode) =:= Msg);
postcondition(_, msg_received, S , _C, {error, timeout})
  when S#state.sent_messages =:= [] ->
    true;
postcondition(_, msg_received, S , _C, {error, timeout}) ->
    [HeadSent | _] = lists:reverse(S#state.sent_messages),
    case iolist_size(HeadSent) of
        0 ->
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

sockets(Protocol, Transport, Mode, Active) ->
    Url = url(Protocol, Transport),
    {ok, Read} = enm:pull([{bind, Url}, Mode, {active, Active}]),
    {ok, Write} = enm:push([{connect, Url}]),
    {Read, Write}.

url(pipeline, inproc) ->
    "inproc://pipeline";
url(pipeline, ipc) ->
    "ipc:///tmp/enm-eqc/test.ipc";
url(pipeline, tcp) ->
    "tcp://127.0.0.1:12345".

close(Read, Write) ->
    enm:close(Read),
    enm:close(Write).

recv(Socket, true, Mode) ->
    receive
        {nnpull, Socket, Msg} ->
            {ok, maybe_convert_msg(Msg, Mode)}
    after
        1000 ->
            {error, timeout}
    end;
recv(Socket, false, Mode) ->
    case enm:recv(Socket, 1000) of
        {error, etimedout} ->
            {error, timeout};
        {error, _}=Error ->
            Error;
        {ok, Msg} ->
            {ok, maybe_convert_msg(Msg, Mode)}
    end.

maybe_convert_msg([], binary) ->
    <<>>;
maybe_convert_msg(Msg, binary) when is_list(Msg) ->
    iolist_to_binary(Msg);
maybe_convert_msg(Msg, binary) when is_binary(Msg) ->
    Msg;
maybe_convert_msg([<<>>], list) ->
    [];
maybe_convert_msg([], list) ->
    [];
maybe_convert_msg([[]], list) ->
    [];
maybe_convert_msg(Msg, list) ->
    binary_to_list(iolist_to_binary(Msg)).

test() ->
    test(500).

test(Iterations) ->
    setup(),
    Res = eqc:quickcheck(eqc:numtests(Iterations, prop_enm())),
    cleanup(ok),
    Res.

recheck() ->
    setup(),
    Res = eqc:recheck(prop_enm()),
    cleanup(ok),
    Res.

-endif.
-endif.
