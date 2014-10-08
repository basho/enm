%% -------------------------------------------------------------------
%%
%% enm: Erlang driver-based binding for nanomsg
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
-module(enm).
-behaviour(gen_server).

-include("enm.hrl").

-export([close/1, shutdown/2,
         connect/2, bind/2,
         req/0, req/1, rep/0, rep/1,
         pair/0, pair/1,
         bus/0, bus/1,
         push/0, push/1, pull/0, pull/1,
         pub/0, pub/1, sub/0, sub/1,
         surveyor/0, surveyor/1, respondent/0, respondent/1,
         send/2, recv/1, recv/2,
         getopts/2, setopts/2,
         controlling_process/2]).

-export([start_link/0, start/0, stop/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {
          drvmonref :: reference() | undefined
         }).

%% driver command IDs and arguments
-define(ENM_CLOSE, 1).
-define(ENM_BIND, 2).
-define(ENM_CONNECT, 3).
-define(ENM_SHUTDOWN, 4).
-define(ENM_TERM, 5).
-define(ENM_RECV, 10).
-define(ENM_CANCEL_RECV, 11).
-define(ENM_GETOPTS, 12).
-define(ENM_SETOPTS, 13).
-define(ENM_REQ, 20).
-define(ENM_REP, 21).
-define(ENM_BUS, 22).
-define(ENM_PUB, 23).
-define(ENM_SUB, 24).
-define(ENM_PUSH, 25).
-define(ENM_PULL, 26).
-define(ENM_SVYR, 27).
-define(ENM_RESP, 28).
-define(ENM_PAIR, 29).

-define(ENM_FALSE, 0).
-define(ENM_TRUE, 1).
-define(ENM_ONCE, 2).
-define(ENM_N, 3).
-define(ENM_ACTIVE, 10).
-define(ENM_TYPE, 11).
-define(ENM_RAW, 12).
-define(ENM_DEADLINE, 13).
-define(ENM_SUBSCRIBE, 14).
-define(ENM_UNSUBSCRIBE, 15).
-define(ENM_RESEND_IVL, 16).
-define(ENM_BINARY, 17).
-define(ENM_SNDBUF, 18).
-define(ENM_RCVBUF, 19).
-define(ENM_NODELAY, 20).

-type nnstate() :: #state{}.
-type nnsocket() :: port().
-type nndata() :: binary() | list().
-type nnurl() :: #nn_inproc{} | #nn_ipc{} | #nn_tcp{} |
                 binary() | string().
-type nnid() :: integer().
-type nnoptname() :: type | active | raw | mode |
                     deadline | subscribe | unsubscribe | resend_ivl | sndbuf | rcvbuf.
-type nnoptnames() :: [nnoptname()].
-type nntypename() :: nnreq | nnrep | nnbus | nnpub | nnsub | nnpush | nnpull |
                      nnsurveyor | nnrespondent | nnpair.
-type nntypeopt() :: {type, nntypename()}.
-type nnbindopt() :: {bind, nnurl()}.
-type nnconnectopt() :: {connect, nnurl()}.
-type nnactiveopt() :: {active, boolean() | once | -32768..32767}.
-type nnrawopt() :: raw | {raw, boolean()}.
-type nnmodeopt() :: {mode, binary | list} | binary | list.
-type nndeadlineopt() :: {deadline, pos_integer()}.
-type nnsubscribeopt() :: {subscribe, string() | binary()}.
-type nnunsubscribeopt() :: {unsubscribe, string() | binary()}.
-type nnresendivlopt() :: {resend_ivl, pos_integer()}.
-type nnsndbufopt() :: {sndbuf, pos_integer()}.
-type nnrcvbufopt() :: {rcvbuf, pos_integer()}.
-type nnnodelayopt() :: {nodelay, boolean()}.
-type nngetopt() :: nntypeopt() | nnactiveopt() | nnmodeopt() |
                    nndeadlineopt() | nnresendivlopt() |
                    nnsndbufopt() | nnrcvbufopt() | nnnodelayopt().
-type nngetopts() :: [nngetopt()].
-type nnsetopt() :: nnactiveopt() | nnmodeopt() |
                    nndeadlineopt() | nnsubscribeopt() | nnunsubscribeopt() |
                    nnresendivlopt() | nnsndbufopt() | nnrcvbufopt() | nnnodelayopt().
-type nnsetopts() :: [nnsetopt()].
-type nnopenopt() :: nnbindopt() | nnconnectopt() | nnrawopt() |
                     nnactiveopt() | nnmodeopt() |
                     nndeadlineopt() | nnsubscribeopt() | nnunsubscribeopt() |
                     nnresendivlopt() | nnsndbufopt() | nnrcvbufopt() | nnnodelayopt().
-type nnopenopts() :: [nnopenopt()].


-spec start_link() -> {ok, pid()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec start() -> {ok, pid()}.
start() ->
    gen_server:start({local, ?MODULE}, ?MODULE, [], []).

-spec stop() -> ok.
stop() ->
    gen_server:cast(?MODULE, stop),
    wait_for_stop().

-spec close(nnsocket()) -> ok.
close(Sock) when is_port(Sock) ->
    try
        _ = port_control(Sock, ?ENM_CLOSE, <<>>),
        _ = erlang:port_close(Sock)
    catch
        error:badarg ->
            ok
    end,
    ok.

-spec shutdown(nnsocket(), nnid()) -> ok | {error, any()}.
shutdown(Sock, Id) when is_port(Sock) ->
    call_control(Sock, ?ENM_SHUTDOWN, <<Id:32/big>>).

-spec connect(nnsocket(), nnurl()) -> {ok, nnid()} | {error, any()}.
connect(Sock, Url) when is_port(Sock) ->
    call_control(Sock, ?ENM_CONNECT, url(Url)).

-spec bind(nnsocket(), nnurl()) -> {ok, nnid()} | {error, any()}.
bind(Sock, Url) when is_port(Sock) ->
    call_control(Sock, ?ENM_BIND, url(Url)).

-spec getopts(nnsocket(), nnoptnames()) -> {ok, nngetopts()} | {error, any()}.
getopts(Sock, OptNames) when is_port(Sock) ->
    OptBin = validate_opt_names(OptNames),
    call_control(Sock, ?ENM_GETOPTS, OptBin).

-spec setopts(nnsocket(), nnsetopts()) -> ok | {error, any()}.
setopts(Sock, Opts) when is_port(Sock) ->
    case getopts(Sock, [type]) of
        {ok, [{type,Type}]} ->
            case validate_opts(normalize_opts(Opts), Type) of
                OptBin when is_binary(OptBin) ->
                    call_control(Sock, ?ENM_SETOPTS, OptBin);
                Error ->
                    Error
            end;
        Error ->
            Error
    end.

-spec controlling_process(nnsocket(), pid()) -> ok | {error, any()}.
controlling_process(Sock, NewOwner) when is_port(Sock) ->
    case erlang:port_info(Sock, connected) of
        {connected, NewOwner} ->
            ok;
        {connected, Owner} when Owner /= self() ->
            {error, not_owner};
        undefined ->
            {error, closed};
        _ ->
            {ok, Opts} = getopts(Sock, [active,type]),
            {active,A} = lists:keyfind(active,1,Opts),
            {type,Type} = lists:keyfind(type,1,Opts),
            ok = case A of
                     false -> ok;
                     _ -> setopts(Sock, [{active,false}])
                 end,
            ok = transfer_unreceived_msgs(Sock, Type, NewOwner),
            try erlang:port_connect(Sock, NewOwner) of
                true ->
                    unlink(Sock),
                    ok = case A of
                             false -> ok;
                             _ -> setopts(Sock, [{active,A}])
                         end,
                    ok
            catch
                error:Reason ->
                    {error, Reason}
            end
    end.

-spec req() -> {ok, nnsocket()} | {error, any()}.
-spec req(nnopenopts()) -> {ok, nnsocket()} | {error, any()}.
req() ->
    socket(nnreq, [], [], []).
req(Opts) ->
    socket(nnreq, [], [], Opts).

-spec rep() -> {ok, nnsocket()} | {error, any()}.
-spec rep(nnopenopts()) -> {ok, nnsocket()} | {error, any()}.
rep() ->
    socket(nnrep, [], [], []).
rep(Opts) ->
    socket(nnrep, [], [], Opts).

-spec pair() -> {ok, nnsocket()} | {error, any()}.
-spec pair(nnopenopts()) -> {ok, nnsocket()} | {error, any()}.
pair() ->
    socket(nnpair, [], [], []).
pair(Opts) ->
    socket(nnpair, [], [], Opts).

-spec bus() -> {ok, nnsocket()} | {error, any()}.
-spec bus(nnopenopts()) -> {ok, nnsocket()} | {error, any()}.
bus() ->
    socket(nnbus, [], [], []).
bus(Opts) ->
    socket(nnbus, [], [], Opts).

-spec push() -> {ok, nnsocket()} | {error, any()}.
-spec push(nnopenopts()) -> {ok, nnsocket()} | {error, any()}.
push() ->
    socket(nnpush, [], [], []).
push(Opts) ->
    socket(nnpush, [], [], Opts).

-spec pull() -> {ok, nnsocket()} | {error, any()}.
-spec pull(nnopenopts()) -> {ok, nnsocket()} | {error, any()}.
pull() ->
    socket(nnpull, [], [], []).
pull(Opts) ->
    socket(nnpull, [], [], Opts).

-spec pub() -> {ok, nnsocket()} | {error, any()}.
-spec pub(nnopenopts()) -> {ok, nnsocket()} | {error, any()}.
pub() ->
    socket(nnpub, [], [], []).
pub(Opts) ->
    socket(nnpub, [], [], Opts).

-spec sub() -> {ok, nnsocket()} | {error, any()}.
-spec sub(nnopenopts()) -> {ok, nnsocket()} | {error, any()}.
sub() ->
    socket(nnsub, [], [], []).
sub(Opts) ->
    socket(nnsub, [], [], Opts).

-spec surveyor() -> {ok, nnsocket()} | {error, any()}.
-spec surveyor(nnopenopts()) -> {ok, nnsocket()} | {error, any()}.
surveyor() ->
    socket(nnsurveyor, [], [], []).
surveyor(Opts) ->
    socket(nnsurveyor, [], [], Opts).

-spec respondent() -> {ok, nnsocket()} | {error, any()}.
-spec respondent(nnopenopts()) -> {ok, nnsocket()} | {error, any()}.
respondent() ->
    socket(nnrespondent, [], [], []).
respondent(Opts) ->
    socket(nnrespondent, [], [], Opts).

-spec send(nnsocket(), iodata()) -> ok | {error, any()}.
send(Sock, Data) when is_port(Sock) ->
    try
        true = port_command(Sock, Data),
        ok
    catch
        error:badarg ->
            {error, closed}
    end.

-spec recv(nnsocket()) -> {ok, nndata()} | {error, any()}.
-spec recv(nnsocket(), timeout()) -> {ok, nndata()} | {error, any()}.
recv(Sock) when is_port(Sock) ->
    recv(Sock, infinity).
recv(Sock, Timeout) when is_port(Sock) ->
    Ref = make_ref(),
    Bin = term_to_binary(Ref),
    try binary_to_term(port_control(Sock, ?ENM_RECV, Bin)) of
        {Ref, wait} ->
            receive
                {Ref, Reply} when is_tuple(Reply) ->
                    Reply;
                {Ref, Reply} ->
                    {ok, Reply}
            after
                Timeout ->
                    ok = binary_to_term(port_control(Sock, ?ENM_CANCEL_RECV, Bin)),
                    receive
                        {Ref, Reply} when is_tuple(Reply) ->
                            Reply;
                        {Ref, Reply} ->
                            {ok, Reply}
                    after
                        0 ->
                            {error, etimedout}
                    end
            end;
        {Ref, Reply} when is_tuple(Reply) ->
            Reply;
        {Ref, Reply} ->
            {ok, Reply}
    catch
        error:badarg ->
            {error, closed}
    end.

-define(SHLIB, "enm_drv").

-spec init([]) -> ignore | {ok, nnstate()} | {stop, any()}.
init([]) ->
    process_flag(trap_exit, true),
    PrivDir = case code:priv_dir(?MODULE) of
                  {error, bad_name} ->
                      EbinDir = filename:dirname(code:which(?MODULE)),
                      AppPath = filename:dirname(EbinDir),
                      filename:join(AppPath, "priv");
                  Path ->
                      Path
              end,
    Opts = [{driver_options, [kill_ports]}],
    LoadResult = case erl_ddll:try_load(PrivDir, ?SHLIB, Opts) of
                     {ok, loaded} -> ok;
                     {ok, already_loaded} -> ok;
                     {error, LoadError} ->
                         LoadErrorStr = erl_ddll:format_error(LoadError),
                         EStr = lists:flatten(
                                  io_lib:format("could not load driver ~s: ~p",
                                                [?SHLIB, LoadErrorStr])),
                         {stop, EStr}
                 end,
    case LoadResult of
        ok ->
            {ok, #state{}};
        Error ->
            Error
    end.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(stop, State) ->
    ok = nn_term(),
    case erl_ddll:try_unload(?SHLIB, [{monitor, pending_driver}]) of
        {ok, unloaded} ->
            {stop, normal, State};
        {ok, pending_driver} ->
            {noreply, State};
        {ok, pending_driver, Ref} ->
            {noreply, State#state{drvmonref=Ref}}
    end;
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'DOWN', Ref, driver, _, unloaded}, #state{drvmonref=Ref}=State) ->
    {stop, normal, State};
handle_info({'DOWN', _, driver, _, unloaded}, State) ->
    {stop, normal, State};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% internal functions
-spec socket(nntypename(), [nnurl()], [nnurl()], nnopenopts()) ->
                    {ok, nnsocket()} | {error, any()}.
socket(Type, [], [], Opts0) ->
    {Bind, Connect, Opts} = lists:foldl(fun({bind,_}=B, {Bind0, C, Opt}) ->
                                                {[B|Bind0], C, Opt};
                                           ({connect,_}=C, {B, Connect0, Opt}) ->
                                                {B, [C|Connect0], Opt};
                                           (Other, {B, C, Opt}) ->
                                                {B, C, [Other|Opt]}
                                  end, {[],[],[]}, Opts0),
    case {Bind, Connect} of
        {[],[]} ->
            open_socket(Type, Opts0);
        _ ->
            socket(Type, Bind, Connect, lists:reverse(Opts))
    end;
socket(Type, [{bind,Url}|_], [], Opts) ->
    case open_socket(Type, Opts) of
        {ok, Sock} ->
            case bind(Sock, Url) of
                {ok, _} ->
                    {ok, Sock};
                Error ->
                    close(Sock),
                    Error
            end;
        Error ->
            Error
    end;
socket(Type, [], [{connect,Url}|_], Opts) ->
    case open_socket(Type, Opts) of
        {ok, Sock} ->
            case connect(Sock, Url) of
                {ok, _} ->
                    {ok, Sock};
                Error ->
                    close(Sock),
                    Error
            end;
        Error ->
            Error
    end;
socket(Type, _, _, Opts) ->
    error(badarg, [Type, Opts]).

-spec call_control(nnsocket(), non_neg_integer(), binary()) -> {error, closed} | term().
call_control(Sock, Cmd, Bin) ->
    try
        binary_to_term(port_control(Sock, Cmd, Bin))
    catch
        error:badarg ->
            {error, closed}
    end.

-spec open_socket(nntypename(), nnopenopts()) -> {ok, nnsocket()} | {error, any()}.
open_socket(Type, Opts) ->
    Sock = erlang:open_port({spawn_driver, ?SHLIB}, [binary]),
    try
        case validate_opts(normalize_opts(Opts), Type) of
            OptBin when is_binary(OptBin) ->
                Protocol = protocol(Type),
                case binary_to_term(port_control(Sock, Protocol, OptBin)) of
                    ok ->
                        erlang:port_set_data(Sock, ?MODULE),
                        {ok, Sock};
                    Error ->
                        erlang:port_close(Sock),
                        Error
                end;
            Error ->
                erlang:port_close(Sock),
                Error
        end
    catch
        error:badarg ->
            erlang:port_close(Sock),
            error(badarg)
    end.

-spec protocol(nntypename()) -> non_neg_integer().
protocol(nnpair) -> ?ENM_PAIR;
protocol(nnreq) -> ?ENM_REQ;
protocol(nnrep) -> ?ENM_REP;
protocol(nnbus) -> ?ENM_BUS;
protocol(nnpub) -> ?ENM_PUB;
protocol(nnsub) -> ?ENM_SUB;
protocol(nnpush) -> ?ENM_PUSH;
protocol(nnpull) -> ?ENM_PULL;
protocol(nnsurveyor) -> ?ENM_SVYR;
protocol(nnrespondent) -> ?ENM_RESP.

-spec validate_opt_names(nnoptnames()) -> binary().
validate_opt_names(Opts) ->
    validate_opt_names(Opts, <<>>).
validate_opt_names([], Bin) ->
    Bin;
validate_opt_names([mode|Opts], Bin) ->
    validate_opt_names(Opts, <<Bin/binary, ?ENM_BINARY>>);
validate_opt_names([active|Opts], Bin) ->
    validate_opt_names(Opts, <<Bin/binary, ?ENM_ACTIVE>>);
validate_opt_names([type|Opts], Bin) ->
    validate_opt_names(Opts, <<Bin/binary, ?ENM_TYPE>>);
validate_opt_names([raw|Opts], Bin) ->
    validate_opt_names(Opts, <<Bin/binary, ?ENM_RAW>>);
validate_opt_names([deadline|Opts], Bin) ->
    validate_opt_names(Opts, <<Bin/binary, ?ENM_DEADLINE>>);
validate_opt_names([subscribe|Opts], Bin) ->
    validate_opt_names(Opts, <<Bin/binary, ?ENM_SUBSCRIBE>>);
validate_opt_names([unsubscribe|Opts], Bin) ->
    validate_opt_names(Opts, <<Bin/binary, ?ENM_UNSUBSCRIBE>>);
validate_opt_names([resend_ivl|Opts], Bin) ->
    validate_opt_names(Opts, <<Bin/binary, ?ENM_RESEND_IVL>>);
validate_opt_names([sndbuf|Opts], Bin) ->
    validate_opt_names(Opts, <<Bin/binary, ?ENM_SNDBUF>>);
validate_opt_names([rcvbuf|Opts], Bin) ->
    validate_opt_names(Opts, <<Bin/binary, ?ENM_RCVBUF>>);
validate_opt_names([nodelay|Opts], Bin) ->
    validate_opt_names(Opts, <<Bin/binary, ?ENM_NODELAY>>);
validate_opt_names([Opt|_], _) ->
    error(badarg, [Opt]).

-spec validate_opts(nnopenopts() | nnsetopts(), nntypename()) -> binary().
validate_opts(Opts, Type) ->
    validate_opts(Opts, Type, <<>>).
validate_opts([], _, Bin) ->
    Bin;
validate_opts([{mode,binary}|Opts], Type, Bin) ->
    validate_opts(Opts, Type, <<Bin/binary, ?ENM_BINARY, ?ENM_TRUE>>);
validate_opts([{mode,list}|Opts], Type, Bin) ->
    validate_opts(Opts, Type, <<Bin/binary, ?ENM_BINARY, ?ENM_FALSE>>);
validate_opts([{active,_}|_]=Opts, nnpush, Bin) ->
    error(badarg, [Opts, nnpush, Bin]);
validate_opts([{active,true}|Opts], Type, Bin) ->
    validate_opts(Opts, Type, <<Bin/binary, ?ENM_ACTIVE, ?ENM_TRUE>>);
validate_opts([{active,false}|Opts], Type, Bin) ->
    validate_opts(Opts, Type, <<Bin/binary, ?ENM_ACTIVE, ?ENM_FALSE>>);
validate_opts([{active,once}|Opts], Type, Bin) ->
    validate_opts(Opts, Type, <<Bin/binary, ?ENM_ACTIVE, ?ENM_ONCE>>);
validate_opts([{active,N}|Opts], Type, Bin) when N >= -32768, N =< 32767 ->
    validate_opts(Opts, Type, <<Bin/binary, ?ENM_ACTIVE, ?ENM_N, N:16/big>>);
validate_opts([{raw,true}|Opts], Type, Bin) ->
    validate_opts(Opts, Type, <<Bin/binary, ?ENM_RAW, ?ENM_TRUE>>);
validate_opts([{raw,false}|Opts], Type, Bin) ->
    validate_opts(Opts, Type, <<Bin/binary, ?ENM_RAW, ?ENM_FALSE>>);
validate_opts([{deadline,Ddline}|Opts], nnsurveyor, Bin) when is_integer(Ddline) ->
    validate_opts(Opts, nnsurveyor, <<Bin/binary, ?ENM_DEADLINE, Ddline:32/big>>);
validate_opts([{SubOrUnsub,Topic}|Opts]=AllOpts, nnsub, Bin)
  when (SubOrUnsub == subscribe orelse SubOrUnsub == unsubscribe) andalso
       (is_list(Topic) orelse is_binary(Topic)) ->
    Cmd = case SubOrUnsub of
              subscribe -> ?ENM_SUBSCRIBE;
              unsubscribe -> ?ENM_UNSUBSCRIBE
          end,
    case iolist_size(Topic) of
        Len when Len >= 256 ->
            error(badarg, [AllOpts, nnsub, Bin]);
        _ ->
            NewBin = list_to_binary([<<Bin/binary, Cmd>>, Topic, <<0>>]),
            validate_opts(Opts, nnsub, NewBin)
    end;
validate_opts([{resend_ivl,RI}|Opts], nnreq, Bin) when is_integer(RI), RI > 0 ->
    validate_opts(Opts, nnreq, <<Bin/binary, ?ENM_RESEND_IVL, RI:32/big>>);
validate_opts([{sndbuf,_}|_], Type, _Bin) when Type == nnpull; Type == nnsub ->
    {error,einval};
validate_opts([{sndbuf,Sndbuf}|Opts], Type, Bin) when is_integer(Sndbuf) ->
    validate_opts(Opts, Type, <<Bin/binary, ?ENM_SNDBUF, Sndbuf:32/big>>);
validate_opts([{rcvbuf,_}|_], Type, _Bin) when Type == nnpush; Type == nnpub ->
    {error, einval};
validate_opts([{rcvbuf,Rcvbuf}|Opts], Type, Bin) when is_integer(Rcvbuf) ->
    validate_opts(Opts, Type, <<Bin/binary, ?ENM_RCVBUF, Rcvbuf:32/big>>);
validate_opts([{nodelay,NoDelay}|Opts], Type, Bin) when is_boolean(NoDelay) ->
    Bool = case NoDelay of
               true -> ?ENM_TRUE;
               false -> ?ENM_FALSE
           end,
    validate_opts(Opts, Type, <<Bin/binary, ?ENM_NODELAY, Bool:8>>);
validate_opts(Opts, Type, Bin) ->
    error(badarg, [Opts, Type, Bin]).

normalize_opts(Opts) ->
    lists:map(fun(raw) -> {raw, true};
                 (binary) -> {mode, binary};
                 (list) -> {mode, list};
                 (Other) -> Other end, Opts).

wait_for_stop() ->
    timer:sleep(5),
    case whereis(?MODULE) of
        undefined ->
            ok;
        _ ->
            wait_for_stop()
    end.

nn_term() ->
    Port = erlang:open_port({spawn_driver, ?SHLIB}, [binary]),
    binary_to_term(port_control(Port, ?ENM_TERM, <<>>)).

transfer_unreceived_msgs(Sock, Type, Owner) ->
    receive
        {Type, Sock, _}=Msg ->
            Owner ! Msg,
            transfer_unreceived_msgs(Sock, Type, Owner)
    after
        0 ->
            ok
    end.

-spec url(nnurl()) -> binary().
url(Url) when Url == <<>>; Url == [] ->
    error(badarg, [Url]);
url(Url0) when is_binary(Url0); is_list(Url0) ->
    list_to_binary([Url0, <<0>>]);
url(#nn_inproc{addr=Addr}) when is_binary(Addr); is_list(Addr) ->
    list_to_binary([<<"inproc://">>, Addr, <<0>>]);
url(#nn_ipc{path=Path}) when is_binary(Path); is_list(Path) ->
    list_to_binary([<<"ipc://">>, Path, <<0>>]);
url(#nn_tcp{interface=undefined, addr=undefined, port=Port}) ->
    list_to_binary([<<"tcp://:">>, integer_to_list(Port), <<0>>]);
url(#nn_tcp{interface=any, addr=undefined, port=Port}) ->
    list_to_binary([<<"tcp://*:">>, integer_to_list(Port), <<0>>]);
url(#nn_tcp{interface=Intf}=Url) when is_tuple(Intf) ->
    try inet_parse:ntoa(Intf) of
        ListIntf ->
            url(Url#nn_tcp{interface=ListIntf})
    catch
        _:_ ->
            error(badarg, [Url])
    end;
url(#nn_tcp{interface=Intf0, addr=undefined, port=Port}) ->
    Intf = getintf(Intf0),
    list_to_binary([<<"tcp://">>, Intf, $:, integer_to_list(Port), <<0>>]);
url(#nn_tcp{addr=Addr}=Url) when is_tuple(Addr) ->
    try inet_parse:ntoa(Addr) of
        ListAddr ->
            url(Url#nn_tcp{addr=ListAddr})
    catch
        _:_ ->
            error(badarg, [Url])
    end;
url(#nn_tcp{interface=undefined, addr=Addr0, port=Port}) ->
    Addr = getaddr(Addr0),
    list_to_binary([<<"tcp://">>, Addr, $:, integer_to_list(Port), <<0>>]);
url(#nn_tcp{interface=Intf0, addr=Addr0, port=Port}) ->
    Intf = getintf(Intf0),
    Addr = getaddr(Addr0),
    list_to_binary([<<"tcp://[">>, Intf, <<"]:">>,
                    Addr, $:, integer_to_list(Port), <<0>>]).

getintf(Intf) when is_list(Intf) ->
    try
        getaddr(Intf)
    catch
        error:badarg ->
            {ok, Intfs} = inet:getifaddrs(),
            case lists:member(Intf, [IfNm || {IfNm, _} <- Intfs]) of
                true ->
                    Intf;
                false ->
                    error(badarg, [Intf])
            end
    end;
getintf(Intf) ->
    error(badarg, [Intf]).

getaddr(Addr) when is_list(Addr) ->
    case inet:getaddr(Addr, inet) of
        {ok, TupleV4} ->
            inet_parse:ntoa(TupleV4);
        _ ->
            case inet:getaddr(Addr, inet6) of
                {ok, TupleV6} ->
                    inet_parse:ntoa(TupleV6);
                _ ->
                    %% check if Addr is an interface name
                    error(badarg, [Addr])
            end
    end;
getaddr(Addr) ->
    error(badarg, [Addr]).

%% Internal tests
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

url_test() ->
    ?assertMatch(<<"inproc://foo",0>>, url(#nn_inproc{addr="foo"})),
    ?assertMatch(<<"ipc:///tmp/file",0>>, url(#nn_ipc{path= <<"/tmp/file">>})),
    ?assertMatch(<<"tcp://*:1234",0>>, url(#nn_tcp{interface=any, port=1234})),
    ?assertMatch(<<"tcp://127.0.0.1:1234",0>>,
                 url(#nn_tcp{interface={127,0,0,1}, port=1234})),
    ?assertMatch(<<"tcp://192.168.1.1:1234",0>>,
                 url(#nn_tcp{addr={192,168,1,1}, port=1234})),
    ?assertMatch(<<"tcp://::1:1234",0>>,
                 url(#nn_tcp{addr={0,0,0,0,0,0,0,1}, port=1234})),
    ?assertMatch(<<"tcp://:1234",0>>, url(#nn_tcp{port=1234})),
    ?assertMatch(<<"tcp://[127.0.0.1]:127.0.0.1:4321",0>>,
                 url(#nn_tcp{interface="127.0.0.1", addr={127,0,0,1}, port=4321})),
    ok = try url(#nn_tcp{interface=any})
         catch
             error:badarg -> ok
         end,
    ok = try url(#nn_tcp{addr={192,168,1,1}})
         catch
             error:badarg -> ok
         end,
    ok.

close_test_() ->
    {setup,
     fun start_link/0,
     fun(_) -> stop() end,
     [fun close_twice/0,
      fun close_send/0,
      fun close_recv/0,
      fun close_bind/0,
      fun close_connect/0,
      fun close_shutdown/0,
      fun close_getopts/0,
      fun close_setopts/0,
      fun close_ctrlproc/0]}.

close_twice() ->
    {ok,Sock} = enm:pair(),
    %% verify multiple calls to close just return ok
    ok = enm:close(Sock),
    ok = enm:close(Sock),
    ok.

close_send() ->
    {ok,Sock} = enm:pair(),
    ok = enm:close(Sock),
    {error, closed} = enm:send(Sock, "foo"),
    ok.

close_recv() ->
    {ok,Sock} = enm:pair(),
    ok = enm:close(Sock),
    {error, closed} = enm:recv(Sock),
    ok.

close_bind() ->
    {ok,Sock} = enm:pair(),
    ok = enm:close(Sock),
    {error, closed} = enm:bind(Sock, "inproc://foo"),
    ok.

close_connect() ->
    {ok,Sock} = enm:pair(),
    ok = enm:close(Sock),
    {error, closed} = enm:connect(Sock, "inproc://foo"),
    ok.

close_shutdown() ->
    {ok,Sock} = enm:pair(),
    {ok,Id} = enm:bind(Sock, "inproc://foo"),
    ok = enm:close(Sock),
    {error, closed} = enm:shutdown(Sock, Id),
    ok.

close_getopts() ->
    {ok,Sock} = enm:pair(),
    ok = enm:close(Sock),
    {error, closed} = enm:getopts(Sock, [active]),
    ok.

close_setopts() ->
    {ok,Sock} = enm:pair(),
    ok = enm:close(Sock),
    {error, closed} = enm:setopts(Sock, [{active,false}]),
    ok.

close_ctrlproc() ->
    {ok,Sock} = enm:pair(),
    ok = enm:close(Sock),
    {error, closed} = enm:controlling_process(Sock, self()),
    ok.

-endif.
