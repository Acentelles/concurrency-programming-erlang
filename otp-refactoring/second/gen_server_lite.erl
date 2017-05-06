%% Erlang has
%% - Four primitives for concurrency (spawn, send, receive, self)
%% - Timeouts
%% - register - whereis
%% - Trapping errors
%% - How to build our own concurrency abstractions
-module(gen_server_lite).
-author("centelles").

%% API
-export([start/2, loop/2, rpc/2]).

start(Mod, State) ->
  register(Mod, spawn(get_server_lite, loop, [Mod, State])).

loop(Mod, State) ->
  receive
    {From, Tag, Query} ->
      {Reply, State1} = Mod:handle(Query, State),
      From ! {Tag, Reply},
      loop(Mod, State1)
  end.

%% Remote procedure call
rpc(Mod, Query) ->
  Tag = make_ref(),
  Mod ! {self(), Tag, Query},
  receive
    {Tag, Reply} -> Reply
  end.
