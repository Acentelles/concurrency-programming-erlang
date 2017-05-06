-module(frequency).
%% Supervisor functions
-export([init/0, start/0]).
%% Server functions
-export([init_server/2, start_server/2]).
%% Client functions
% -export([allocate/0, deallocate/1, stop/0]).
-export([start_client/1, init_client/0]).

-type frequencies() :: {
  Free      :: [integer()],
  Allocated :: [{integer(), pid()}]
}.
%%% Supervisor functions %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec start() -> true.
start() ->
  io:format("Supervisor started.~n"),
  register(supervisor, spawn(frequency, init, [])).

-spec init() -> ok.
init() ->
  process_flag(trap_exit, true),
  Frequencies = {get_frequencies(), []},
  start_server(Frequencies, self()),
  loop(whereis(frequency), [Frequencies]),
  ok.

% Hard Coded
get_frequencies() -> [10, 11, 12, 13, 14, 15].

%%% Server functions %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec start_server(frequencies(), pid()) -> pid().
start_server(Frequencies, SupPid) ->
  io:format("Server started. Freq: ~p~n",[Frequencies]),
  ServerPid = spawn_link(frequency, init_server, [Frequencies, SupPid]),
  register(frequency, ServerPid),
  ServerPid.

-spec init_server(frequencies(), pid()) -> ok.
init_server(Frequencies = {_, []}, SupPid) ->
  process_flag(trap_exit, true),
  loop_server(Frequencies, SupPid),
  ok;
init_server(Frequencies = {_, [_|_]}, SupPid) ->
  process_flag(trap_exit, true),
  {_, Allocated} = Frequencies,
  %% Link again server and clients with allocated memory and update server pid.
  Fun = fun(Pid) ->
    link(Pid),
    Pid ! {request, update_pid, self()}
        end,
  lists:keymap(Fun, 2, Allocated),
  loop_server(Frequencies, SupPid),
  ok.

%%% Supervisor functions %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

loop(SPid, Frequencies) ->
  receive
    {request, SPid, NewFrequencies} ->
      loop(SPid, NewFrequencies);
    {request, kill_supervisor} ->
      %% Kill supervisor
      io:format("Supervisor: killed~n"),
      7/0;
    {request, shut_down_system} ->
      %% Message to shut down the supervisor and server
      io:format("Supervisor: shut down system~n"),
      exit(shut_down);
    {'EXIT', SPid, Reason} ->
      %% Frequency server has died
      io:format("Supervisor: Server (~p) exited, Reason: ~p~n", [SPid, Reason]),
      %% Restarting frequency server with actual Frequency state.
      loop(start_server(Frequencies, self()), Frequencies)
  end.

%%% Sever functions %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

loop_server(Frequencies, SupPid) ->
  receive
    {request, Pid, allocate} ->
      io:format("Server: Allocate request from ~p~n", [Pid]),
      {NewFrequencies, Reply} = allocate(Frequencies, Pid),
      io:format("Server: NewFrequencies ~p~n", [NewFrequencies]),
      supervisor ! {request, self(), NewFrequencies},
      Pid ! {reply, self(), Reply},
      loop_server(NewFrequencies, SupPid);
    {request, Pid , {deallocate, Freq}} ->
      io:format("Server: Deallocate request from ~p~n", [Pid]),
      {NewFrequencies, Reply} = deallocate(Frequencies, Freq),
      io:format("Server: NewFrequencies ~p~n", [NewFrequencies]),
      supervisor ! {request, self(), NewFrequencies},
      Pid ! {reply, self(), Reply},
      loop_server(NewFrequencies, SupPid);
    {request, Pid, stop} ->
      io:format("Server: Stop request from ~p~n", [Pid]),
      Pid ! {reply, self(), stopped};
    {request, shut_down} ->
      exit(shut_down);
    {request, kill} ->
      10/0;
    {'EXIT', Pid, Reason} ->
      case Pid of
        SupPid ->
          handle_server_exit(Reason);
        _ ->
          io:format("Server: Client (~p) exited, Reason: ~p~n", [Pid, Reason]),
          NewFrequencies = exited(Frequencies, Pid),
          io:format("Server: NewFrequencies ~p~n", [NewFrequencies]),
          loop_server(NewFrequencies, SupPid)
      end
  end.

