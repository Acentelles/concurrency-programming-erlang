-module(balancer).
-author("centelles").

%% API
-export([start/0, allocate/0, deallocate/1, loop/1, track/0]).

start() ->
  register(balancer,
    spawn(balancer, loop, [server_one])),
  register(server_one,
    spawn(frequency, init, [[10,11,12,13,14,15]])),
  register(server_two,
    spawn(frequency, init, [[20,21,22,23,24,25]])).

next(server_one) ->
  server_two;
next(server_two) ->
  server_one.

allocate() ->
  server_request(allocate).

deallocate(Freq) ->
  server_request({deallocate, Freq}).

track() ->
  server_request(track).

server_request(Msg) ->
  balancer ! {request, self(), Msg},
  receive
    {reply, Reply} -> Reply
  end.

loop(S) ->
  receive
    {request, _Pid, allocate} = R ->
      Server = whereis(S),
      Server ! R,
      loop(next(S));
    {request, _Pid, {deallocate, Freq}} = R ->
      case correct_server(Freq) of
        out_of_range -> bad_freq_request;
        Server ->
          Server ! R
      end,
      loop(next(S));
    {request, _Pid, track} = R ->
      Server = whereis(S),
      Server ! R,
      loop(next(S))
  end.

correct_server(Freq) when Freq >= 10, Freq =< 15 ->
  server_one;
correct_server(Freq) when Freq >= 20, Freq =< 25 ->
  server_two;
correct_server(_Freq) ->
  out_of_range.


