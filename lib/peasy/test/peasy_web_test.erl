-module(peasy_web_test).

-include_lib("eunit/include/eunit.hrl").
-include("headers.hrl").

-export([announce/1, torrent_status/1, peers/2]).

accept_announce_started_test() ->
	gen_event:start({global, announce_manager}),
	Parms = [
		{"info_hash", "INFOHASH"},
		{"peer_id", "PEERID"},
		{"port", "9090"},
		{"event", "started"},
		{"uploaded","0"},
		{"downloaded","0"},
		{"left","10000"}
	],
	%% ?MODULE is added at the end so that this module is executed instead of 'db' 
	Response = peasy_web:handle_announce("127.0.0.1", Parms, {33, 44, ?MODULE}),
	io:format("~p~n",[Response]),
	?assertEqual({200, [{"Content-Type","text/plain"},{"Content-Length",91}],
				  <<"d8:completei150e10:incompletei999e8:intervali33e12:min intervali441e5:peers12:",
					$a:8,$b:8,$c:8,$d:8,8080:16,$a:8,$b:8,$c:8,$d:8,8080:16,"e">>},
				 Response).

%% Mock functions for db module
announce(_Peer) ->
	ok.

%torrent_status(_InfoHash) ->
%	{torrent_status, 0, 0, 0}.

%torrent_peers(_InfoHash, _NumWant) ->
%	{torrent_peers, []}.

%% mock function for torrent_info module
torrent_status(InfoHash) ->
	{torrent_status,150, 999, 0}.

peers(InfoHash, Numwant) ->
	{torrent_peers, [<<$a:8,$b:8,$c:8,$d:8,8080:16,$a:8,$b:8,$c:8,$d:8,8080:16>>]}.