%%% Client functions %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-spec start_client(atom()) -> true.
start_client(ClientName) ->
  register(ClientName, spawn(frequency, init_client, [])).

-spec init_client() -> ok.
init_client() ->
  process_flag(trap_exit, true),
  loop_client(whereis(frequency)),
  ok.

loop_client(Pid) ->
  receive
    {request, update_pid, ServerPid} ->
      loop_client(ServerPid);
    {request, allocation} ->
      {ActualPid, Reply} = allocate(),
      io:format("Client: ~p~n", [Reply]),
      loop_client(ActualPid);
    {request, deallocation, Freq} ->
      {ActualPid, Reply} = deallocate(Freq),
      io:format("Client: ~p~n", [Reply]),
      loop_client(ActualPid);
    {request, stop_client} ->
      client_stopped;
    {request, kill_client} ->
      7/0;
    {request, stop_server} ->
      {ActualPid, Reply} = stop(),
      io:format("Client: ~p~n", [Reply]),
      loop_client(ActualPid);
    {request, kill_server} ->
      frequency ! {request, kill},
      loop_client(Pid);
    {request, shut_down_system} ->
      frequency ! {request, shut_down},
      io:format("Client: Server shut down~n"),
      loop_client(Pid);
    {'EXIT', Pid, shut_down} ->
      io:format("Client: Server shut down system, Client shut down~n"),
      client_shut_down;
    {'EXIT', Pid, Reason} ->
      io:format("Client: Server stopped ~p~n", [Reason]),
      loop_client(Pid)
  end.

allocate() ->
  clear(),
  frequency ! {request, self(), allocate},
  receive
    {reply, Pid, Reply} -> {Pid, Reply}
  after
    200 -> allocate_timeout
  end.

deallocate(Freq) ->
  clear(),
  frequency ! {request, self(), {deallocate, Freq}},
  receive
    {reply, Pid, Reply} -> {Pid, Reply}
  after
    200 -> deallocate_timeout
  end.

stop() ->
  clear(),
  frequency ! {request, self(), stop},
  receive
    {reply, Pid, Reply} -> {Pid, Reply}
  after
    200 -> stop_timeout
  end.

%%% Private functions %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
handle_server_exit(shut_down) ->
  io:format("Server: Supervisor shut down system, Server shut down ~n"),
  exit(shut_down);
handle_server_exit(Reason) ->
  io:format("Server: Supervisor exited, Reason (~p), Server exit~n", [Reason]),
  server_stopped.

allocate({[], Allocated}, _Pid) ->
  {{[], Allocated}, {error, no_frequency}};
allocate(F = {[Freq | Free], Allocated}, Pid) ->
  case lists:keyfind(Pid, 2, Allocated) of
    {K, _} ->
      {F, {error, already_allocated, K}};
    false ->
      link(Pid),
      io:format("Server: ~p AND ~p are linked~n", [self(), Pid]),
      {{Free, [{Freq, Pid} | Allocated]}, {ok, Freq}}
  end.

deallocate({Free, Allocated}, Freq) ->
  case lists:keyfind(Freq, 1, Allocated) of
    {_, Pid} ->
      unlink(Pid),
      io:format("Server: ~p AND ~p are unlinked~n", [self(), Pid]),
      NewAllocated = lists:keydelete(Freq, 1, Allocated),
      {{[Freq | Free],  NewAllocated}, ok};
    false ->
      {{Free, Allocated}, {error, unexistent_frecuency}}
  end.

exited({Free, Allocated}, Pid) ->
  case lists:keyfind(Pid, 2, Allocated) of
    {Freq, Pid} ->
      NewAllocated = lists:keydelete(Freq, 1, Allocated),
      {[Freq | Free], NewAllocated};
    false ->
      {Free, Allocated}
  end.

clear() ->
  receive
    M ->
      io:format("Message erased: ~p~n", [M]),
      clear()
  after 0 ->
    stop
  end.

