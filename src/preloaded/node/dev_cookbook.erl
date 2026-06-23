%%% @doc Prototype renderer device for HyperBEAM `/info' docs payloads.
%%%
%%% `hb_docs' discovers and assembles documentation data. This device owns the
%%% renderer-facing contract: HTML negotiation, page dispatch, and the
%%% protocol-native cookbook surface.
-module(dev_cookbook).
-specification("../../../specs/cookbook@1.0.md").
-implements(<<"cookbook@1.0">>).
-export([info/1, info/3]).
-export([index/3, node/3, device/3, schema/3, spec/3, recipes/3]).
-export([render/3, respond_html_or_json/4, unsupported_device_response/2]).
-export([renderer_metadata/0]).

-define(DEFAULT_DEVICE, <<"message@1.0">>).

-spec info(#{ _ => _ }) -> #{ exports := [binary()] }.
info(_Opts) ->
    #{
        exports => [
            <<"info">>,
            <<"index">>,
            <<"node">>,
            <<"device">>,
            <<"schema">>,
            <<"spec">>,
            <<"recipes">>
        ]
    }.

%% @doc Return docs for the cookbook renderer itself.
-spec info(#{ _ => _ }, #{ _ => _ }, #{ _ => _ }) -> {ok, _} | {error, _}.
info(_Base, Req, Opts) ->
    hb_docs:device_info(<<"cookbook@1.0">>, Req, Opts).

%% @doc Render the node documentation index.
-spec index(#{ _ => _ }, #{ _ => _ }, #{ _ => _ }) -> {ok, _} | {error, _}.
index(_Base, Req, Opts) ->
    {ok, hb_docs_cookbook:render(node, hb_docs:node_info_data(Opts), Req)}.

%% @doc Alias for `index/3'.
-spec node(#{ _ => _ }, #{ _ => _ }, #{ _ => _ }) -> {ok, _} | {error, _}.
node(Base, Req, Opts) ->
    index(Base, Req, Opts).

%% @doc Render documentation for the device named in the `for' parameter.
-spec device(#{ _ => _ }, #{ 'for' => binary(), _ => _ }, #{ _ => _ }) ->
    {ok, _} | {error, _}.
device(_Base, Req, Opts) ->
    hb_docs:device_info(requested_device(Req, Opts), Req, Opts).

%% @doc Render schema for the device named in the `for' parameter.
-spec schema(#{ _ => _ }, #{ 'for' => binary(), _ => _ }, #{ _ => _ }) ->
    {ok, _} | {error, _}.
schema(_Base, Req, Opts) ->
    hb_docs:device_info_route(requested_device(Req, Opts), [<<"schema">>], Req, Opts).

%% @doc Render spec for the device named in the `for' parameter.
-spec spec(#{ _ => _ }, #{ 'for' => binary(), _ => _ }, #{ _ => _ }) ->
    {ok, _} | {error, _}.
spec(_Base, Req, Opts) ->
    hb_docs:device_info_route(requested_device(Req, Opts), [<<"spec">>], Req, Opts).

%% @doc Render recipes for the device named in the `for' parameter.
-spec recipes(#{ _ => _ }, #{ 'for' => binary(), _ => _ }, #{ _ => _ }) ->
    {ok, _} | {error, _}.
recipes(_Base, Req, Opts) ->
    hb_docs:device_info_route(requested_device(Req, Opts), [<<"recipes">>], Req, Opts).

%% @doc Render a docs payload for the caller's preferred response format.
-spec render(atom(), map(), map()) -> map().
render(Kind, Data, Req) ->
    hb_docs_cookbook:render(Kind, Data, Req).

-spec respond_html_or_json(atom(), map(), map(), map()) -> {ok, map()}.
respond_html_or_json(Kind, HtmlData, JsonData, Req) ->
    hb_docs_cookbook:respond_html_or_json(Kind, HtmlData, JsonData, Req).

-spec unsupported_device_response(binary(), map()) -> map().
unsupported_device_response(Device, Req) ->
    hb_docs_cookbook:unsupported_device_response(Device, Req).

-spec renderer_metadata() -> map().
renderer_metadata() ->
    hb_docs_cookbook:renderer_metadata().

requested_device(Req, Opts) ->
    strip_device_prefix(
        hb_maps:get(
            <<"for">>,
            Req,
            hb_maps:get(<<"device-id">>, Req, ?DEFAULT_DEVICE, Opts),
            Opts
        )
    ).

strip_device_prefix(<<"~", Device/binary>>) ->
    Device;
strip_device_prefix(Device) ->
    Device.
