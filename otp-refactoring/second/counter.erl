-module(counter).
-author("centelles").

-import(get_server_lite, [start/2, rpc/2]).
%% API
-export([start/0, tick/1, read/0, handle/2]).

start() -> start(counter, 0).

tick(N) -> rpc(counter, {tick, N}).
read() -> rpc(counter, read).

handle({tick, N}, State) -> {ack, State + N};
handle(read, State) -> {State, State}.

