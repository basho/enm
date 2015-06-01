%%% 
%%% Stress test enm pipeline.
%%%
-module(stress).

-export([start/0]).

start()->
  enm:start_link(),
  small_payload(),
  large_payload().

% smaller payload of 100 bytes
small_payload() ->
  Url = "tcp://127.0.0.1:" ++ integer_to_list(port()),
  spawn(fun() -> acceptor(Url) end),
  timer:sleep(1000),
  SmallMsg = make_message("test", 100), % 100 bytes
  spawn(fun() -> sender(Url, SmallMsg) end).

% larger payload > 1KB
large_payload() ->
  Url = "tcp://127.0.0.1:" ++ integer_to_list(port()),
  spawn(fun() -> acceptor(Url) end),
  timer:sleep(1000),
  LargeMsg = make_message("test", 2000), % 2KB
  spawn(fun() -> sender(Url, LargeMsg) end).

% Server
acceptor(Url) ->
  {ok, Socket} = enm:pull([{bind, Url}]),
  io:format("accepting on socket: ~p~n", [Socket]),
  listen(Socket, 0).

listen(Socket, Count) ->
  receive
      {nnpull, Socket, <<"quit">>} ->
        io:format("Quitting server : ~p~n", [Socket]),
        enm:close(Socket);
      {nnpull, Socket, _Message} ->
        %io:format("~p : ~p~n", [Socket, Count]),
        %timer:sleep(1),
        listen(Socket, Count+1)
  after 10000 ->
      io:format("Timeout server : ~p~n", [Socket]),
      enm:close(Socket)
  end.

% Client
sender(Url, Message) ->
 {ok, Client} = enm:push([{connect, Url}]),
 send(Client, Message, 1000).
 
 send(Socket, _Message, 0) ->
  io:format("Quitting client: ~p~n", [Socket]),
  ok=enm:send(Socket, <<"quit">>),
  timer:sleep(1000),
  enm:close(Socket);
send(Socket, Message, Tick) ->
  %io:format("sending ~p ~n", [Tick]),
  ok=enm:send(Socket, Message),
  send(Socket, Message, Tick-1).

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