%% Copyright (c) 2011, Loïc Hoguin <essen@dev-extend.eu>
%%
%% Permission to use, copy, modify, and/or distribute this software for any
%% purpose with or without fee is hereby granted, provided that the above
%% copyright notice and this permission notice appear in all copies.
%%
%% THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
%% WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
%% MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
%% ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
%% WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
%% ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
%% OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

-module(http_SUITE).

-include_lib("common_test/include/ct.hrl").

-export([all/0, groups/0, init_per_suite/1, end_per_suite/1,
	init_per_group/2, end_per_group/2]). %% ct.
-export([chunked_response/1, headers_dupe/1, headers_huge/1,
	keepalive_nl/1, max_keepalive/1, nc_rand/1, nc_zero/1,
	pipeline/1, raw/1, set_resp_header/1, set_resp_overwrite/1,
	set_resp_body/1, stream_body_set_resp/1, response_as_req/1]). %% http.
-export([http_200/1, http_404/1, file_200/1, file_403/1,
	dir_403/1, file_404/1, file_400/1]). %% http and https.
-export([http_10_hostless/1]). %% misc.
-export([rest_simple/1, rest_keepalive/1]). %% rest.

%% ct.

all() ->
	[{group, http}, {group, https}, {group, misc}, {group, rest}].

groups() ->
	BaseTests = [http_200, http_404, file_200, file_403, dir_403, file_404,
		file_400],
	[{http, [], [chunked_response, headers_dupe, headers_huge,
		keepalive_nl, max_keepalive, nc_rand, nc_zero, pipeline, raw,
		set_resp_header, set_resp_overwrite,
		set_resp_body, response_as_req, stream_body_set_resp] ++ BaseTests},
	{https, [], BaseTests},
	{misc, [], [http_10_hostless]},
	{rest, [], [rest_simple, rest_keepalive]}].

init_per_suite(Config) ->
	application:start(inets),
	application:start(cowboy),
	Config.

end_per_suite(_Config) ->
	application:stop(cowboy),
	application:stop(inets),
	ok.

init_per_group(http, Config) ->
	Port = 33080,
	Config1 = init_static_dir(Config),
	cowboy:start_listener(http, 100,
		cowboy_tcp_transport, [{port, Port}],
		cowboy_http_protocol, [{max_keepalive, 50},
			{dispatch, init_http_dispatch(Config1)}]
	),
	[{scheme, "http"}, {port, Port}|Config1];
init_per_group(https, Config) ->
	Port = 33081,
	Config1 = init_static_dir(Config),
	application:start(crypto),
	application:start(public_key),
	application:start(ssl),
	DataDir = ?config(data_dir, Config),
	cowboy:start_listener(https, 100,
		cowboy_ssl_transport, [
			{port, Port}, {certfile, DataDir ++ "cert.pem"},
			{keyfile, DataDir ++ "key.pem"}, {password, "cowboy"}],
		cowboy_http_protocol, [{dispatch, init_https_dispatch(Config1)}]
	),
	[{scheme, "https"}, {port, Port}|Config1];
init_per_group(misc, Config) ->
	Port = 33082,
	cowboy:start_listener(misc, 100,
		cowboy_tcp_transport, [{port, Port}],
		cowboy_http_protocol, [{dispatch, [{'_', [
			{[], http_handler, []}
	]}]}]),
	[{port, Port}|Config];
init_per_group(rest, Config) ->
	Port = 33083,
	cowboy:start_listener(reset, 100,
		cowboy_tcp_transport, [{port, Port}],
		cowboy_http_protocol, [{dispatch, [{'_', [
			{[<<"simple">>], rest_simple_resource, []}
	]}]}]),
	[{port, Port}|Config].

end_per_group(https, Config) ->
	cowboy:stop_listener(https),
	application:stop(ssl),
	application:stop(public_key),
	application:stop(crypto),
	end_static_dir(Config),
	ok;
end_per_group(Listener, Config) ->
	cowboy:stop_listener(Listener),
	end_static_dir(Config),
	ok.

%% Dispatch configuration.

