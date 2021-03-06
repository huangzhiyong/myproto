%% -*- erlang; utf-8 -*-
-module(server_test).
-author('Max Lapshin <max@maxidoors.ru>').

-compile(export_all).

% required for eunit to work
-include_lib("eunit/include/eunit.hrl").
-include("myproto.hrl").


%%====================================================================
%% Test cases
%%====================================================================


select_simple_test() ->
  {ok, LSocket} = gen_tcp:listen(0, [binary, {packet, 0}, {active, false}, {reuseaddr, true}]),
  {ok, ListenPort} = inet:port(LSocket),
  Client = spawn_link(fun() ->
    {ok, Sock} = nanomysql:connect("mysql://user:pass@127.0.0.1:"++integer_to_list(ListenPort)++"/dbname"),
    Query1 = "SELECT input,output FROM minute_stats WHERE source='net' AND time >= '2013-09-05' AND time < '2013-09-06'",
    {ok, {Columns1, Rows1}} = nanomysql:execute(Query1, Sock),
    [{<<"input">>,_}, {<<"output">>,_}] = Columns1,
    [
      [<<"20">>,20],
      [<<"30">>,30],
      [<<"40">>,undefined]
    ] = Rows1,
    ok
  end),
  erlang:monitor(process, Client),
  {ok, Sock} = gen_tcp:accept(LSocket),
  My0 = my_protocol:init([{socket,Sock}]),
  {ok, My1} = my_protocol:hello(42, My0),
  {ok, #request{info = #user{}}, My2} = my_protocol:next_packet(My1),
  {ok, My3} = my_protocol:ok(My2),

  {ok, #request{info = #select{} = Select}, My4} = my_protocol:next_packet(My3),
  #select{
    params = [#key{name = <<"input">>},#key{name = <<"output">>}],
    tables = [#table{name = <<"minute_stats">>}],
    conditions = #condition{nexo = nexo_and, op1 = 
      #condition{nexo = eq, op1 = #key{name = <<"input">>},op2 = #value{value = <<"net">>}
    }}
  },

  ResponseFields = {
    [
      #column{name = <<"input">>, type=?TYPE_VARCHAR, length=20},
      #column{name = <<"output">>, type=?TYPE_LONG, length = 8}
    ],
    [
      [<<"20">>, 20],
      [<<"30">>, 30],
      [<<"40">>, undefined]
    ]
  },
  Response = #response{status=?STATUS_OK, info = ResponseFields},
  {ok, My5} = my_protocol:send_or_reply(Response, My4),
  receive {'DOWN', _, _, Client, Reason} -> normal = Reason end,
  ok.




reject_password_test() ->
  {ok, LSocket} = gen_tcp:listen(0, [binary, {packet, 0}, {active, false}, {reuseaddr, true}]),
  {ok, ListenPort} = inet:port(LSocket),
  Client = spawn_link(fun() ->
    {error,{1045,<<"password rejected">>}} = nanomysql:connect("mysql://user:pass@127.0.0.1:"++integer_to_list(ListenPort)++"/dbname"),
    ok
  end),
  erlang:monitor(process, Client),
  {ok, Sock} = gen_tcp:accept(LSocket),
  My0 = my_protocol:init([{socket,Sock}]),
  {ok, My1} = my_protocol:hello(42, My0),
  {ok, #request{info = #user{}}, My2} = my_protocol:next_packet(My1),
  {ok, My3} = my_protocol:error(<<"password rejected">>, My2),

  receive {'DOWN', _, _, Client, Reason} -> normal = Reason end,
  ok.


very_long_query_test() ->
  Value = binary:copy(<<"0123456789">>, 2177721),
  Query = iolist_to_binary(["INSERT INTO photos (data) VALUES ('", Value, "')"]),

  {ok, LSocket} = gen_tcp:listen(0, [binary, {packet, 0}, {active, false}, {reuseaddr, true}]),
  {ok, ListenPort} = inet:port(LSocket),
  Client = spawn_link(fun() ->
    {ok, Sock} = nanomysql:connect("mysql://user:pass@127.0.0.1:"++integer_to_list(ListenPort)++"/dbname"),
    nanomysql:execute(Query, Sock),
    ok
  end),
  erlang:monitor(process, Client),
  {ok, Sock} = gen_tcp:accept(LSocket),
  My0 = my_protocol:init([{socket,Sock},{parse_query,false}]),
  {ok, My1} = my_protocol:hello(42, My0),
  {ok, #request{info = #user{}}, My2} = my_protocol:next_packet(My1),
  {ok, My3} = my_protocol:ok(My2),

  {ok, #request{info = Query}, My4} = my_protocol:next_packet(My3),

  ResponseFields = {
    [#column{name = <<"id">>, type=?TYPE_LONG, length = 8}],
    [[20]]
  },
  Response = #response{status=?STATUS_OK, info = ResponseFields},
  {ok, My5} = my_protocol:send_or_reply(Response, My4),


  % receive {'DOWN', _, _, Client, Reason} -> normal = Reason end,
  ok.