%%% Example of use %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 1> c(frequency).
%% frequency.erl:68: Warning: this expression will fail with a 'badarith' exception
%% frequency.erl:104: Warning: this expression will fail with a 'badarith' exception
%% frequency.erl:144: Warning: this expression will fail with a 'badarith' exception
%% {ok,frequency}
%% 2> frequency:start().
%% Supervisor started.
%% Server started. Freq: {[10,11,12,13,14,15],[]}
%% true
%% 3> frequency:start_client(c1).
%% true
%% 4> frequency:start_client(c2).
%% true
%% 5> frequency:start_client(c3).
%% true
%% 6> c1 ! {request, allocation}.
%% Server: Allocate request from <0.74.0>
%% {request,allocation}
%% Server: <0.72.0> AND <0.74.0> are linked
%% Server: NewFrequencies {[11,12,13,14,15],[{10,<0.74.0>}]}
%% Client: {ok,10}
%% 7> c2 ! {request, allocation}.
%% Server: Allocate request from <0.76.0>
%% {request,allocation}
%% Server: <0.72.0> AND <0.76.0> are linked
%% Server: NewFrequencies {[12,13,14,15],[{11,<0.76.0>},{10,<0.74.0>}]}
%% Client: {ok,11}
%% 8> c2 ! {request, allocation}.
%% Server: Allocate request from <0.76.0>
%% {request,allocation}
%% Server: NewFrequencies {[12,13,14,15],[{11,<0.76.0>},{10,<0.74.0>}]}
%% Client: {error,already_allocated,11}
%% 9> c3 ! {request, allocation}.
%% Server: Allocate request from <0.78.0>
%% {request,allocation}
%% Server: <0.72.0> AND <0.78.0> are linked
%% Server: NewFrequencies {[13,14,15],
%%                         [{12,<0.78.0>},{11,<0.76.0>},{10,<0.74.0>}]}
%% Client: {ok,12}
%% 10> c3 ! {request, deallocation, 12}.
%% Server: Deallocate request from <0.78.0>
%% {request,deallocation,12}
%% Server: <0.72.0> AND <0.78.0> are unlinked
%% Server: NewFrequencies {[12,13,14,15],[{11,<0.76.0>},{10,<0.74.0>}]}
%% Client: ok
%% 11> c1 ! {request, kill_server}.
%% Client: Server stopped {badarith,
%%                            [{frequency,loop_server,2,
%%                                 [{file,"frequency.erl"},{line,104}]},
%%                             {frequency,init_server,2,
%%                                 [{file,"frequency.erl"},{line,45}]}]}
%% Client: Server stopped {badarith,
%%                            [{frequency,loop_server,2,
%%                                 [{file,"frequency.erl"},{line,104}]},
%%                             {frequency,init_server,2,
%%                                 [{file,"frequency.erl"},{line,45}]}]}
%% Supervisor: Server (<0.72.0>) exited, Reason: {badarith,
%%                                                [{frequency,loop_server,2,
%%                                                  [{file,"frequency.erl"},
%%                                                   {line,104}]},
%%                                                 {frequency,init_server,2,
%%                                                  [{file,"frequency.erl"},
%%                                                   {line,45}]}]}
%% {request,kill_server}
%% Server started. Freq: {[12,13,14,15],[{11,<0.76.0>},{10,<0.74.0>}]}
%% 12>
%% =ERROR REPORT==== 20-Apr-2017::22:45:29 ===
%% Error in process <0.72.0> with exit value:
%% {badarith,[{frequency,loop_server,2,[{file,"frequency.erl"},{line,104}]},
%%            {frequency,init_server,2,[{file,"frequency.erl"},{line,45}]}]}
%% 
%% 12> whereis(frequency).
%% <0.85.0>
%% 13> c1 ! {request, deallocation, 10}.
%% Server: Deallocate request from <0.74.0>
%% {request,deallocation,10}
%% Server: <0.85.0> AND <0.74.0> are unlinked
%% Server: NewFrequencies {[10,12,13,14,15],[{11,<0.76.0>}]}
%% Client: ok
%% 14> c3 ! {request, allocation}.
%% Server: Allocate request from <0.78.0>
%% {request,allocation}
%% Server: <0.85.0> AND <0.78.0> are linked
%% Server: NewFrequencies {[12,13,14,15],[{10,<0.78.0>},{11,<0.76.0>}]}
%% Client: {ok,10}
%% 15> supervisor ! {request, shut_down_system}.
%% Supervisor: shut down system
%% {request,shut_down_system}
%% Server: Supervisor shut down system, Server shut down
%% Client: Server shut down system, Client shut down
%% Client: Server shut down system, Client shut down
%% 16>