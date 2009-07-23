-module(peasy_web).

-import(mochiweb).

-include("headers.hrl").

%% API
-export([start_link/1, stop/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

start_link(Port) ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [Port], []).

init([Port]) ->
  process_flag(trap_exit, true),
  io:format("~p (~p) starting...~n", [?MODULE, self()]),
  mochiweb_http:start([{port, Port},
		       {loop, fun(Req) -> dispatch_requests(Req) end}]),
  erlang:monitor(process, mochiweb_http),
  {ok, [45, 30]}.

stop() ->
	mochiweb_http:stop(). 

dispatch_requests(HttpRequest) ->
	{Action,_,_} = mochiweb_util:urlsplit_path(HttpRequest:get(path)),
	handle(Action, HttpRequest).

handle("/announce", HttpRequest) ->
		ClientIp = HttpRequest:get(peer),
		Req = parse_req(ClientIp, HttpRequest:parse_qs()),
		Peer = Req#req.peer,
		print_req(Req),
		
		% store announce data (async call, returns immediately - does not block waiting for response)
		db:announce(Peer),
		{InfoHash, _PeerId} = Peer#peer.peer_key,
		
		%% load stats and peer list
		%% TODO: both this calls should NOT go straight to the database,
		%% but invoke one or two specific servers. 
		{torrent_stats, Complete, Incomplete} = db:torrent_stats(InfoHash),
		{torrent_peers, Peers} = db:torrent_peers(InfoHash, Req#req.numwant),
		
		io:format("Stats: complete:~p incomplete: ~p.~n",[Complete,Incomplete]),
		PeerStr = peers_str(Peers,[]),
		Response = build_respose(10, 20, <<"123456">>, Complete, Incomplete, PeerStr),
		
		io:format("Response ~s~n----~n----~n",[Response]),
		HttpRequest:respond({200, [{"Content-Type", "text/plain"},{"Content-Length", size(Response)}], Response});

handle(_Unknown, Req) ->
	Req:respond({404, [{"Content-Type","text/plain"}], "404"}).

peers_str([], Rt) ->
	Rt;
peers_str([Peer|Peers], Rt) ->
	io:format("Peer: ~p to list ~p~n", [Peer,binary_to_list(Peer)]),
	peers_str(Peers, binary_to_list(Peer)++Rt).

build_respose(Interval, MinInterval, _TrackerId, Complete, Incomplete, Peers) ->
		subst("d8:completei~pe10:incompletei~pe8:intervali~pe12:min intervali~p1e5:peers~p:~se",
			  [Complete,Incomplete,Interval,MinInterval,length(Peers), Peers]).

%% packs ip and port in a 6-byte binary (4 ip, 2 port)
%% as it
binary_ip({ok,{A,B,C,D}}, Port) ->
	<<A:8,B:8,C:8,D:8,Port:16>>.

print_req(Req) ->
	#peer{peer_key={Hash,Id}, last_event=Event, uploaded=Up, downloaded=Down, left=Left} = Req#req.peer,
	io:format("REQUEST: event:~p Torr:~s Peer:~s  up:~p down:~p left:~p.~n", [Event, hex:bin_to_hexstr(Hash), hex:bin_to_hexstr(Id), Up, Down, Left]).

parse_req(Ip, HttpParams) ->
	#req{
		compact = case proplists:get_value("compact", HttpParams) of
				% use compact if not defined
				undefined -> 1;
				"0" -> 0;
				"1" -> 1
		end,
		no_peer_id = case proplists:get_value("no_peer_id", HttpParams) of
				undefined -> undefined;
				Any -> 1
		end,
		trackerid = case proplists:get_value("trackerid", HttpParams) of
				undefined -> undefined;
				Any -> Any
		end,
		numwant = case proplists:get_value("numwant",HttpParams) of
				undefined -> 50;
				Any -> list_to_integer(Any)
		end,
		peer = #peer {
			peer_key = {
				list_to_binary(proplists:get_value("info_hash", HttpParams)),
				list_to_binary(proplists:get_value("peer_id", HttpParams))
			},
			last_seen = erlang:now(),
			last_event = case proplists:get_value("event", HttpParams) of
				undefined -> undefined;
				Any -> list_to_atom(Any)
			end,
			uploaded = list_to_integer(proplists:get_value("uploaded", HttpParams)),
			downloaded = list_to_integer(proplists:get_value("downloaded", HttpParams)),
			left = list_to_integer(proplists:get_value("left", HttpParams)),
			ip_port = binary_ip(
				inet_parse:address(
					case proplists:get_value("ip", HttpParams) of
						undefined -> Ip;
						Any -> Any
					end),
				list_to_integer(proplists:get_value("port", HttpParams))),
			key = case proplists:get_value("key", HttpParams) of
					undefined -> undefined;
					Any -> Any
				end		 
		}
	}.

subst(Template, Values) when is_list(Values) ->
  list_to_binary(lists:flatten(io_lib:fwrite(Template, Values))).

handle_call(_Request, _From, State) ->
  Reply = ok,
  {reply, Reply, State}.

handle_cast(stop, State) ->
  {stop, normal, State};

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info({'DOWN', _, _, {mochiweb_http, _}, _}, State) ->
  {stop, normal, State};

handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, _State) ->
  mochiweb_http:stop(),
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.