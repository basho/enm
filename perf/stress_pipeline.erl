%% -------------------------------------------------------------------
%%
%% stress_pipeline: stress test for pipeline protocol over TCP
%% run it as:
%% > erl -pa ebin
%% > c("perf/stress_pipeline.erl",[{o, "perf"}]),
%% > stress_pipeline:start().
%% -------------------------------------------------------------------
-module(stress_pipeline).

-export([start/0]).

start()->
  enm:start_link(),
  test_payload(make_message("test", 100), 1000),
  test_payload(make_message("test", 1000), 1000),
  test_payload(make_message("test", 2000), 1000).

test_payload(Msg, Count) ->
  Url = "tcp://127.0.0.1:" ++ integer_to_list(port()),
  spawn(fun() -> acceptor(Url) end),
  %timer:sleep(1000),
  spawn(fun() -> sender(Url, Msg, Count) end).

% Server
acceptor(Url) ->
  {ok, Socket} = enm:pull([{bind, Url}]),
  io:format("accepting on socket: ~p~n", [Socket]),
  listen(Socket, 0).

listen(Socket, Count) ->
  receive
      {nnpull, Socket, <<"quit">>} ->
        io:format("Quitting server : ~p. Total Msg received: ~p ~n", [Socket, Count]),
        enm:close(Socket);
      {nnpull, Socket, _Message} ->
        listen(Socket, Count+1)
  after 5000 -> % 5 second timeout
      io:format("Timeout server : ~p. Total Msg received: ~p ~n", [Socket, Count]),
      enm:close(Socket)
  end.

% Client
sender(Url, Message, Count) ->
 {ok, Socket} = enm:push([{connect, Url}]),
 send(Socket, Message, Count).
 
 send(Socket, Message, 0) ->
  io:format("Quitting client: ~p. All messages sent. Size: ~p ~n", [Socket, byte_size(Message)]),
  ok=enm:send(Socket, <<"quit">>),
  timer:sleep(1000),
  enm:close(Socket);
send(Socket, Message, Count) ->
  case enm:send(Socket, Message) of
    ok ->
      send(Socket, Message, Count-1);
     {error, closed}->
        io:format("ERROR: Socket closed prematurely. Messages left: ~p, Size = ~p bytes ~n", [Count, byte_size(Message)]),
        exit(self(), killed)
  end.

%% Make message of "Size" bytes. 
make_message(Message, Size) ->
  case byte_size(term_to_binary(Message)) > Size of
    true ->
      term_to_binary(Message); 
    false ->
    make_message(lists:flatten([ Message | Message]), Size)
  end.

port() ->
 (catch lists:foldl(
                    fun(P, _) ->
                            case gen_tcp:connect("localhost", P, []) of
                                {error, econnrefused} ->
                                    throw(P);
                                {ok, S} ->
                                    gen_tcp:close(S),
                                    P;
                                _ ->
                                    P
                            end
                    end, ok, lists:seq(47000,60000))).