init_http_dispatch(Config) ->
	[
		{[<<"localhost">>], [
			{[<<"chunked_response">>], chunked_handler, []},
			{[<<"init_shutdown">>], http_handler_init_shutdown, []},
			{[<<"long_polling">>], http_handler_long_polling, []},
			{[<<"headers">>, <<"dupe">>], http_handler,
				[{headers, [{<<"Connection">>, <<"close">>}]}]},
			{[<<"set_resp">>, <<"header">>], http_handler_set_resp,
				[{headers, [{<<"Vary">>, <<"Accept">>}]}]},
			{[<<"set_resp">>, <<"overwrite">>], http_handler_set_resp,
				[{headers, [{<<"Server">>, <<"DesireDrive/1.0">>}]}]},
			{[<<"set_resp">>, <<"body">>], http_handler_set_resp,
				[{body, <<"A flameless dance does not equal a cycle">>}]},
			{[<<"stream_body">>, <<"set_resp">>], http_handler_stream_body,
				[{reply, set_resp}, {body, <<"stream_body_set_resp">>}]},
			{[<<"static">>, '...'], cowboy_http_static,
				[{directory, ?config(static_dir, Config)},
				 {mimetypes, [{<<".css">>, [<<"text/css">>]}]}]},
			{[], http_handler, []}
		]}
	].

init_https_dispatch(Config) ->
	init_http_dispatch(Config).


