-module(counter).
-author("centelles").

%% API
%% We need to export the loop function because that is
%% the function that is spawned
-export([start/0, loop/1, tick/1, read/0]).

start() -> register(counter, spawn(counter, loop, [0])).

tick(N) -> rpc({tick, N}).
read() -> rpc(read).

loop(State) ->
  receive
    {From, Tag, {tick, N}} ->
      From ! {Tag, ack},
      loop(State + N);
    {From, Tag, read} ->
      From ! State,
      loop(State)
  end.

%% Remote procedure call
rpc(Query) ->
  Tag = make_ref(),
  counter ! {self(), Tag, Query},
  receive
    {Tag, Reply} -> Reply
  end.
