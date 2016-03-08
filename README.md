`enm` is an
[Erlang port driver](http://www.erlang.org/doc/tutorial/c_portdriver.html)
that wraps the [nanomsg](http://nanomsg.org) C library, allowing Erlang
systems to communicate with other nanomsg endpoints. `enm` supports
idioms and approaches common to standard Erlang networking facilities such
as `gen_tcp` and `gen_udp`.

`enm` is currently based on version 0.4-beta of nanomsg, and `enm` itself
is new, so its features are experimental and subject to change.

## Starting and Stopping

You can start `enm` as a normal application, using
`application:start(enm)` and `application:stop(enm)`. You can also call
`enm:start_link/0` or `enm:start/0`, and call `enm:stop/0` to stop it.

## Just Open a Socket

`enm` supports all nanomsg scalability protocols and transports. You can
open a socket providing a particular scalability protocol using functions
named for each protocol. For example, the `enm:pair/0` function opens a
pair-type socket for one-to-one commucation, and the `enm:req/0` and
`enm:rep/0` functions open the request and reply ends, respectively, of the
`reqrep` scalability protocol. The arity 0 versions of the `enm`
scalability protocol functions listed below use default settings for the
open sockets, while the arity 1 versions allow a list of
[socket options](#socket-options) to be passed to control socket settings.

* `req`: open the request end of the `reqrep` protocol
* `rep`: open the reply end of the `reqrep` protocol
* `pair`: open a pair socket for one-to-one commucations
* `bus`: open a bus socket for many-to-many communications
* `pub`: open the publication end of the `pubsub` protocol
* `sub`: open the subscriber end of the `pubsub` protocol
* `push`: open the pushing end of the `pipeline` protocol
* `pull`: open the pulling end of the `pipeline` protocol
* `surveyor`: open the query end of the `survey` protocol
* `respondent`: open the response end of the `survey` protocol

If successful, these functions &mdash; both their arity 0 and arity 1
versions &mdash; all return `{ok,Socket}`.

Once opened, sockets can be bound or connected using the `enm:bind/2` or
`enm:connect/2` functions respectively. Bind and connect information can
alternatively be provided via [socket options](#socket-options) when
sockets are first opened via the functions listed above.

## Functions

In addition to the [scalability protocol functions](#just-open-a-socket),
`enm` supports the following functions:

* `send(Socket, Data)`: send `Data` on `Socket`. `Data` is an Erlang
  `iolist`, thus allowing lists of binaries and characters, or nested lists
  thereof, to be sent.
* `recv(Socket)`: receive data from `Socket`. This function blocks
  indefinitely until data arrive. Returns `{ok,Data}` on success, or an
  error tuple on failure. `Data` defaults to a binary unless the socket was
  opened in `list` mode or was set into `list` mode via `setopts/2`.
* `recv(Socket, Timeout)`: same as `recv/1` but if no data arrive within
  `Timeout` milliseconds, return `{error,etimedout}`.
* `bind(Socket, Address)`: bind `Socket` to `Address`, where `Address`
  supports one of the nanomsg transport types:
  [inproc](http://nanomsg.org/v0.4/nn_inproc.7.html),
  [ipc](http://nanomsg.org/v0.4/nn_ipc.7.html), or
  [TCP](http://nanomsg.org/v0.4/nn_tcp.7.html). `Address` can be either a
  string or binary using the nanomsg URL address format, such as
  `"inproc://foo"` to bind to an intraprocess address or `"tcp://*:12345"`
  to listen on all your host's network interfaces on port 12345, or it can
  be one of the `enm` [address record types](#address-record-types).
* `getopts(Socket, Options)`: return the current setting on `Socket` for
  each of the option names listed in `Options`. If successful, returns
  `{ok, OptionList}` where each element of the list provides the name and
  setting of one of the requested options. If `getopts` fails it return an
  error tuple.
* `setopts(Socket, OptionList)`: apply each of the option settings in
  `OptionList` to `Socket`. Returns `ok` if successful or an error tuple on
  failure.
* `controlling_process(Socket, Pid)`: the current controlling process for
  `Socket` can call this function to transfer its control to the process
  represented by `Pid`. The controlling process of a `Socket` is initially
  the one that opens it, and it's the one that receives data messages as
  Erlang messages if the socket is in an active mode.
* `shutdown(Socket, EndpointId)`: removes the endpoint associated with
  `EndpointId`, created via `bind/2` or `connect/2`, from `Socket`.
* `close(Socket)`: closes `Socket`.

If you're already familiar with standard Erlang networking capabilities,
you'll find these functions similar to functions supplied by standard
modules such as `gen_tcp`, `gen_udp` and `inet`.

## Address Record Types

To help avoid errors with mistyped string and binary address URLs, `enm`
provides three record types you can use for addresses instead:

* `#nn_inproc{addr=Address}`: for intra-process addresses. `Address` is a
  name in either string or binary form.
* `#nn_ipc{path=Path}`: for IPC addresses. `Path` can be either an absolute
  pathname or a pathname relative to the current working directory, in
  either string or binary form.
* `#nn_tcp{interface=Interface, addr=Address, port=Port}`: for TCP
  addresses. `Interface` can be the atom `any`, a network address in string
  or tuple form, or a string representing a network interface
  name. `Address` can be a hostname or a network address in either string
  or binary form. `Port` is a port number.

Using these types, which is completely optional, requires including the
`enm.hrl` file.

## Socket Options

`enm` supports several socket options that can be set either when the
socket is opened, or modified later during operation. Most socket options
can also be read from `enm` sockets. `enm` supports the following options:

* `type`: indicates the type of socket. For example, the `nnreq` type
  indicates a socket opened via the `req` function, and `nnsurveyor`
  indicates a socket implementing the query end of the `survey`
  protocol. This option can only be read from an `enm` socket and cannot
  be set.
* `active`: this controls how messages are delivered from an `enm` socket
  to its controlling Erlang process.
    * The default setting, `{active,true}`, means that the driver reads
      data from the socket as soon as they arrive and sends them as Erlang
      messages to the controlling process.
    * The `{active,false}` setting puts an `enm` socket in passive mode;
      data from such a socket are retrieved only via the `enm:recv/{1,2}`
      functions.
    * The `{active,once}` setting allows the driver to deliver one message
      from the socket to the controlling process, after which the socket
      flips automatically to `{active,false}` mode. This allows the
      application to receive nanomsg messages as Erlang messages only when
      it's ready to handle them.
    * The `{active,N}` mode, where `N` represents an integer, is similar to
      `{active,once}` mode except that it allows the driver to receive `N`
      messages on the socket and deliver them as Erlang messages to the
      controlling process before flipping the socket into `{active,false}`
      mode. When the socket flips to passive mode, `enm` sends a
      `{X_passive,Socket}` message to the controlling process, with the
      socket's actual type name substituted for "X" (for example,
      `{nnpair_passive, Socket}` if `Socket` is a `pair` socket).
* `raw`: this option, which defaults to false, controls whether the
  underlying nanomsg socket is opened with the `AF_SP` domain (the default,
  or set via `{raw,false}`) or the `AF_SP_RAW` domain (set via
  `{raw,true}`). Using the atom `raw` by itself is equivalent to
  `{raw,true}`. See the
  [nanomsg nn_socket man page](http://nanomsg.org/v0.4/nn_socket.3.html)
  for more details on the `AF_SP` and `AF_SP_RAW` socket domains.
* `mode`: this controls the form of the data delivered or retrieved from
  the socket. The default, `binary`, means that data from the socket are
  delivered to the application as Erlang binaries, whereas the `list`
  setting means socket data are delivered as Erlang lists. Using the atom
  `binary` by itself is equivalent to `{mode,binary}`, and `list` by itself
  is equivalent to `{mode,list}`.
* `bind`: this option allows you to open a socket and then immediately bind
  it to the given address. See the `bind`
  [function description](#functions) for more details on the allowable
  forms for the bind address. Note, however, that the bind endpoint
  identifier is thrown away in this case. If you need to later manage the
  endpoint via `shutdown`, use the `bind` function instead.
* `connect`: this option allows you open a socket and then immediately
  connect it to the given address. See the `connect`
  [function description](#functions) for more details on the allowable
  forms for the connect address. Note, however, that the connect endpoint
  identifier is thrown away in this case. If you need to later manage the
  endpoint via `shutdown`, use the `connect` function instead.
* `deadline`: for `surveyor` sockets, set the surveyor deadline to specify
  how long, in milliseconds, to wait for responses to arrive.
* `subscribe`: for `sub` sockets, subscribe to the named topic, specified
  either as a string or a binary. Topic names must be less than 256
  characters in length (this is an `enm` limit, not a nanomsg
  limit). Applying the `subscribe` option to a socket type other than `sub`
  results in a `badarg` exception.
* `unsubscribe`: for `sub` sockets, unsubscribe from the named topic,
  specified either as a string or a binary. As for the `subscribe` option,
  topic names must be less than 256 characters in length. Applying the
  `unsubscribe` option to a socket type other than `sub` results in a
  `badarg` exception.
* `resend_ivl`: for `req` sockets, set the request resend interval to
  specify how long, in milliseconds, to wait for a reply before resending
  the request. The default is 60000. Applying the `resend_ivl` option to a
  socket type other than `req` results in a `badarg` exception.
* `sndbuf`: set the send buffer size to the specified number of
  bytes. Applying this option to a socket that doesn't allow sending,
  specifically a `pull` or `sub` socket, results in a `badarg` exception.
* `rcvbuf`: set the receive buffer size to the specified number of
  bytes. Applying this option to a socket that doesn't allow receiving,
  specifically a `push` or `pub` socket, results in a `badarg` exception.
* `nodelay`: if true, set the `TCP_NODELAY` option on TCP sockets, or if
  false, clear it.
* `reconnect_ivl`: set the reconnect interval to specify how long, in
  milliseconds, to wait before attempting to reconnect a broken socket
  connection. The supplied value must be greater than 0, otherwise a
  `badarg` exception results. The default is 100.
* `reconnect_ivl_max`: set the maximum reconnect interval in
  milliseconds. If this value is greater than the default of 0, socket
  reconnection attempts will use exponential backoff starting with the
  socket's `reconnect_ivl` value and doubling it on each reconnection
  attempt, but will ensure the backoff value never exceeds the specified
  `reconnect_ivl_max` value. With the default value of 0, no exponential
  backoff is used, and only the `reconnect_ivl` setting controls
  reconnection wait time.

Currently, most but not all nanomsg socket options are implemented. Please
file an issue or submit a pull request if an option you need is missing.

## Examples

These following examples are based on
[Tim Dysinger's C examples](https://github.com/dysinger/nanomsg-examples),
but they produce somewhat different output. They are all run with `inproc`
addresses, thereby taking advantage of Erlang's lightweight processes
rather than using separate OS processes as for Tim's examples (though we
could easily do that with Erlang too).

Note also that each example explicitly starts and stops `enm` &mdash;
this is for exposition only, and is not something you'd do explicitly in an
actual Erlang application. The output shown comes from an interactive
Erlang shell, and it assumes `enm` beam files are on the shell's load
path.

You can find the code for these examples in the repository `examples`
directory.

### Pipeline

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

Here, note the pattern matching in the `receive` statements where we use
the data variables set for the sent messages as the data to be expected to
be received. We put each socket into `list` mode to ensure these pattern
matches succeed, given that `Send1` and `Send2` are strings. Note also that
both the type of the socket and the socket itself are part of the received
messages, allowing us to use matching to easily distinguish between what
each socket is receiving. If these expected patterns did not match what was
being sent, the `receive` statements would wait forever.

#### Pipeline Results

    1> c("examples/pipeline.erl", [{o,"examples"}]).
    {ok,pipeline}
    2> pipeline:start().
    pushing message "Hello, World!"
    pulling message "Hello, World!"
    pushing message "Goodbye."
    pulling message "Goodbye."
    ok

### Request/Reply

    -module(request_reply).
    -export([start/0]).

    start() ->
        enm:start_link(),
        Url = "inproc://request_reply",
        {ok,Rep} = enm:rep([{bind,Url}]),
        {ok,Req} = enm:req([{connect,Url}]),
        DateReq = <<"DATE">>,
        io:format("sending date request~n"),
        ok = enm:send(Req, DateReq),
        receive
            {nnrep,Rep,DateReq} ->
                io:format("received date request~n"),
                Now = httpd_util:rfc1123_date(),
                io:format("sending date ~s~n", [Now]),
                ok = enm:send(Rep, Now)
        end,
        receive
            {nnreq,Req,Date} ->
                io:format("received date ~s~n", [Date])
        end,
        enm:close(Req),
        enm:close(Rep),
        enm:stop().

This is similar to the [pipeline example](#pipeline) except that data flows
in both directions, and both sockets default to binary mode.

#### Request/Reply Results

    1> c("examples/request_reply.erl", [{o,"examples"}]).
    {ok,request_reply}
    2> request_reply:start().
    sending date request
    received date request
    sending date Tue, 09 Sep 2014 23:05:26 GMT
    received date Tue, 09 Sep 2014 23:05:26 GMT
    ok

### Pair

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

This code is a little more involved than previous examples because we spawn
two child processes that receive and send messages. Note how we use the
`{active,N}` socket mode for each end of the pair to eventually break out
of the recursive `send_recv/2` function, by using `enm:getopts/2` to
check for when each socket flips into `{active,false}` mode.

#### Pair Results

    1> c("examples/pair.erl",[{o,"examples"}]).
    {ok,pair}
    2> pair:start().
    Node0 sending "Node0"
    Node1 sending "Node1"
    Node0 received "Node1"
    Node1 received "Node0"
    Node1 sending "Node1"
    Node0 sending "Node0"
    Node0 received "Node1"
    Node1 received "Node0"
    Node1 sending "Node1"
    Node0 sending "Node0"
    Node0 received "Node1"
    Node1 received "Node0"
    ok

### Pub/Sub

    -module(pubsub).
    -export([start/0]).

    -define(COUNT, 3).

    start() ->
        enm:start_link(),
        Url = "inproc://pubsub",
        Pub = pub(Url),
        collect(subs(Url, self())),
        enm:close(Pub),
        enm:stop().

    pub(Url) ->
        {ok,Pub} = enm:pub([{bind,Url}]),
        spawn_link(fun() -> pub(Pub, ?COUNT) end),
        Pub.
    pub(_, 0) ->
        ok;
    pub(Pub, Count) ->
        Now = httpd_util:rfc1123_date(),
        io:format("publishing date \"~s\"~n", [Now]),
        ok = enm:send(Pub, ["DATE: ", Now]),
        timer:sleep(1000),
        pub(Pub, Count-1).

    subs(Url, Parent) ->
        subs(Url, Parent, ?COUNT, []).
    subs(_, _, 0, Acc) ->
        Acc;
    subs(Url, Parent, Count, Acc) ->
        {ok, Sub} = enm:sub([{connect,Url},{subscribe,"DATE:"},{active,false}]),
        Name = "Subscriber" ++ integer_to_list(Count),
        spawn_link(fun() -> sub(Sub, Parent, Name) end),
        subs(Url, Parent, Count-1, [Name|Acc]).
    sub(Sub, Parent, Name) ->
        case enm:recv(Sub, 2000) of
            {ok,Data} ->
                io:format("~s received \"~s\"~n", [Name, Data]),
                sub(Sub, Parent, Name);
            {error,etimedout} ->
                enm:close(Sub),
                Parent ! {done, Name},
                ok
        end.

    collect([Sub|Subs]) ->
        receive
            {done,Sub} ->
                collect(Subs)
        end;
    collect([]) ->
        ok.

This code sets up a publisher and 3 subscribers, and the publisher
publishes dates to the subscribers. It includes the text "DATE:" in each
message, and messages containing that text are what the subscribers are
looking to receive. Note the use of `{active,false}` mode for the
subscriber sockets; this is done because the Erlang process that creates
the sockets, known as the *controlling process* for the socket, is not the
same process that receives the messages. Only the controlling process can
receive messages in an active mode from a socket.

#### Pub/Sub Results

    1> c("examples/pubsub.erl", [{o,"examples"}]).
    {ok,pubsub}
    2> pubsub:start().
    publishing date "Tue, 09 Sep 2014 23:08:10 GMT"
    Subscriber3 received "DATE: Tue, 09 Sep 2014 23:08:10 GMT"
    Subscriber2 received "DATE: Tue, 09 Sep 2014 23:08:10 GMT"
    Subscriber1 received "DATE: Tue, 09 Sep 2014 23:08:10 GMT"
    publishing date "Tue, 09 Sep 2014 23:08:11 GMT"
    Subscriber3 received "DATE: Tue, 09 Sep 2014 23:08:11 GMT"
    Subscriber2 received "DATE: Tue, 09 Sep 2014 23:08:11 GMT"
    Subscriber1 received "DATE: Tue, 09 Sep 2014 23:08:11 GMT"
    publishing date "Tue, 09 Sep 2014 23:08:12 GMT"
    Subscriber3 received "DATE: Tue, 09 Sep 2014 23:08:12 GMT"
    Subscriber2 received "DATE: Tue, 09 Sep 2014 23:08:12 GMT"
    Subscriber1 received "DATE: Tue, 09 Sep 2014 23:08:12 GMT"
    ok

### Survey

    -module(survey).
    -export([start/0]).

    -define(COUNT, 3).

    start() ->
        enm:start_link(),
        Url = "inproc://survey",
        Self = self(),
        {ok,Survey} = enm:surveyor([{bind,Url},{deadline,3000}]),
        Clients = clients(Url, Self),
        ok = enm:send(Survey, httpd_util:rfc1123_date()),
        get_responses(Survey),
        wait_for_clients(Clients),
        enm:close(Survey),
        enm:stop().

    clients(Url, Parent) ->
        clients(Url, Parent, ?COUNT, []).
    clients(_, _, 0, Acc) ->
        Acc;
    clients(Url, Parent, Count, Acc) ->
        {ok, Respondent} = enm:respondent([{connect,Url},{active,false},list]),
        Name = "Respondent" ++ integer_to_list(Count),
        Pid = spawn_link(fun() -> client(Respondent, Name, Parent) end),
        clients(Url, Parent, Count-1, [Pid|Acc]).

    client(Respondent, Name, Parent) ->
        {ok,Msg} = enm:recv(Respondent, 5000),
        Date = httpd_util:convert_request_date(Msg),
        ok = enm:send(Respondent, term_to_binary(Date)),
        io:format("~s got \"~s\"~n", [Name, Msg]),
        Parent ! {done, self(), Respondent}.

    get_responses(Survey) ->
        get_responses(Survey, ?COUNT+1).
    get_responses(_, 0) ->
        ok;
    get_responses(Survey, Count) ->
        receive
            {nnsurveyor,Survey,BinResp} ->
                Response = binary_to_term(BinResp),
                io:format("received survey response ~p~n", [Response]);
            {nnsurveyor_deadline,Survey} ->
                io:format("survey has expired~n")
        end,
        get_responses(Survey, Count-1).

    wait_for_clients([Client|Clients]) ->
        receive
            {done,Client,Respondent} ->
                enm:close(Respondent),
                wait_for_clients(Clients)
        end;
    wait_for_clients([]) ->
        ok.

This example creates a surveyor, and several respondents connect to it. The
`{deadline,3000}` option used when creating the surveyor socket means
respondents have a maximum of 3 seconds to respond to any survey. The
surveyor sends out the survey, and then collects responses from each of the
respondents. When we hit the survey deadline, the controlling process for
the surveyor socket gets a `{nnsurveyor_deadline,Socket}` message.

#### Survey Results

    1> c("examples/survey.erl", [{o,"examples"}]).
    {ok,survey}
    2> survey:start().
    Respondent3 got "Tue, 09 Sep 2014 23:09:34 GMT"
    Respondent2 got "Tue, 09 Sep 2014 23:09:34 GMT"
    Respondent1 got "Tue, 09 Sep 2014 23:09:34 GMT"
    received survey response {{2014,9,9},{23,9,34}}
    received survey response {{2014,9,9},{23,9,34}}
    received survey response {{2014,9,9},{23,9,34}}
    survey has expired
    ok

### Bus

    -module(bus).
    -export([start/0]).

    -define(COUNT, 4).

    start() ->
        enm:start_link(),
        UrlBase = "inproc://bus",
        Buses = connect_buses(UrlBase),
        Pids = send_and_receive(Buses, self()),
        wait_for_pids(Pids),
        enm:stop().

    connect_buses(UrlBase) ->
        connect_buses(UrlBase, lists:seq(1,?COUNT), []).
    connect_buses(UrlBase, [1=Node|Nodes], Buses) ->
        Url = make_url(UrlBase, Node),
        {ok,Bus} = enm:bus([{bind,Url},{active,false}]),
        {ok,_} = enm:connect(Bus, make_url(UrlBase, 2)),
        {ok,_} = enm:connect(Bus, make_url(UrlBase, 3)),
        connect_buses(UrlBase, Nodes, [{Bus,Node}|Buses]);
    connect_buses(UrlBase, [?COUNT=Node|Nodes], Buses) ->
        Url = make_url(UrlBase, Node),
        {ok,Bus} = enm:bus([{bind,Url},{active,false}]),
        {ok,_} = enm:connect(Bus, make_url(UrlBase, 1)),
        connect_buses(UrlBase, Nodes, [{Bus,Node}|Buses]);
    connect_buses(UrlBase, [Node|Nodes], Buses) ->
        Url = make_url(UrlBase, Node),
        {ok,Bus} = enm:bus([{bind,Url},{active,false}]),
        Urls = [make_url(UrlBase,N) || N <- lists:seq(Node+1,?COUNT)],
        [{ok,_} = enm:connect(Bus,U) || U <- Urls],
        connect_buses(UrlBase, Nodes, [{Bus,Node}|Buses]);
    connect_buses(_, [], Buses) ->
        Buses.

    send_and_receive(Buses, Parent) ->
        send_and_receive(Buses, Parent, []).
    send_and_receive([{Bus,Id}|Buses], Parent, Acc) ->
        Pid = spawn_link(fun() -> bus(Bus, Id, Parent) end),
        send_and_receive(Buses, Parent, [Pid|Acc]);
    send_and_receive([], _, Acc) ->
        Acc.

    bus(Bus, Id, Parent) ->
        Name = "node"++integer_to_list(Id),
        io:format("node ~w sending \"~s\"~n", [Id, Name]),
        ok = enm:send(Bus, Name),
        collect(Bus, Id, Parent).

    collect(Bus, Id, Parent) ->
        case enm:recv(Bus, 1000) of
            {ok,Data} ->
                io:format("node ~w received \"~s\"~n", [Id, Data]),
                collect(Bus, Id, Parent);
            {error,etimedout} ->
                Parent ! {done, self(), Bus}
        end.

    wait_for_pids([Pid|Pids]) ->
        receive
            {done,Pid,Bus} ->
                enm:close(Bus),
                wait_for_pids(Pids)
        end;
    wait_for_pids([]) ->
        ok.

    make_url(Base,N) ->
        Base++integer_to_list(N).

In this example consisting of four nodes, each node is connected such that
it receives one message from each of the other nodes. Each node binds to
one bus address and connects to one or more of the other bus addresses
&mdash; for example, node 1 connects to nodes 2 and 3, and node 4 connects
only to node 1. This example uses `{active,false}` mode since the Erlang
processes calling `enm:recv/2` are not the controlling processes for the
receiving sockets.

#### Bus Results

    1> c("examples/bus", [{o,"examples"}]).
    {ok,bus}
    2> bus:start().
    node 4 sending "node4"
    node 3 sending "node3"
    node 2 sending "node2"
    node 1 sending "node1"
    node 3 received "node4"
    node 2 received "node4"
    node 1 received "node4"
    node 4 received "node3"
    node 3 received "node2"
    node 2 received "node3"
    node 1 received "node3"
    node 4 received "node2"
    node 3 received "node1"
    node 2 received "node1"
    node 1 received "node2"
    node 4 received "node1"
    ok
