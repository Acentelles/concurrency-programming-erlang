%% Simple example with otp
-module(gecho).
-behaviour(gen_server).
-compile(export_all).

start_link() ->
    gen_server:start_link(
		{local, ?MODULE}, 
		?MODULE, [], []).

count() ->
    gen_server:call(?MODULE,count).

echo(X) ->
    gen_server:call(?MODULE,X).

reset(N) ->
    gen_server:cast(?MODULE,{reset,N}).

stop() ->
    gen_server:stop(?MODULE).


init([]) ->
    {ok, 0}.

handle_call(count, _From, State) ->
    {reply, State, State};

handle_call(Msg, _From, State) ->
    {reply, Msg, State+1}.


handle_cast({reset,N}, _State) ->
    {noreply, N}.