init_static_dir(Config) ->
	Dir = filename:join(?config(priv_dir, Config), "static"),
	Level1 = fun(Name) -> filename:join(Dir, Name) end,
	ok = file:make_dir(Dir),
	ok = file:write_file(Level1("test_file"), "test_file\n"),
	ok = file:write_file(Level1("test_file.css"), "test_file.css\n"),
	ok = file:write_file(Level1("test_noread"), "test_noread\n"),
	ok = file:change_mode(Level1("test_noread"), 8#0333),
	ok = file:make_dir(Level1("test_dir")),
	[{static_dir, Dir}|Config].

end_static_dir(Config) ->
	Dir = ?config(static_dir, Config),
	Level1 = fun(Name) -> filename:join(Dir, Name) end,
	ok = file:delete(Level1("test_file")),
	ok = file:delete(Level1("test_file.css")),
	ok = file:delete(Level1("test_noread")),
	ok = file:del_dir(Level1("test_dir")),
	ok = file:del_dir(Dir),
	Config.

%% http.

chunked_response(Config) ->
	{ok, {{"HTTP/1.1", 200, "OK"}, _Headers, "chunked_handler\r\nworks fine!"}} =
		httpc:request(build_url("/chunked_response", Config)).

headers_dupe(Config) ->
	{port, Port} = lists:keyfind(port, 1, Config),
	{ok, Socket} = gen_tcp:connect("localhost", Port,
		[binary, {active, false}, {packet, raw}]),
	ok = gen_tcp:send(Socket, "GET /headers/dupe HTTP/1.1\r\n"
		"Host: localhost\r\nConnection: keep-alive\r\n\r\n"),
	{ok, Data} = gen_tcp:recv(Socket, 0, 6000),
	{_Start, _Length} = binary:match(Data, <<"Connection: close">>),
	nomatch = binary:match(Data, <<"Connection: keep-alive">>),
	{error, closed} = gen_tcp:recv(Socket, 0, 1000).

headers_huge(Config) ->
	Cookie = lists:flatten(["whatever_man_biiiiiiiiiiiig_cookie_me_want_77="
		"Wed Apr 06 2011 10:38:52 GMT-0500 (CDT)" || _N <- lists:seq(1, 40)]),
	{_Packet, 200} = raw_req(["GET / HTTP/1.0\r\nHost: localhost\r\n"
		"Set-Cookie: ", Cookie, "\r\n\r\n"], Config).

keepalive_nl(Config) ->
	{port, Port} = lists:keyfind(port, 1, Config),
	{ok, Socket} = gen_tcp:connect("localhost", Port,
		[binary, {active, false}, {packet, raw}]),
	ok = keepalive_nl_loop(Socket, 10),
	ok = gen_tcp:close(Socket).

keepalive_nl_loop(_Socket, 0) ->
	ok;
keepalive_nl_loop(Socket, N) ->
	ok = gen_tcp:send(Socket, "GET / HTTP/1.1\r\n"
		"Host: localhost\r\nConnection: keep-alive\r\n\r\n"),
	{ok, Data} = gen_tcp:recv(Socket, 0, 6000),
	{0, 12} = binary:match(Data, <<"HTTP/1.1 200">>),
	nomatch = binary:match(Data, <<"Connection: close">>),
	ok = gen_tcp:send(Socket, "\r\n"), %% extra nl
	keepalive_nl_loop(Socket, N - 1).

max_keepalive(Config) ->
	{port, Port} = lists:keyfind(port, 1, Config),
	{ok, Socket} = gen_tcp:connect("localhost", Port,
		[binary, {active, false}, {packet, raw}]),
	ok = max_keepalive_loop(Socket, 50),
	{error, closed} = gen_tcp:recv(Socket, 0, 1000).

max_keepalive_loop(_Socket, 0) ->
	ok;
max_keepalive_loop(Socket, N) ->
	ok = gen_tcp:send(Socket, "GET / HTTP/1.1\r\n"
		"Host: localhost\r\nConnection: keep-alive\r\n\r\n"),
	{ok, Data} = gen_tcp:recv(Socket, 0, 6000),
	{0, 12} = binary:match(Data, <<"HTTP/1.1 200">>),
	case N of
		1 -> {_, _} = binary:match(Data, <<"Connection: close">>);
		N -> nomatch = binary:match(Data, <<"Connection: close">>)
	end,
	keepalive_nl_loop(Socket, N - 1).

nc_rand(Config) ->
	nc_reqs(Config, "/dev/urandom").

nc_zero(Config) ->
	nc_reqs(Config, "/dev/zero").

nc_reqs(Config, Input) ->
	Cat = os:find_executable("cat"),
	Nc = os:find_executable("nc"),
	case {Cat, Nc} of
		{false, _} ->
			{skip, {notfound, cat}};
		{_, false} ->
			{skip, {notfound, nc}};
		_Good ->
			%% Throw garbage at the server then check if it's still up.
			{port, Port} = lists:keyfind(port, 1, Config),
			[nc_run_req(Port, Input) || _N <- lists:seq(1, 100)],
			Packet = "GET / HTTP/1.0\r\nHost: localhost\r\n\r\n",
			{Packet, 200} = raw_req(Packet, Config)
	end.

nc_run_req(Port, Input) ->
	os:cmd("cat " ++ Input ++ " | nc localhost " ++ integer_to_list(Port)).

pipeline(Config) ->
	{port, Port} = lists:keyfind(port, 1, Config),
	{ok, Socket} = gen_tcp:connect("localhost", Port,
		[binary, {active, false}, {packet, raw}]),
	ok = gen_tcp:send(Socket,
		"GET / HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n"
		"GET / HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n"
		"GET / HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n"
		"GET / HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n"
		"GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"),
	Data = pipeline_recv(Socket, <<>>),
	Reqs = binary:split(Data, << "\r\n\r\nhttp_handler" >>, [global, trim]),
	5 = length(Reqs),
	pipeline_check(Reqs).

pipeline_check([]) ->
	ok;
pipeline_check([Req|Tail]) ->
	<< "HTTP/1.1 200", _Rest/bits >> = Req,
	pipeline_check(Tail).

pipeline_recv(Socket, SoFar) ->
	case gen_tcp:recv(Socket, 0, 6000) of
		{ok, Data} ->
			pipeline_recv(Socket, << SoFar/binary, Data/binary >>);
		{error, closed} ->
			ok = gen_tcp:close(Socket),
			SoFar
	end.

raw_req(Packet, Config) ->
	{port, Port} = lists:keyfind(port, 1, Config),
	{ok, Socket} = gen_tcp:connect("localhost", Port,
		[binary, {active, false}, {packet, raw}]),
	ok = gen_tcp:send(Socket, Packet),
	Res = case gen_tcp:recv(Socket, 0, 6000) of
		{ok, << "HTTP/1.1 ", Str:24/bits, _Rest/bits >>} ->
			list_to_integer(binary_to_list(Str));
		{error, Reason} ->
			Reason
	end,
	gen_tcp:close(Socket),
	{Packet, Res}.

raw(Config) ->
	Huge = [$0 || _N <- lists:seq(1, 5000)],
	Tests = [
		{"\r\n\r\n\r\n\r\n\r\nGET / HTTP/1.1\r\nHost: localhost\r\n\r\n", 200},
		{"\n", 400},
		{"Garbage\r\n\r\n", 400},
		{"\r\n\r\n\r\n\r\n\r\n\r\n", 400},
		{"GET / HTTP/1.1\r\nHost: dev-extend.eu\r\n\r\n", 400},
		{"", closed},
		{"\r\n", closed},
		{"\r\n\r\n", closed},
		{"GET / HTTP/1.1", closed},
		{"GET / HTTP/1.1\r\n", 408},
		{"GET / HTTP/1.1\r\nHost: localhost", 408},
		{"GET / HTTP/1.1\r\nHost: localhost\r\n", 408},
		{"GET / HTTP/1.1\r\nHost: localhost\r\n\r", 408},
		{"GET http://localhost/ HTTP/1.1\r\n\r\n", 501},
		{"GET / HTTP/1.2\r\nHost: localhost\r\n\r\n", 505},
		{"GET /init_shutdown HTTP/1.1\r\nHost: localhost\r\n\r\n", 666},
		{"GET /long_polling HTTP/1.1\r\nHost: localhost\r\n\r\n", 102},
		{Huge, 413},
		{"GET / HTTP/1.1\r\n" ++ Huge, 413}
	],
	[{Packet, StatusCode} = raw_req(Packet, Config)
		|| {Packet, StatusCode} <- Tests].

set_resp_header(Config) ->
	{port, Port} = lists:keyfind(port, 1, Config),
	{ok, Socket} = gen_tcp:connect("localhost", Port,
		[binary, {active, false}, {packet, raw}]),
	ok = gen_tcp:send(Socket, "GET /set_resp/header HTTP/1.1\r\n"
		"Host: localhost\r\nConnection: close\r\n\r\n"),
	{ok, Data} = gen_tcp:recv(Socket, 0, 6000),
	{_, _} = binary:match(Data, <<"Vary: Accept">>),
	{_, _} = binary:match(Data, <<"Set-Cookie: ">>).

set_resp_overwrite(Config) ->
	{port, Port} = lists:keyfind(port, 1, Config),
	{ok, Socket} = gen_tcp:connect("localhost", Port,
		[binary, {active, false}, {packet, raw}]),
	ok = gen_tcp:send(Socket, "GET /set_resp/overwrite HTTP/1.1\r\n"
		"Host: localhost\r\nConnection: close\r\n\r\n"),
	{ok, Data} = gen_tcp:recv(Socket, 0, 6000),
	{_Start, _Length} = binary:match(Data, <<"Server: DesireDrive/1.0">>).

set_resp_body(Config) ->
	{port, Port} = lists:keyfind(port, 1, Config),
	{ok, Socket} = gen_tcp:connect("localhost", Port,
		[binary, {active, false}, {packet, raw}]),
	ok = gen_tcp:send(Socket, "GET /set_resp/body HTTP/1.1\r\n"
		"Host: localhost\r\nConnection: close\r\n\r\n"),
	{ok, Data} = gen_tcp:recv(Socket, 0, 6000),
	{_Start, _Length} = binary:match(Data, <<"\r\n\r\n"
		"A flameless dance does not equal a cycle">>).

response_as_req(Config) ->
	Packet =
"HTTP/1.0 302 Found
Location: http://www.google.co.il/
Cache-Control: private
Content-Type: text/html; charset=UTF-8
Set-Cookie: PREF=ID=568f67013d4a7afa:FF=0:TM=1323014101:LM=1323014101:S=XqctDWC65MzKT0zC; expires=Tue, 03-Dec-2013 15:55:01 GMT; path=/; domain=.google.com
Date: Sun, 04 Dec 2011 15:55:01 GMT
Server: gws
Content-Length: 221
X-XSS-Protection: 1; mode=block
X-Frame-Options: SAMEORIGIN

<HTML><HEAD><meta http-equiv=\"content-type\" content=\"text/html;charset=utf-8\">
<TITLE>302 Moved</TITLE></HEAD><BODY>
<H1>302 Moved</H1>
The document has moved
<A HREF=\"http://www.google.co.il/\">here</A>.
</BODY></HTML>",
	{Packet, 400} = raw_req(Packet, Config).

stream_body_set_resp(Config) ->
	{port, Port} = lists:keyfind(port, 1, Config),
	{ok, Socket} = gen_tcp:connect("localhost", Port,
		[binary, {active, false}, {packet, raw}]),
	ok = gen_tcp:send(Socket, "GET /stream_body/set_resp HTTP/1.1\r\n"
		"Host: localhost\r\nConnection: close\r\n\r\n"),
	{ok, Data} = gen_tcp:recv(Socket, 0, 6000),
	{_Start, _Length} = binary:match(Data, <<"stream_body_set_resp">>).


%% http and https.

build_url(Path, Config) ->
	{scheme, Scheme} = lists:keyfind(scheme, 1, Config),
	{port, Port} = lists:keyfind(port, 1, Config),
	Scheme ++ "://localhost:" ++ integer_to_list(Port) ++ Path.

http_200(Config) ->
	{ok, {{"HTTP/1.1", 200, "OK"}, _Headers, "http_handler"}} =
		httpc:request(build_url("/", Config)).

http_404(Config) ->
	{ok, {{"HTTP/1.1", 404, "Not Found"}, _Headers, _Body}} =
		httpc:request(build_url("/not/found", Config)).

file_200(Config) ->
	{ok, {{"HTTP/1.1", 200, "OK"}, Headers, "test_file\n"}} =
		httpc:request(build_url("/static/test_file", Config)),
	"application/octet-stream" = ?config("content-type", Headers),

	{ok, {{"HTTP/1.1", 200, "OK"}, Headers1, "test_file.css\n"}} =
		httpc:request(build_url("/static/test_file.css", Config)),
	"text/css" = ?config("content-type", Headers1).

file_403(Config) ->
	{ok, {{"HTTP/1.1", 403, "Forbidden"}, _Headers, _Body}} =
		httpc:request(build_url("/static/test_noread", Config)).

dir_403(Config) ->
	{ok, {{"HTTP/1.1", 403, "Forbidden"}, _Headers, _Body}} =
		httpc:request(build_url("/static/test_dir", Config)),
	{ok, {{"HTTP/1.1", 403, "Forbidden"}, _Headers, _Body}} =
		httpc:request(build_url("/static/test_dir/", Config)).

file_404(Config) ->
	{ok, {{"HTTP/1.1", 404, "Not Found"}, _Headers, _Body}} =
		httpc:request(build_url("/static/not_found", Config)).

file_400(Config) ->
	{ok, {{"HTTP/1.1", 400, "Bad Request"}, _Headers, _Body}} =
		httpc:request(build_url("/static/%2f", Config)),
	{ok, {{"HTTP/1.1", 400, "Bad Request"}, _Headers1, _Body1}} =
		httpc:request(build_url("/static/%2e", Config)),
	{ok, {{"HTTP/1.1", 400, "Bad Request"}, _Headers2, _Body2}} =
		httpc:request(build_url("/static/%2e%2e", Config)).
%% misc.

http_10_hostless(Config) ->
	Packet = "GET / HTTP/1.0\r\n\r\n",
	{Packet, 200} = raw_req(Packet, Config).

%% rest.

rest_simple(Config) ->
	Packet = "GET /simple HTTP/1.1\r\nHost: localhost\r\n\r\n",
	{Packet, 200} = raw_req(Packet, Config).

rest_keepalive(Config) ->
	{port, Port} = lists:keyfind(port, 1, Config),
	{ok, Socket} = gen_tcp:connect("localhost", Port,
		[binary, {active, false}, {packet, raw}]),
	ok = rest_keepalive_loop(Socket, 100),
	ok = gen_tcp:close(Socket).

rest_keepalive_loop(_Socket, 0) ->
	ok;
rest_keepalive_loop(Socket, N) ->
	ok = gen_tcp:send(Socket, "GET /simple HTTP/1.1\r\n"
		"Host: localhost\r\nConnection: keep-alive\r\n\r\n"),
	{ok, Data} = gen_tcp:recv(Socket, 0, 6000),
	{0, 12} = binary:match(Data, <<"HTTP/1.1 200">>),
	nomatch = binary:match(Data, <<"Connection: close">>),
	rest_keepalive_loop(Socket, N - 1).