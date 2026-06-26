%%% @doc Protocol-native documentation payloads for HyperBEAM.
-module(hb_docs).
-export([
    node_info/2,
    node_info_route/3,
    device_info/3,
    maybe_info_request/3,
    request_hook/2,
    is_node_info_request/2
]).
-export([device_info_route/4]).
-export([node_info_data/1, device_info_data/2]).
-export([
    render_node_html/1,
    render_device_html/1,
    render_schema_index_html/1,
    render_schema_key_html/1,
    render_schema_parameter_html/1,
    render_spec_html/1,
    render_spec_section_page_html/1,
    render_recipes_html/1,
    render_recipe_html/1,
    render_implementations_html/1,
    render_node_component_html/3,
    render_node_boilerplate_html/1,
    render_node_boilerplate_page_html/1,
    render_node_concepts_html/1,
    render_node_concept_html/1,
    render_unsupported_device_html/1,
    supported_device/1
]).

-include("include/hb.hrl").
-include_lib("eunit/include/eunit.hrl").

-define(ARWEAVE_DEVICE, <<"arweave@2.9">>).
-define(MESSAGE_DEVICE, <<"message@1.0">>).
-define(COOKBOOK_DEVICE, <<"cookbook@1.0">>).
-define(PACKAGED_DEVICE_DOCS_ROOT, ["docs", "cookbook", "device-docs"]).
-define(CARD_SUMMARY_MAX, 120).
-define(RECIPE_CARD_SUMMARY_MAX, 80).

%% @doc Return true when an inbound request addresses node-root `/docs`.
is_node_info_request([Base, Req], Opts) when is_map(Base), is_map(Req) ->
    not maps:is_key(<<"device">>, Base) andalso
        hb_path:hd(Req, Opts) =:= <<"docs">>;
is_node_info_request(_, _Opts) ->
    false.

%% @doc Route complete docs paths before AO-Core resolves the first docs key.
%% This keeps nested docs URLs such as `/~message@1.0/docs/schema/field` and
%% `/docs/schema/field` from resolving against the already-rendered
%% HTML response or a device-specific fallback.
maybe_info_request(Msgs, Req, Opts) ->
    case info_route(Msgs) of
        {node, Tail} -> {true, node_info_route(Tail, Req, Opts)};
        {device, Device, Tail} -> {true, device_info_route(Device, Tail, Req, Opts)};
        false -> false
    end.

request_hook(HookReq, Opts) ->
    Msgs = hb_maps:get(<<"body">>, HookReq, [], Opts),
    RawReq = hb_maps:get(<<"request">>, HookReq, #{}, Opts),
    Body =
        case info_route(Msgs) of
            {node, Tail} ->
                cookbook_route_request(<<"node">>, <<>>, Tail, RawReq);
            {device, Device, Tail} ->
                cookbook_route_request(<<"device">>, Device, Tail, RawReq);
            false ->
                Msgs
        end,
    {ok, #{ <<"body">> => Body }}.

cookbook_route_request(Kind, Device, Tail, RawReq) ->
    [
        #{ <<"device">> => ?COOKBOOK_DEVICE },
        #{
            <<"path">> => <<"route">>,
            <<"docs-kind">> => Kind,
            <<"docs-device">> => Device,
            <<"docs-tail">> => Tail,
            <<"request">> => RawReq
        }
    ].

info_route([Base, Info | Tail]) when is_map(Base), is_map(Info) ->
    case {maps:is_key(<<"device">>, Base), node_docs_tail(path_key(Info), Tail)} of
        {false, {ok, RouteTail}} -> {node, RouteTail};
        _ -> false
    end;
info_route([{as, Device, _Base}, Info | Tail]) when is_map(Info) ->
    case device_docs_tail(path_key(Info), Tail) of
        {ok, RouteTail} -> {device, Device, RouteTail};
        false -> false
    end;
info_route(_) ->
    false.

node_docs_tail(<<"docs">>, Tail) ->
    {ok, path_tail_keys(Tail)};
node_docs_tail(_, _Tail) ->
    false.

device_docs_tail(<<"docs">>, Tail) ->
    {ok, path_tail_keys(Tail)};
device_docs_tail(_, _Tail) ->
    false.

path_key(Msg) ->
    hb_maps:get(<<"path">>, Msg, <<>>, #{}).

path_tail_key(Msg) when is_map(Msg) ->
    path_key(Msg);
path_tail_key(Msg) when is_binary(Msg) ->
    Msg;
path_tail_key(_) ->
    <<>>.

path_tail_keys(Tail) ->
    [Key || Msg <- Tail, (Key = path_tail_key(Msg)) =/= <<>>].

supported_device(Device) ->
    supported_device(Device, #{}).

supported_device(Device, Opts) ->
    case docs_resolve_spec(Device, Opts) of
        {ok, SpecID} -> loaded_device_for_spec(Device, SpecID, Opts);
        _ -> false
    end.

node_info(Req, Opts) ->
    Data = node_info_data(Opts),
    {ok, hb_docs_cookbook:render(node, Data, Req)}.

device_info(Device, Req, Opts) ->
    case supported_device(Device, Opts) of
        true ->
            Data = device_info_data(Device, Opts),
            {ok, hb_docs_cookbook:render(device, Data, Req)};
        false ->
            {ok, unsupported_device_info_response(Device, Req)}
    end.

node_info_route([], Req, Opts) ->
    node_info(Req, Opts);
node_info_route([<<"assets">> | AssetPath], _Req, _Opts) ->
    docs_asset_response(AssetPath);
node_info_route([<<"schema">>], Req, Opts) ->
    Data = node_info_data(Opts),
    Payload = node_component_index(<<"node-schema-index">>, <<"schema">>, Data),
    respond_html_or_json(node_schema, Payload, Payload, Req);
node_info_route([<<"spec">>], Req, Opts) ->
    Data = node_info_data(Opts),
    Payload = node_component_index(<<"node-spec-index">>, <<"spec">>, Data),
    respond_html_or_json(node_spec, Payload, Payload, Req);
node_info_route([<<"recipes">>], Req, Opts) ->
    Data = node_info_data(Opts),
    Payload = node_component_index(<<"node-recipes-index">>, <<"recipes">>, Data),
    respond_html_or_json(node_recipes, Payload, Payload, Req);
node_info_route([<<"implementations">>], Req, Opts) ->
    Data = node_info_data(Opts),
    Payload = node_component_index(<<"node-implementations-index">>, <<"implementations">>, Data),
    respond_html_or_json(node_implementations, Payload, Payload, Req);
node_info_route([<<"guides">>], Req, _Opts) ->
    Payload = boilerplate_index(),
    respond_html_or_json(node_boilerplate, Payload, Payload, Req);
node_info_route([<<"introduction">> | Parts], Req, _Opts) ->
    boilerplate_page_response([<<"introduction">> | Parts], Req);
node_info_route([<<"forge">> | Parts], Req, _Opts) ->
    boilerplate_page_response([<<"forge">> | Parts], Req);
node_info_route([<<"processes">> | Parts], Req, _Opts) ->
    boilerplate_page_response([<<"processes">> | Parts], Req);
node_info_route([<<"boilerplate">> | _Parts], _Req, _Opts) ->
    {ok, not_found_response()};
node_info_route([<<"concepts">>], Req, Opts) ->
    Data = node_info_data(Opts),
    Payload = #{
        <<"kind">> => <<"node-concepts-index">>,
        <<"concepts">> => maps:get(<<"concepts">>, Data, #{})
    },
    respond_html_or_json(node_concepts, Payload, Payload, Req);
node_info_route([<<"concepts">>, Concept], Req, Opts) ->
    Data = node_info_data(Opts),
    Concepts = maps:get(<<"concepts">>, Data, #{}),
    case maps:get(Concept, Concepts, undefined) of
        undefined -> {ok, not_found_response()};
        Description ->
            Payload = #{
                <<"kind">> => <<"node-concept">>,
                <<"concept">> => Concept,
                <<"description">> => Description
            },
            respond_html_or_json(node_concept, Payload, Payload, Req)
    end;
node_info_route(_Tail, _Req, _Opts) ->
    {ok, not_found_response()}.

boilerplate_page_response(Parts, Req) ->
    case boilerplate_page_payload(Parts) of
        {ok, Payload} ->
            respond_html_or_json(node_boilerplate_page, Payload, Payload, Req);
        not_found ->
            {ok, not_found_response()}
    end.

device_info_route(Device, Tail, Req, Opts) ->
    case supported_device(Device, Opts) of
        true -> supported_device_info_route(Device, Tail, Req, Opts);
        false -> {ok, unsupported_device_info_response(Device, Req)}
    end.

supported_device_info_route(Device, [], Req, Opts) ->
    device_info(Device, Req, Opts);
supported_device_info_route(_Device, [<<"assets">> | AssetPath], _Req, _Opts) ->
    docs_asset_response(AssetPath);
supported_device_info_route(Device, [<<"schema">>], Req, Opts) ->
    Data = device_info_data(Device, Opts),
    Schema = maps:get(<<"schema">>, Data, #{}),
    respond_html_or_json(schema_index, Data, Schema, Req);
supported_device_info_route(Device, [<<"schema">>, Key], Req, Opts) ->
    Data = device_info_data(Device, Opts),
    Schema = maps:get(<<"schema">>, Data, #{}),
    case maps:get(Key, Schema, undefined) of
        undefined -> {ok, not_found_response()};
        KeySchema ->
            Payload = #{
                <<"device">> => maps:get(<<"device">>, Data, #{}),
                <<"device-data">> => Data,
                <<"key">> => Key,
                <<"schema">> => KeySchema
            },
            respond_html_or_json(schema_key, Payload, KeySchema, Req)
    end;
supported_device_info_route(Device, [<<"schema">>, Key, Param], Req, Opts) ->
    Data = device_info_data(Device, Opts),
    Schema = maps:get(<<"schema">>, Data, #{}),
    case maps:get(Key, Schema, undefined) of
        undefined ->
            {ok, not_found_response()};
        KeySchema ->
            Params = maps:get(<<"parameters">>, KeySchema, #{}),
            case maps:get(Param, Params, undefined) of
                undefined ->
                    {ok, not_found_response()};
                ParamSchema ->
                    Payload = #{
                        <<"device">> => maps:get(<<"device">>, Data, #{}),
                        <<"device-data">> => Data,
                        <<"key">> => Key,
                        <<"parameter">> => Param,
                        <<"schema">> => ParamSchema
                    },
                    respond_html_or_json(schema_parameter, Payload, ParamSchema, Req)
            end
    end;
supported_device_info_route(Device, [<<"spec">>], Req, Opts) ->
    Data = device_info_data(Device, Opts),
    Spec = maps:get(<<"spec">>, Data, #{}),
    respond_html_or_json(spec, Data, Spec, Req);
supported_device_info_route(Device, [<<"spec">>, SectionSlug], Req, Opts) ->
    Data = device_info_data(Device, Opts),
    Spec = maps:get(<<"spec">>, Data, #{}),
    case spec_section_lookup(Spec, SectionSlug) of
        undefined ->
            {ok, not_found_response()};
        {SectionSlug, Title} ->
            Payload = #{
                <<"device">> => maps:get(<<"device">>, Data, #{}),
                <<"device-data">> => Data,
                <<"section-id">> => SectionSlug,
                <<"section-title">> => Title,
                <<"spec">> => Spec
            },
            respond_html_or_json(spec_section, Payload, Payload, Req)
    end;
supported_device_info_route(Device, [<<"recipes">>], Req, Opts) ->
    Data = device_recipes_data(Device, Opts),
    Recipes = maps:get(<<"recipes">>, Data, #{}),
    respond_html_or_json(recipes, Data, Recipes, Req);
supported_device_info_route(Device, [<<"recipes">>, Slug], Req, Opts) ->
    Data = device_recipes_data(Device, Opts),
    Recipes = maps:get(<<"recipes">>, Data, #{}),
    case maps:get(Slug, Recipes, undefined) of
        undefined -> {ok, not_found_response()};
        Recipe ->
            Payload = #{
                <<"device">> => maps:get(<<"device">>, Data, #{}),
                <<"device-data">> => Data,
                <<"recipe">> => Recipe,
                <<"slug">> => Slug
            },
            respond_html_or_json(recipe, Payload, Recipe, Req)
    end;
supported_device_info_route(Device, [<<"implementations">>], Req, Opts) ->
    Data = device_info_data(Device, Opts),
    Implementations = maps:get(<<"implementations">>, Data, []),
    respond_html_or_json(implementations, Data, Implementations, Req);
supported_device_info_route(_Device, _Tail, _Req, _Opts) ->
    {ok, not_found_response()}.

respond_html_or_json(Kind, HtmlData, JsonData, Req) ->
    hb_docs_cookbook:respond_html_or_json(Kind, HtmlData, JsonData, Req).

not_found_response() ->
    #{
        <<"status">> => 404,
        <<"content-type">> => <<"application/json">>,
        <<"body">> => <<"{\"error\":\"not found\"}">>
    }.

unsupported_device_info_response(Device, Req) ->
    hb_docs_cookbook:unsupported_device_response(Device, Req).

docs_node_device(DeviceID, Name, Version, Summary) ->
    #{
        <<"name">> => Name,
        <<"version">> => Version,
        <<"href">> => device_info_path(DeviceID),
        <<"summary">> => Summary,
        <<"schema">> => device_schema_path(DeviceID),
        <<"spec">> => device_spec_path(DeviceID),
        <<"recipes">> => device_recipes_path(DeviceID)
    }.

node_device_shortcut_links() ->
    #{}.

node_info_data(Opts) ->
    maps:merge(node_device_shortcut_links(), #{
        <<"kind">> => <<"node-info">>,
        <<"node">> => node_href(Opts),
        <<"summary">> =>
            <<"HyperBEAM documentation for the spec-loaded devices this node "
                "can resolve and run.">>,
        <<"renderer">> => cookbook_renderer(),
        <<"boilerplate-link">> => <<"/docs/guides">>,
        <<"devices">> => on_weave_node_devices(Opts),
        <<"boilerplate">> => boilerplate_index(),
        <<"concepts">> => #{
            <<"hyperbeam">> =>
                <<"A node runtime for AO-Core messages, devices, and "
                    "path-addressed computation.">>,
            <<"ao-core">> =>
                <<"The message execution model where each path segment applies "
                    "a request message to a base message.">>,
            <<"devices">> =>
                <<"Versioned interpreters that expose computable keys over "
                    "messages.">>,
            <<"messages">> =>
                <<"Typed key/value structures that carry data, commitments, "
                    "device names, and execution history.">>
        }
    }).

device_info_data(Device, Opts) ->
    case docs_resolve_spec(Device, Opts) of
        {ok, SpecID} ->
            case loaded_device_for_spec(Device, SpecID, Opts) of
                true -> on_weave_info_data(Device, SpecID, Opts);
                false -> unsupported_device_info_data(Device)
            end;
        _ ->
            unsupported_device_info_data(Device)
    end.

device_recipes_data(Device, Opts) ->
    {Name, Version} = split_device_id(Device),
    SpecID =
        case docs_resolve_spec(Device, Opts) of
            {ok, ResolvedSpecID} -> ResolvedSpecID;
            _ -> <<>>
        end,
    Recipes = device_recipe_docs(Device, SpecID, <<>>, Opts),
    maps:merge(device_doc_link_fields(Device), #{
        <<"kind">> => <<"device-info">>,
        <<"device">> => #{
            <<"name">> => Name,
            <<"version">> => Version,
            <<"id">> => Device,
            <<"spec-id">> => SpecID
        },
        <<"device-id">> => Device,
        <<"device-name">> => Name,
        <<"device-version">> => Version,
        <<"renderer">> => cookbook_renderer(),
        <<"schema">> => #{},
        <<"schema-order">> => [],
        <<"spec">> => #{},
        <<"recipes">> => Recipes,
        <<"recipe-count">> => map_size(Recipes)
    }).

unsupported_device_info_data(Device) ->
    #{
        <<"kind">> => <<"device-info">>,
        <<"device">> => #{ <<"id">> => Device },
        <<"device-id">> => Device,
        <<"status">> => <<"not-implemented">>,
        <<"docs-status">> => <<"not-documented">>,
        <<"summary">> =>
            <<"No on-weave spec-loaded documentation is available for this device.">>
    }.

device_summary(#{ <<"spec-status">> := <<"missing">>, <<"summary">> := Summary }) ->
    Summary;
device_summary(_Spec) ->
    <<>>.

canonical_spec_device(Device) ->
    lists:member(Device, canonical_spec_devices()).

canonical_spec_devices() ->
    Specs = filelib:wildcard("specs/*.md"),
    lists:sort(
        [
            hb_util:bin(filename:rootname(filename:basename(Spec)))
        || Spec <- Specs,
            canonical_spec_filename(Spec)
        ]
    ).

canonical_spec_filename(Spec) ->
    Name = hb_util:bin(filename:rootname(filename:basename(Spec))),
    binary:match(Name, <<"@">>) =/= nomatch.

on_weave_node_devices(Opts) ->
    NameResolvers = hb_opts:get(<<"name-resolvers">>, [], Opts),
    Pairs0 =
        lists:flatmap(
            fun(Resolver) when is_map(Resolver) -> maps:to_list(Resolver);
               (_Resolver) -> []
            end,
            NameResolvers
        ),
    Pairs =
        lists:usort(
            [
                {DeviceID, SpecID}
            || {DeviceID, SpecID} <- Pairs0,
                is_binary(DeviceID),
                is_binary(SpecID),
                ?IS_ID(SpecID)
            ]
        ),
    [
        on_weave_node_device(DeviceID, SpecID)
    || {DeviceID, SpecID} <- Pairs,
        loaded_device_for_spec(DeviceID, SpecID, Opts)
    ].

loaded_device_for_spec(_DeviceID, SpecID, Opts) ->
    case hb_device_load:reference(SpecID, Opts) of
        {ok, Module} when is_atom(Module) -> true;
        _ -> false
    end.

on_weave_node_device(DeviceID, SpecID) ->
    {Name, Version} = split_device_id(DeviceID),
    docs_node_device(
        DeviceID,
        Name,
        Version,
        <<"On-weave device docs discovered from spec ID ", SpecID/binary, ".">>
    ).

on_weave_info_data(Device, SpecID, Opts) ->
    Spec = on_weave_spec_status(Device, SpecID, Opts),
    SpecSigner = maps:get(<<"signer">>, Spec, <<>>),
    {Schema, SchemaOrder, SchemaSource} =
        docs_schema_for_device(Device, SpecID, Opts),
    Recipes = device_recipe_docs(Device, SpecID, SpecSigner, Opts),
    {Name, Version} = split_device_id(Device),
    maps:merge(device_doc_link_fields(Device), #{
        <<"kind">> => <<"device-info">>,
        <<"device">> => #{
            <<"name">> => Name,
            <<"version">> => Version,
            <<"id">> => Device,
            <<"spec-id">> => SpecID
        },
        <<"device-id">> => Device,
        <<"device-name">> => Name,
        <<"device-version">> => Version,
        <<"summary">> => device_summary(Spec),
        <<"renderer">> => cookbook_renderer(),
        <<"keys">> => on_weave_key_summaries(Device, Schema, SchemaOrder),
        <<"schema">> => Schema,
        <<"schema-order">> => SchemaOrder,
        <<"schema-source">> => SchemaSource,
        <<"spec">> => Spec,
        <<"recipes">> => Recipes,
        <<"recipe-count">> => map_size(Recipes),
        <<"implementations">> => on_weave_implementations(SpecID, Opts),
        <<"coverage">> => #{
            <<"spec">> => SpecID,
            <<"schema">> => maps:get(<<"mode">>, SchemaSource, <<"unknown">>),
            <<"schema-status">> => maps:get(<<"status">>, SchemaSource, <<"unknown">>),
            <<"schema-source">> => maps:get(<<"mode">>, SchemaSource, <<"unknown">>),
            <<"recipes">> => <<"recipe-for-device graph query">>,
            <<"source">> => <<"on-weave">>
        },
        <<"dependencies">> => [],
        <<"docs-source">> => #{
            <<"mode">> => <<"on-weave-by-spec-id">>,
            <<"spec-id">> => SpecID,
            <<"spec-signer">> => SpecSigner,
            <<"schema-source">> => SchemaSource,
            <<"schema-display-rule">> =>
                <<"implementation-derived schema from the loaded device; "
                    "Device-Schema artifacts are ignored">>,
            <<"recipe-display-rule">> =>
                <<"Device-Recipe messages tagged recipe-for-device, any owner">>
        },
        <<"spec-status">> => maps:get(<<"spec-status">>, Spec, <<"missing">>)
    }).

split_device_id(DeviceID) ->
    case binary:split(DeviceID, <<"@">>) of
        [Name, Version] when Name =/= <<>>, Version =/= <<>> ->
            {Name, Version};
        _ ->
            {DeviceID, <<>>}
    end.

docs_resolve_spec(Ref, _Opts) when ?IS_ID(Ref) ->
    {ok, Ref};
docs_resolve_spec(Ref, Opts) ->
    case
        hb_ao:raw(
            #{ <<"device">> => <<"name@1.0">> },
            #{ <<"path">> => Ref, <<"load">> => false },
            Opts
        )
    of
        {ok, SpecID} when ?IS_ID(SpecID) -> {ok, SpecID};
        _ -> {error, <<"device-name-not-resolvable">>}
    end.

on_weave_spec_status(Device, SpecID, Opts) ->
    Metadata = on_weave_item_by_id(SpecID, Opts),
    case on_weave_spec_markdown(SpecID, Opts) of
        {ok, Markdown} ->
            maps:merge(on_weave_spec_metadata(Metadata, SpecID, Opts), #{
                <<"kind">> => <<"device-spec">>,
                <<"href">> => <<"/~", Device/binary, "/docs/spec">>,
                <<"spec-status">> => <<"present">>,
                <<"coverage-status">> => <<"present">>,
                <<"source-path">> => <<>>,
                <<"source">> => <<"on-weave">>,
                <<"txid">> => SpecID,
                <<"title">> => markdown_title(Markdown, Device),
                <<"summary">> => markdown_summary(Markdown),
                <<"markdown-bytes">> => byte_size(Markdown),
                <<"markdown">> => Markdown
            });
        {error, Reason} ->
            missing_on_weave_spec(
                Device,
                SpecID,
                {metadata, Metadata, markdown, Reason}
            )
    end.

on_weave_spec_metadata({ok, Node}, _SpecID, Opts) ->
    (doc_item_metadata(Node, Opts))#{
        <<"metadata-status">> => <<"present">>
    };
on_weave_spec_metadata({error, Reason}, SpecID, _Opts) ->
    #{
        <<"txid">> => SpecID,
        <<"signer">> => <<>>,
        <<"block-height">> => <<>>,
        <<"block-timestamp">> => <<>>,
        <<"metadata-status">> => <<"missing">>,
        <<"metadata-error">> => format_reason(Reason)
    }.

missing_on_weave_spec(Device, SpecID, Reason) ->
            #{
                <<"kind">> => <<"device-spec">>,
                <<"href">> => <<"/~", Device/binary, "/docs/spec">>,
                <<"spec-status">> => <<"missing">>,
                <<"coverage-status">> => <<"missing">>,
                <<"source-path">> => <<>>,
                <<"source">> => <<"on-weave">>,
                <<"txid">> => SpecID,
                <<"summary">> => <<"The on-weave Device-Specification could not be loaded.">>,
                <<"reason">> => format_reason(Reason)
            }.

on_weave_spec_markdown(SpecID, Opts) ->
    case cached_spec_markdown(SpecID, Opts) of
        {ok, Markdown} ->
            {ok, Markdown};
        {error, CacheReason} ->
            case gateway_spec_markdown(SpecID, Opts) of
                {ok, Markdown} -> {ok, Markdown};
                {error, GatewayReason} -> {error, {CacheReason, GatewayReason}}
            end
    end.

cached_spec_markdown(SpecID, Opts) ->
    case hb_cache:read(SpecID, Opts) of
        {ok, Item} -> cached_spec_body(Item, Opts);
        {error, Reason} -> {error, {cache_read_failed, Reason}};
        Other -> {error, {cache_read_unexpected, Other}}
    end.

cached_spec_body(Item, Opts) ->
    case cached_item_body_markdown(Item, Opts) of
        {ok, Markdown} ->
            {ok, Markdown};
        {error, BodyReason} ->
            case raw_ans104_body(Item) of
                {ok, Markdown} -> {ok, Markdown};
                {error, RawReason} ->
                    case safe_structured_ans104_body(Item, Opts) of
                        {ok, Markdown} -> {ok, Markdown};
                        {error, StructuredReason} ->
                            {error,
                                {cache_spec_body_unavailable,
                                    BodyReason,
                                    RawReason,
                                    StructuredReason
                                }}
                    end
            end
    end.

cached_item_body_markdown(Item, Opts) when is_map(Item) ->
    case maps:get(<<"body">>, Item, undefined) of
        undefined ->
            {error, cache_body_missing};
        Body ->
            load_markdown_body(Body, Opts)
    end;
cached_item_body_markdown(_Item, _Opts) ->
    {error, cache_item_not_map}.

load_markdown_body(Body, Opts) ->
    case find_markdown_body(Body) of
        {ok, Markdown} ->
            {ok, Markdown};
        error ->
            try hb_cache:ensure_loaded(Body, Opts) of
                Loaded ->
                    case find_markdown_body(Loaded) of
                        {ok, Markdown} -> {ok, Markdown};
                        error -> {error, cache_body_not_markdown}
                    end
            catch
                Class:Reason -> {error, {cache_body_load_failed, Class, Reason}}
            end
    end.

safe_structured_ans104_body(Item, Opts) ->
    try structured_ans104_body(Item, Opts) of
        Result -> Result
    catch
        Class:Reason -> {error, {Class, Reason}}
    end.

gateway_spec_markdown(SpecID, Opts) ->
    case hb_client_gateway:data(SpecID, Opts) of
        {ok, Markdown} when is_binary(Markdown) ->
            case text_payload(Markdown) of
                true -> {ok, Markdown};
                false -> recover_spec_body(Markdown, SpecID, Opts)
            end;
        {ok, Other} ->
            case gateway_item_data(SpecID, Opts) of
                {ok, Markdown} -> {ok, Markdown};
                {error, Reason} -> {error, {non_binary_spec_body, Other, Reason}}
            end;
        {error, Reason} ->
            case gateway_item_data(SpecID, Opts) of
                {ok, Markdown} -> {ok, Markdown};
                {error, FallbackReason} -> {error, {Reason, FallbackReason}}
            end
    end.

text_payload(Bin) ->
    binary:match(Bin, <<0>>) =:= nomatch.

recover_spec_body(Raw, SpecID, Opts) ->
    case ans104_body(Raw, Opts) of
        {ok, Markdown} -> {ok, Markdown};
        {error, DecodeReason} ->
            case gateway_item_data(SpecID, Opts) of
                {ok, Markdown} -> {ok, Markdown};
                {error, GatewayReason} -> {error, {DecodeReason, GatewayReason}}
            end
    end.

ans104_body(Raw, Opts) ->
    try
        Item = ar_bundles:deserialize(Raw),
        case structured_ans104_body(Item, Opts) of
            {ok, Body} -> {ok, Body};
            {error, StructuredReason} ->
                case raw_ans104_body(Item) of
                    {ok, Body} -> {ok, Body};
                    {error, RawReason} -> {error, {StructuredReason, RawReason}}
                end
        end
    catch
        Class:Reason:Stack ->
            {error, {Class, Reason, Stack}}
    end.

structured_ans104_body(Item, Opts) ->
    Msg = hb_message:convert(
        Item,
        <<"structured@1.0">>,
        <<"ans104@1.0">>,
        Opts
    ),
    case hb_maps:get(<<"body">>, Msg, not_found, Opts) of
        Body when is_binary(Body), byte_size(Body) > 0 ->
            case text_payload(Body) of
                true -> {ok, Body};
                false -> {error, non_text_ans104_body}
            end;
        Other ->
            {error, {missing_or_empty_ans104_body, Other}}
    end.

raw_ans104_body(Item) ->
    case find_markdown_body(Item) of
        {ok, Body} -> {ok, Body};
        error -> {error, unsupported_ans104_shape}
    end.

find_markdown_body(Term) ->
    find_markdown_body(Term, 0).

find_markdown_body(_Term, Depth) when Depth > 12 ->
    error;
find_markdown_body(#tx{data = Data}, Depth) ->
    find_markdown_body(Data, Depth + 1);
find_markdown_body(Bin, Depth) when is_binary(Bin), byte_size(Bin) > 0 ->
    case markdown_payload(Bin) of
        true -> {ok, Bin};
        false ->
            case embedded_markdown_body(Bin) of
                {ok, _} = Found -> Found;
                error -> nested_ans104_body(Bin, Depth + 1)
            end
    end;
find_markdown_body(Map, Depth) when is_map(Map) ->
    case maps:get(<<"body">>, Map, undefined) of
        undefined ->
            find_markdown_body_in_list(maps:values(Map), Depth + 1);
        Body ->
            case find_markdown_body(Body, Depth + 1) of
                {ok, _} = Found -> Found;
                error ->
                    find_markdown_body_in_list(
                        maps:values(maps:remove(<<"body">>, Map)),
                        Depth + 1
                    )
            end
    end;
find_markdown_body(List, Depth) when is_list(List) ->
    find_markdown_body_in_list(List, Depth + 1);
find_markdown_body(Tuple, Depth) when is_tuple(Tuple) ->
    find_markdown_body_in_list(tuple_to_list(Tuple), Depth + 1);
find_markdown_body(_Other, _Depth) ->
    error.

nested_ans104_body(Bin, Depth) ->
    try ar_bundles:deserialize(Bin) of
        Bin -> error;
        Nested -> find_markdown_body(Nested, Depth)
    catch
        _Class:_Reason -> error
    end.

embedded_markdown_body(Bin) ->
    case embedded_markdown_start(Bin) of
        {ok, Pos} ->
            Candidate0 = binary:part(Bin, Pos, byte_size(Bin) - Pos),
            Candidate = binary_before_nul(Candidate0),
            case markdown_payload(Candidate) of
                true -> {ok, Candidate};
                false -> error
            end;
        error ->
            error
    end.

embedded_markdown_start(Bin) ->
    case binary:match(Bin, <<"# `">>) of
        {Pos, _Len} -> {ok, Pos};
        nomatch ->
            case binary:match(Bin, <<"# ">>) of
                {Pos, _Len} -> {ok, Pos};
                nomatch -> error
            end
    end.

binary_before_nul(Bin) ->
    case binary:match(Bin, <<0>>) of
        {Pos, _Len} -> binary:part(Bin, 0, Pos);
        nomatch -> Bin
    end.

find_markdown_body_in_list([], _Depth) ->
    error;
find_markdown_body_in_list([Term | Rest], Depth) ->
    case find_markdown_body(Term, Depth) of
        {ok, _} = Found -> Found;
        error -> find_markdown_body_in_list(Rest, Depth)
    end.

markdown_payload(Bin) ->
    text_payload(Bin) andalso markdown_prefix(skip_ascii_ws(Bin)).

skip_ascii_ws(<<C, Rest/binary>>) when C =:= 9; C =:= 10; C =:= 13; C =:= 32 ->
    skip_ascii_ws(Rest);
skip_ascii_ws(Bin) ->
    Bin.

markdown_prefix(<<"#", _/binary>>) ->
    true;
markdown_prefix(_Bin) ->
    false.

gateway_item_data(ID, Opts) ->
    Req = #{
        <<"multirequest-accept-status">> => 200,
        <<"multirequest-responses">> => 1,
        <<"path">> => <<"/arweave/", ID/binary>>,
        <<"method">> => <<"GET">>
    },
    case hb_http:request(Req, Opts) of
        {ok, Data} when is_binary(Data) ->
            {ok, Data};
        {ok, Res} ->
            gateway_item_response_body(ID, Res, Opts);
        {error, Reason} ->
            {error, Reason}
    end.

gateway_item_response_body(ID, Res, Opts) when is_map(Res) ->
    Data =
        case hb_maps:find(<<"data">>, Res, Opts) of
            {ok, D} -> D;
            _ -> hb_ao:get(<<"body">>, Res, <<>>, Opts)
        end,
    case Data of
        Bin when is_binary(Bin) -> {ok, Bin};
        Other -> {error, {non_binary_gateway_body, ID, Other}}
    end;
gateway_item_response_body(ID, Other, _Opts) ->
    {error, {unexpected_gateway_item_response, ID, Other}}.

on_weave_key_summaries(Device, Schema, Order) ->
    [
        device_key_summary(
            Device,
            Name,
            maps:get(<<"kind">>, KeySchema, <<"computed">>),
            maps:get(<<"description">>, KeySchema, <<>>)
        )
    || Name <- Order,
        KeySchema <- [maps:get(Name, Schema, #{})],
        map_size(KeySchema) > 0
    ].

device_recipe_docs(_Device, <<>>, _SpecSigner, _Opts) ->
    #{};
device_recipe_docs(Device, SpecID, SpecSigner, Opts) ->
    on_weave_recipe_docs(Device, SpecID, SpecSigner, Opts).

on_weave_recipe_docs(Device, SpecID, SpecSigner, Opts) ->
    case on_weave_doc_items(<<"Device-Recipe">>, <<"recipe-for-device">>, SpecID, [], 20, Opts) of
        {ok, Nodes} ->
            LoadedRecipes = [
                Recipe
            || Node <- Nodes,
                {ok, Recipe} <- [on_weave_recipe_doc(Node, SpecSigner, Opts)]
            ],
            Recipes = apply_recipe_blacklist(Device, SpecID, LoadedRecipes, Opts),
            lists:foldl(
                fun(Recipe, Acc) ->
                    Slug = maps:get(<<"name">>, Recipe),
                    case maps:is_key(Slug, Acc) of
                        true -> Acc;
                        false -> Acc#{Slug => Recipe}
                    end
                end,
                #{},
                Recipes
            );
        {error, _Reason} ->
            #{}
    end.

apply_recipe_blacklist(Device, SpecID, Recipes, Opts) ->
    [
        Recipe
    || Recipe <- Recipes,
        not recipe_blacklisted(Device, SpecID, Recipe, Opts)
    ].

recipe_blacklisted(Device, SpecID, Recipe, Opts) ->
    Entries = docs_recipe_blacklist(Opts),
    lists:any(
        fun(Entry) -> recipe_blacklist_entry_matches(Device, SpecID, Recipe, Entry) end,
        Entries
    ).

docs_recipe_blacklist(Opts) ->
    normalize_recipe_blacklist_entries(
        hb_opts:get(
            <<"docs-recipe-blacklist">>,
            hb_opts:get(docs_recipe_blacklist, [], Opts),
            Opts
        )
    ) ++ docs_recipe_blacklist_file_entries(Opts).

docs_recipe_blacklist_file_entries(Opts) ->
    case hb_opts:get(
        <<"docs-recipe-blacklist-file">>,
        hb_opts:get(docs_recipe_blacklist_file, <<>>, Opts),
        Opts
    ) of
        <<>> ->
            [];
        Path0 ->
            Path = binary_to_list(hb_util:bin(Path0)),
            case file:read_file(Path) of
                {ok, Body} ->
                    try normalize_recipe_blacklist_entries(hb_json:decode(Body))
                    catch _:_ -> []
                    end;
                {error, _Reason} ->
                    []
            end
    end.

normalize_recipe_blacklist_entries(Entries) when is_list(Entries) ->
    [Entry || Entry <- Entries, is_map(Entry)];
normalize_recipe_blacklist_entries(#{ <<"recipes">> := Entries }) ->
    normalize_recipe_blacklist_entries(Entries);
normalize_recipe_blacklist_entries(#{ <<"blacklist">> := Entries }) ->
    normalize_recipe_blacklist_entries(Entries);
normalize_recipe_blacklist_entries(Entry) when is_map(Entry) ->
    [Entry];
normalize_recipe_blacklist_entries(_Entries) ->
    [].

recipe_blacklist_entry_matches(Device, SpecID, Recipe, Entry) when is_map(Entry) ->
    recipe_blacklist_txid_matches(Recipe, Entry) orelse
        recipe_blacklist_slug_matches(Device, SpecID, Recipe, Entry);
recipe_blacklist_entry_matches(_Device, _SpecID, _Recipe, _Entry) ->
    false.

recipe_blacklist_txid_matches(Recipe, Entry) ->
    EntryTXID = trim(hb_util:bin(maps:get(<<"txid">>, Entry, <<>>))),
    EntryTXID =/= <<>> andalso
        lists:member(EntryTXID, recipe_blacklist_txids(Recipe)).

recipe_blacklist_txids(Recipe) ->
    lists:usort([
        TXID
    || Value <- [
            maps:get(<<"txid">>, Recipe, <<>>),
            maps:get(<<"source">>, Recipe, <<>>),
            maps:get(<<"source-relative">>, Recipe, <<>>)
        ],
        TXID <- [strip_weave_prefix(trim(hb_util:bin(Value)))],
        TXID =/= <<>>
    ]).

strip_weave_prefix(<<"weave:", Rest/binary>>) ->
    Rest;
strip_weave_prefix(Value) ->
    Value.

recipe_blacklist_slug_matches(Device, SpecID, Recipe, Entry) ->
    EntrySlug = trim(hb_util:bin(maps:get(<<"slug">>, Entry, <<>>))),
    EntryDevice = trim(hb_util:bin(maps:get(<<"device">>, Entry, <<>>))),
    EntrySpecID = trim(hb_util:bin(maps:get(<<"spec-id">>, Entry, <<>>))),
    Slug = maps:get(<<"name">>, Recipe, <<>>),
    EntrySlug =/= <<>> andalso
        EntrySlug =:= Slug andalso
        (
            (EntryDevice =/= <<>> andalso EntryDevice =:= Device) orelse
            (EntrySpecID =/= <<>> andalso EntrySpecID =:= SpecID)
        ).

on_weave_recipe_doc(Node, SpecSigner, Opts) ->
    ID = maps:get(<<"id">>, Node),
    case hb_client_gateway:data(ID, Opts) of
        {ok, Markdown} ->
            Slug = doc_item_tag(Node, <<"slug">>, ID),
            Title = doc_item_tag(Node, <<"title">>, markdown_title(Markdown, Slug)),
            Blocks = code_blocks(Markdown),
            Runnable = [Block || Block <- Blocks, maps:get(<<"runnable">>, Block, false) =:= true],
            FirstCommand =
                case Runnable of
                    [First|_] -> command_preview(maps:get(<<"text">>, First, <<>>));
                    [] -> <<>>
                end,
            {ok,
                maps:merge(doc_item_metadata(Node, Opts), #{
                    <<"name">> => Slug,
                    <<"title">> => Title,
                    <<"summary">> => markdown_summary(Markdown),
                    <<"source">> => <<"on-weave">>,
                    <<"source-relative">> => <<"weave:", ID/binary>>,
                    <<"recipe-status">> => <<"loaded">>,
                    <<"block-count">> => length(Blocks),
                    <<"runnable-block-count">> => length(Runnable),
                    <<"first-command">> => FirstCommand,
                    <<"blocks">> => Blocks,
                    <<"markdown">> => Markdown,
                    <<"official">> =>
                        SpecSigner =/= <<>> andalso doc_item_owner(Node, Opts) =:= SpecSigner
                })};
        {error, Reason} ->
            {ok,
                maps:merge(doc_item_metadata(Node, Opts), #{
                    <<"name">> => doc_item_tag(Node, <<"slug">>, ID),
                    <<"title">> => doc_item_tag(Node, <<"title">>, ID),
                    <<"summary">> => <<"Recipe body could not be loaded from the weave.">>,
                    <<"source">> => <<"on-weave">>,
                    <<"source-relative">> => <<"weave:", ID/binary>>,
                    <<"recipe-status">> => <<"missing">>,
                    <<"error">> => format_reason(Reason),
                    <<"block-count">> => 0,
                    <<"runnable-block-count">> => 0
                })}
    end.

on_weave_implementations(SpecID, Opts) ->
    TrustedSigners = hb_opts:get(<<"trusted-device-signers">>, [], Opts),
    case TrustedSigners of
        [] ->
            [];
        _ ->
            case hb_client_gateway:device(SpecID, TrustedSigners, Opts) of
                {ok, ImplIDs} ->
                    [
                        #{
                            <<"name">> => SpecID,
                            <<"module">> => <<"on-weave-beam-archive">>,
                            <<"source">> => ImplID,
                            <<"status">> => <<"discovered-by-implements-device">>
                        }
                    || ImplID <- ImplIDs
                    ];
                {error, _Reason} ->
                    []
            end
    end.

on_weave_item_by_id(ID, Opts) ->
    Query =
        <<"query($ids: [ID!]!) { ",
            "transactions(ids: $ids, first: 1){ ",
                "edges { ",
                    "node { ",
                        "id ",
                        "owner { address key } ",
                        "block { height timestamp } ",
                        "tags { name value } ",
                        "data { size } ",
                    "} ",
                    "cursor ",
                "} ",
            "} ",
        "}">>,
    Variables = #{<<"ids">> => [ID]},
    case hb_client_gateway:query(Query, Variables, Opts) of
        {ok, GqlMsg} ->
            case hb_ao:get(<<"data/transactions/edges">>, GqlMsg, Opts) of
                [#{<<"node">> := Node} | _] -> {ok, Node};
                _ -> {error, not_found}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

on_weave_doc_items(Type, TagName, SpecID, Owners, First, Opts) ->
    OwnerVar =
        case Owners of
            [] -> <<>>;
            _ -> <<", $owners: [String!]">>
        end,
    OwnerArg =
        case Owners of
            [] -> <<>>;
            _ -> <<"owners: $owners, ">>
        end,
    FirstBin = integer_to_binary(First),
    Query =
        <<"query($specid: [String!], $type: [String!]", OwnerVar/binary, ") { ",
            "transactions(",
                OwnerArg/binary,
                "tags: [",
                    "{ name: \"type\", values: $type }, ",
                    "{ name: \"", TagName/binary, "\", values: $specid }",
                "], ",
                "sort: HEIGHT_DESC, ",
                "first: ", FirstBin/binary,
            "){ ",
                "edges { ",
                    "node { ",
                        "id ",
                        "owner { address key } ",
                        "block { height timestamp } ",
                        "tags { name value } ",
                        "data { size } ",
                    "} ",
                    "cursor ",
                "} ",
            "} ",
        "}">>,
    Variables0 = #{<<"specid">> => [SpecID], <<"type">> => [Type]},
    Variables =
        case Owners of
            [] -> Variables0;
            _ -> Variables0#{<<"owners">> => Owners}
        end,
    case hb_client_gateway:query(Query, Variables, Opts) of
        {ok, GqlMsg} ->
            case hb_ao:get(<<"data/transactions/edges">>, GqlMsg, Opts) of
                Edges when is_list(Edges) ->
                    {ok, [Node || #{<<"node">> := Node} <- Edges]};
                _ ->
                    {ok, []}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

doc_item_metadata(Node, Opts) ->
    #{
        <<"txid">> => maps:get(<<"id">>, Node, <<>>),
        <<"signer">> => doc_item_owner(Node, Opts),
        <<"block-height">> => hb_ao:get(<<"block/height">>, Node, <<>>, Opts),
        <<"block-timestamp">> => hb_ao:get(<<"block/timestamp">>, Node, <<>>, Opts)
    }.

doc_item_owner(Node, Opts) ->
    hb_ao:get(<<"owner/address">>, Node, <<>>, Opts).

doc_item_tag(Node, Name, Default) ->
    Tags = maps:get(<<"tags">>, Node, []),
    case [Value || #{<<"name">> := TagName, <<"value">> := Value} <- Tags, TagName =:= Name] of
        [Value | _] -> Value;
        [] -> Default
    end.

format_reason(Reason) ->
    hb_util:bin(io_lib:format("~tp", [Reason])).

json_safe(Value) when is_map(Value) ->
    maps:from_list(
        [
            {json_safe_key(Key), json_safe(Inner)}
        || {Key, Inner} <- maps:to_list(Value)
        ]
    );
json_safe(Value) when is_list(Value) ->
    [json_safe(Inner) || Inner <- Value];
json_safe(true) ->
    true;
json_safe(false) ->
    false;
json_safe(Value) when is_atom(Value) ->
    atom_to_binary(Value, utf8);
json_safe(Value) when is_tuple(Value) ->
    [json_safe(Inner) || Inner <- tuple_to_list(Value)];
json_safe(Value) ->
    Value.

json_safe_key(Key) when is_binary(Key) ->
    Key;
json_safe_key(Key) when is_atom(Key) ->
    binary:replace(atom_to_binary(Key, utf8), <<"_">>, <<"-">>, [global]);
json_safe_key(Key) ->
    hb_util:bin(io_lib:format("~tp", [Key])).

node_href(Opts) ->
    Host = hb_opts:get(node_host, <<"localhost">>, Opts),
    Port = hb_opts:get(port, 8734, Opts),
    iolist_to_binary(["http://", hb_util:bin(Host), ":", hb_util:bin(Port)]).

cookbook_renderer() ->
    hb_docs_cookbook:renderer_metadata().

node_component_index(Kind, LinkKey, Data) ->
    Devices = maps:get(<<"devices">>, Data, []),
    #{
        <<"kind">> => Kind,
        <<"renderer">> => maps:get(<<"renderer">>, Data, cookbook_renderer()),
        <<"devices">> =>
            [
                #{
                    <<"device">> => device_card_label(Device),
                    <<"href">> => maps:get(LinkKey, Device, maps:get(<<"href">>, Device, <<>>))
                }
            || Device <- Devices
            ]
    }.

device_key_summary(Device, Name, Kind, Description) ->
    #{
        <<"name">> => Name,
        <<"kind">> => Kind,
        <<"description">> => Description,
        <<"href">> => <<"/~", Device/binary, "/", Name/binary>>
    }.

docs_schema_for_device(Device, SpecID, Opts) ->
    case implementation_derived_schema(Device, Opts) of
        {ok, Schema, SchemaOrder, Source} ->
            {
                Schema,
                SchemaOrder,
                Source#{
                    <<"mode">> => <<"implementation-derived">>,
                    <<"spec-id">> => SpecID
                }
            };
        {error, Reason} ->
            {
                #{},
                [],
                #{
                    <<"mode">> => <<"implementation-derived-unavailable">>,
                    <<"device">> => Device,
                    <<"spec-id">> => SpecID,
                    <<"status">> => <<"unavailable">>,
                    <<"reason">> => format_reason(Reason),
                    <<"display-rule">> =>
                        <<"schema must be derived from the loaded implementation">>
                }
            }
    end.

implementation_derived_schema(Device, Opts) ->
    case hb_types:extract(Device, Opts#{ <<"hashpath">> => ignore }) of
        {ok, #{ <<"keys">> := Keys } = Extracted} when is_map(Keys), map_size(Keys) > 0 ->
            Schema =
                maps:from_list(
                    [
                        {Key, implementation_schema_key(Device, Key, KeySchema)}
                    || {Key, KeySchema} <- maps:to_list(Keys)
                    ]
                ),
            Order = lists:sort(maps:keys(Schema)),
            {ok,
                Schema,
                Order,
                #{
                    <<"status">> => <<"present">>,
                    <<"extractor">> => <<"hb_types:extract/2">>,
                    <<"module">> => maps:get(<<"module">>, Extracted, hb_util:bin(Device)),
                    <<"key-count">> => map_size(Schema)
                }
            };
        {ok, #{ <<"keys">> := Keys }} when is_map(Keys) ->
            {error, no_public_type_keys};
        {ok, Other} ->
            {error, {unexpected_schema_shape, Other}};
        {error, Reason} ->
            {error, Reason}
    end.

implementation_schema_key(Device, Key, KeySchema) ->
    DeviceID =
        case is_binary(Device) of
            true -> Device;
            false -> hb_util:bin(Device)
        end,
    Params = implementation_request_params(maps:get(<<"request">>, KeySchema, #{})),
    Return = implementation_type_label(maps:get(<<"return">>, KeySchema, #{})),
    maps:merge(
        maps:without(
            [<<"description">>],
            schema_key(DeviceID, Key, <<>>, Params)
        ),
        #{
            <<"source">> => <<"hb_types:extract/2">>,
            <<"description-source">> => <<"none">>,
            <<"derived">> => true,
            <<"returns">> => Return,
            <<"type-schema">> => json_safe(KeySchema)
        }
    ).

implementation_request_params(#{ <<"kind">> := <<"message">>, <<"keys">> := Keys })
        when is_map(Keys) ->
    maps:from_list(
        [
            {
                Name,
                implementation_param(Name, Presence, Type)
            }
        || {Name, #{ <<"presence">> := Presence, <<"type">> := Type }} <- maps:to_list(Keys)
        ]
    );
implementation_request_params(_Schema) ->
    #{}.

implementation_param(Name, Presence, Type) ->
    (maps:without(
        [<<"description">>, <<"example">>],
        param(
            Name,
            implementation_required(Presence),
            implementation_type_label(Type),
            <<>>,
            <<>>
        )
    ))#{
        <<"description-source">> => <<"none">>
    }.

implementation_required(required) -> true;
implementation_required(<<"required">>) -> true;
implementation_required(_) -> false.

implementation_type_label(#{ <<"kind">> := <<"message">>, <<"keys">> := Keys }) when is_map(Keys) ->
    case maps:keys(Keys) of
        [] -> <<"message">>;
        Names -> iolist_to_binary([<<"message(">>, join_names(Names), <<")">>])
    end;
implementation_type_label(#{ <<"kind">> := <<"list">>, <<"item">> := Item }) ->
    iolist_to_binary([<<"list<">>, implementation_type_label(Item), <<">">>]);
implementation_type_label(#{ <<"kind">> := <<"tuple">>, <<"items">> := Items }) ->
    implementation_join_type(<<"tuple(">>, Items, <<")">>);
implementation_type_label(#{ <<"kind">> := <<"union">>, <<"members">> := Members }) ->
    implementation_join_type(<<"union(">>, Members, <<")">>);
implementation_type_label(#{ <<"kind">> := <<"literal">>, <<"value">> := Value }) ->
    iolist_to_binary([<<"literal:">>, hb_util:bin(io_lib:format("~tp", [Value]))]);
implementation_type_label(#{ <<"kind">> := Kind }) ->
    hb_util:bin(Kind);
implementation_type_label(_Type) ->
    <<"any">>.

implementation_join_type(Prefix, Items, Suffix) ->
    Labels = [implementation_type_label(Item) || Item <- Items],
    iolist_to_binary([Prefix, lists:join(<<",">>, Labels), Suffix]).

schema_key(Device, Name, Description, Parameters) ->
    Required = [
        ParamName
    ||  {ParamName, ParamSpec} <- maps:to_list(Parameters),
        maps:get(<<"required">>, ParamSpec, false) =:= true
    ],
    maps:merge(Parameters, #{
        <<"name">> => Name,
        <<"kind">> => <<"computed">>,
        <<"description">> => Description,
        <<"href">> => <<"/~", Device/binary, "/", Name/binary>>,
        <<"action-path-template">> => action_path_template(Device, Name),
        <<"parameter-names">> => join_names(maps:keys(Parameters)),
        <<"required-parameters">> => join_names(Required),
        <<"parameters">> => Parameters
    }).

action_path_template(?MESSAGE_DEVICE, <<"field">>) ->
    <<"/~message@1.0/{field}">>;
action_path_template(Device, Name) ->
    <<"/~", Device/binary, "/", Name/binary>>.

join_names([]) ->
    <<"">>;
join_names(Names) ->
    iolist_to_binary(lists:join(<<",">>, lists:sort(Names))).

param(Name, Required, Type, Description, Example) ->
    #{
        <<"name">> => Name,
        <<"required">> => Required,
        <<"type">> => Type,
        <<"description">> => Description,
        <<"example">> => Example
    }.

device_spec_status(Device) ->
    SourcePath = << "specs/", Device/binary, ".md" >>,
    TXID = device_spec_txid(Device),
    case file:read_file(binary_to_list(SourcePath)) of
        {ok, Markdown} ->
            #{
                <<"kind">> => <<"device-spec">>,
                <<"href">> => <<"/~", Device/binary, "/docs/spec">>,
                <<"spec-status">> => <<"present">>,
                <<"coverage-status">> => <<"present">>,
                <<"source-path">> => SourcePath,
                <<"txid">> => TXID,
                <<"title">> => markdown_title(Markdown, Device),
                <<"summary">> => markdown_summary(Markdown),
                <<"markdown-bytes">> => byte_size(Markdown)
            };
        {error, _Reason} ->
            #{
                <<"kind">> => <<"device-spec">>,
                <<"href">> => <<"/~", Device/binary, "/docs/spec">>,
                <<"spec-status">> => <<"missing">>,
                <<"coverage-status">> => <<"missing">>,
                <<"source-path">> => SourcePath,
                <<"txid">> => TXID,
                <<"summary">> =>
                    <<"The specs branch does not currently contain this device "
                        "specification file. This endpoint is stable so callers "
                        "can discover the missing coverage explicitly.">>,
                <<"next-action">> =>
                    <<"Write the normative device contract and replace this "
                        "placeholder with the spec body or content-addressed spec link.">>
            }
    end.

device_spec_txid(Device) ->
    TXIDPath = << "specs/", Device/binary, ".txid" >>,
    case file:read_file(binary_to_list(TXIDPath)) of
        {ok, Raw} ->
            TXID = trim(Raw),
            case is_arweave_txid(TXID) of
                true -> TXID;
                false -> <<>>
            end;
        {error, _Reason} ->
            <<>>
    end.

is_arweave_txid(TXID) when byte_size(TXID) =:= 43 ->
    lists:all(
        fun(Char) ->
            (Char >= $A andalso Char =< $Z) orelse
                (Char >= $a andalso Char =< $z) orelse
                (Char >= $0 andalso Char =< $9) orelse
                Char =:= $_ orelse Char =:= $-
        end,
        binary_to_list(TXID)
    );
is_arweave_txid(_TXID) ->
    false.

boilerplate_index() ->
    hb_docs_ui:boilerplate_index().

boilerplate_page_payload(Parts) ->
    hb_docs_ui:boilerplate_page_payload(Parts).

docs_asset_response(Parts) ->
    hb_docs_ui:docs_asset_response(Parts).

render_node_html(Data) ->
    hb_docs_ui:render_node_html(Data).

render_device_html(Data) ->
    hb_docs_ui:render_device_html(Data).

render_schema_index_html(Data) ->
    hb_docs_ui:render_schema_index_html(Data).

render_schema_key_html(Payload) ->
    hb_docs_ui:render_schema_key_html(Payload).

render_schema_parameter_html(Payload) ->
    hb_docs_ui:render_schema_parameter_html(Payload).

render_spec_html(Data) ->
    hb_docs_ui:render_spec_html(Data).

render_spec_section_page_html(Payload) ->
    hb_docs_ui:render_spec_section_page_html(Payload).

render_recipes_html(Data) ->
    hb_docs_ui:render_recipes_html(Data).

render_recipe_html(Payload) ->
    hb_docs_ui:render_recipe_html(Payload).

render_implementations_html(Data) ->
    hb_docs_ui:render_implementations_html(Data).

render_node_component_html(Title, ActivePath, Data) ->
    hb_docs_ui:render_node_component_html(Title, ActivePath, Data).

render_node_boilerplate_html(Data) ->
    hb_docs_ui:render_node_boilerplate_html(Data).

render_node_boilerplate_page_html(Data) ->
    hb_docs_ui:render_node_boilerplate_page_html(Data).

render_node_concepts_html(Data) ->
    hb_docs_ui:render_node_concepts_html(Data).

render_node_concept_html(Data) ->
    hb_docs_ui:render_node_concept_html(Data).

render_unsupported_device_html(Device) ->
    hb_docs_ui:render_unsupported_device_html(Device).

markdown_title(Markdown, Fallback) ->
    hb_docs_ui:markdown_title(Markdown, Fallback).

markdown_summary(Markdown) ->
    hb_docs_ui:markdown_summary(Markdown).

command_preview(Text) ->
    hb_docs_ui:command_preview(Text).

code_blocks(Markdown) ->
    hb_docs_ui:code_blocks(Markdown).

trim(Bin) ->
    hb_docs_ui:trim(Bin).

spec_section_lookup(Spec, SectionSlug) ->
    hb_docs_ui:spec_section_lookup(Spec, SectionSlug).

spec_sections(Spec) ->
    hb_docs_ui:spec_sections(Spec).

render_spec_body(Spec) ->
    hb_docs_ui:render_spec_body(Spec).

render_markdown(Markdown) ->
    hb_docs_ui:render_markdown(Markdown).

card_summary(Summary) ->
    hb_docs_ui:card_summary(Summary).

recipe_card_summary(Recipe) ->
    hb_docs_ui:recipe_card_summary(Recipe).

packaged_device_docs_root() ->
    hb_docs_ui:packaged_device_docs_root().

device_card_label(Device) ->
    hb_docs_ui:device_card_label(Device).

device_info_path(DeviceID) ->
    hb_docs_ui:device_info_path(DeviceID).

device_schema_path(DeviceID) ->
    hb_docs_ui:device_schema_path(DeviceID).

device_spec_path(DeviceID) ->
    hb_docs_ui:device_spec_path(DeviceID).

device_recipes_path(DeviceID) ->
    hb_docs_ui:device_recipes_path(DeviceID).

device_doc_link_fields(Device) ->
    hb_docs_ui:device_doc_link_fields(Device).

spec_section_nav_label(Title) ->
    hb_docs_ui:spec_section_nav_label(Title).

schema_table(DeviceID, Schema, Order) ->
    hb_docs_ui:schema_table(DeviceID, Schema, Order).

device_summary_paragraph(Data) ->
    hb_docs_ui:device_summary_paragraph(Data).

recipe_nav(DeviceID, Recipes) ->
    hb_docs_ui:recipe_nav(DeviceID, Recipes).

boilerplate_pages_for_section(Section, Pages) ->
    hb_docs_ui:boilerplate_pages_for_section(Section, Pages).

recipe_icon_name(Slug, Title) ->
    hb_docs_ui:recipe_icon_name(Slug, Title).

recipe_icon_paths() ->
    hb_docs_ui:recipe_icon_paths().

on_chain_link_paragraph(Item, Label) ->
    hb_docs_ui:on_chain_link_paragraph(Item, Label).

on_chain_txid(Item) ->
    hb_docs_ui:on_chain_txid(Item).

implementation_source_cell(Impl) ->
    hb_docs_ui:implementation_source_cell(Impl).

spec_tx_link(Spec, Prefix) ->
    hb_docs_ui:spec_tx_link(Spec, Prefix).

device_marked_id(DeviceID) ->
    hb_docs_ui:device_marked_id(DeviceID).

sidebar_device_context(ActivePath, DeviceID) ->
    hb_docs_ui:sidebar_device_context(ActivePath, DeviceID).

decoded_json_response(#{ <<"content-type">> := <<"application/json">>, <<"body">> := Body }) ->
    hb_json:decode(Body);
decoded_json_response(Payload) ->
    Payload.

raw_ans104_body_nested_body_test() ->
    Markdown = <<"# `arweave-byte-pricing@1.1`\n\nDevice spec body.">>,
    Item = #tx{
        data = #{
            <<"1">> => #tx{
                data = #{
                    <<"body">> => #tx{data = Markdown},
                    <<"content-type">> => <<"text/markdown">>
                }
            }
        }
    },
    ?assertEqual({ok, Markdown}, raw_ans104_body(Item)).

raw_ans104_body_serialized_nested_item_test() ->
    Markdown = <<"# `arweave-byte-pricing@1.1`\n\nDevice spec body.">>,
    Inner = ar_bundles:serialize(ar_tx:normalize(#tx{data = Markdown})),
    ?assertEqual({ok, Markdown}, raw_ans104_body(#tx{data = Inner})).

raw_ans104_body_embedded_markdown_binary_test() ->
    Markdown = <<"# `arweave-byte-pricing@1.1`\n\nDevice spec body.">>,
    Wrapped = <<0, 0, 1, 0, "ao-type", 0, "binary", 0, Markdown/binary>>,
    ?assertEqual({ok, Markdown}, raw_ans104_body(#tx{data = Wrapped})).

raw_ans104_body_rejects_wrapper_binary_test() ->
    Item = #tx{data = <<131, 116, 0, 0, 0, 1, 100, 0, 4, "body">>},
    ?assertEqual({error, unsupported_ans104_shape}, raw_ans104_body(Item)).

cached_spec_body_markdown_test() ->
    Markdown = <<"# Cached spec\n\nLoaded from the signed spec item.">>,
    ?assertEqual({ok, Markdown}, cached_spec_body(#{ <<"body">> => Markdown }, #{})).

gateway_item_response_shape_test() ->
    ID = <<"gateway-item-test">>,
    ?assertEqual(
        {ok, <<"from-data">>},
        gateway_item_response_body(ID, #{ <<"data">> => <<"from-data">> }, #{})
    ),
    ?assertEqual(
        {ok, <<"from-body">>},
        gateway_item_response_body(ID, #{ <<"body">> => <<"from-body">> }, #{})
    ),
    ?assertEqual(
        {error, {non_binary_gateway_body, ID, checkout_timeout}},
        gateway_item_response_body(ID, #{ <<"data">> => checkout_timeout }, #{})
    ),
    ?assertEqual(
        {error, {unexpected_gateway_item_response, ID, checkout_timeout}},
        gateway_item_response_body(ID, checkout_timeout, #{})
    ).

node_info_contract_test() ->
    Data = node_info_data(#{ <<"port">> => 9999 }),
    ?assertEqual(<<"node-info">>, maps:get(<<"kind">>, Data)),
    ?assertNot(maps:is_key(<<"arweave-info">>, Data)),
    ?assertNot(maps:is_key(<<"message-info">>, Data)),
    ?assertEqual(<<"/docs/guides">>, maps:get(<<"boilerplate-link">>, Data)),
    ?assertEqual(21, length(maps:get(<<"pages">>, maps:get(<<"boilerplate">>, Data)))),
    ?assertEqual(<<"cookbook@1.0">>, maps:get(<<"device">>, maps:get(<<"renderer">>, Data))),
    ?assertEqual([], maps:get(<<"devices">>, Data)).

node_sidebar_hierarchy_test() ->
    {ok, HTML} = node_info(#{ <<"accept">> => <<"text/html">> }, #{}),
    Body = maps:get(<<"body">>, HTML),
    ?assert(binary:match(Body, <<"<li><p>Guides</p><ul>">>) =/= nomatch),
    ?assert(binary:match(Body, <<"<li><a href=\"/docs/guides\">All guides</a></li>">>) =/= nomatch),
    ?assert(binary:match(Body, <<"<li><p>Introduction</p><ul>">>) =/= nomatch),
    ?assert(binary:match(Body, <<"<li><p>Processes</p><ul>">>) =/= nomatch),
    ?assert(binary:match(Body, <<"<li><p>Device Forge</p><ul>">>) =/= nomatch),
    ?assertEqual(nomatch, binary:match(Body, <<"/docs/boilerplate">>)),
    ?assertEqual(nomatch, binary:match(Body, <<"Device Recipes">>)),
    ?assert(binary:match(Body, <<"AO Devices">>) =/= nomatch),
    ?assertEqual(nomatch, binary:match(Body, <<"/docs/boilerplate/devices/index">>)),
    ?assert(binary:match(Body, <<"hb-docs-guide-index">>) =/= nomatch),
    ?assert(binary:match(Body, <<"<section class=\"hb-docs-guide-group\"><h3>Introduction</h3><ul>">>) =/= nomatch),
    ?assertEqual(nomatch, binary:match(Body, <<"<h2>Guides</h2><div class=\"hb-docs-card-grid\">">>)).

markdown_star_bullet_rendering_test() ->
    HTML = render_markdown(
        <<"*   **Initialization Flow:** starts\n"
            "* **Compute Model:** uses `Message1(Message2) => Message3`">>
    ),
    ?assert(binary:match(HTML, <<"<ul>">>) =/= nomatch),
    ?assert(binary:match(HTML, <<"<li><strong>Initialization Flow:</strong> starts</li>">>) =/= nomatch),
    ?assert(binary:match(HTML, <<"<code>Message1(Message2) =&gt; Message3</code>">>) =/= nomatch),
    ?assertEqual(nomatch, binary:match(HTML, <<"*   **Initialization Flow:**">>)).

markdown_blockquote_rendering_test() ->
    HTML = render_markdown(
        <<"> Worked examples (informative).\n"
            "> - Base `{ device: apply@1.0, body: \"/~meta@1.0/build/node\" }`, request\n"
            ">   `{ path: \"body\" }`: eval mode.\n"
            "> - Path-string invocation\n"
            ">   `/~meta@1.0/build/node~apply@1.0&node=TEST&base=request:&request=base:`.">>
    ),
    ?assert(binary:match(HTML, <<"<blockquote>">>) =/= nomatch),
    ?assert(binary:match(HTML, <<"<p>Worked examples (informative).</p>">>) =/= nomatch),
    ?assert(binary:match(HTML, <<"<ul>">>) =/= nomatch),
    ?assert(binary:match(HTML, <<"<code>{ device: apply@1.0">>) =/= nomatch),
    ?assertEqual(nomatch, binary:match(HTML, <<"&gt; Worked examples">>)).

markdown_video_figure_rendering_test() ->
    Video =
        <<"<video class=\"theme-invert-video\" "
            "src=\"https://arweave.net/pc73dj9tZtj7AOeIKBGiiOm5ta13FYXzgsqWSePAxiM\" "
            "style=\"width: 100%; height: auto; display: block;\" autoplay=\"\" muted=\"\" "
            "playsinline=\"\" loop=\"\" controlslist=\"nodownload nofullscreen noremoteplayback\" "
            "disablepictureinpicture=\"\" preload=\"auto\"></video>">>,
    HTML = render_markdown(Video),
    ?assertEqual(Video, HTML),
    ?assertEqual(nomatch, binary:match(HTML, <<"&lt;video">>)),
    Concept =
        <<"<div class=\"core-concepts-flex\">\n"
            "<img class=\"core-concepts-fig messages\" src=\"/docs/assets/images/aosvg1.svg\" alt=\"\" loading=\"lazy\">\n"
            "<div class=\"core-concepts-column\">\n"
            "<p class=\"core-concept-header-messages\"><b>Messages</b></p>\n"
            "<span class=\"core-concept-subtitle\">Modular Data Packets</span>\n"
            "<p class=\"core-concept-copy\">Every interaction is a <b>message</b>.</p>\n"
            "</div>\n"
            "</div>">>,
    ConceptHTML = render_markdown(Concept),
    ?assertEqual(nomatch, binary:match(ConceptHTML, <<"&lt;div class=&quot;core-concepts-flex">>)),
    ?assert(binary:match(ConceptHTML, <<"src=\"/docs/assets/images/aosvg1.svg\"">>) =/= nomatch).

device_page_omits_section_index_test() ->
    Data = #{
        <<"device">> => #{ <<"id">> => <<"example@1.0">> },
        <<"summary">> => <<"Example device.">>,
        <<"schema">> => #{},
        <<"schema-order">> => [],
        <<"recipes">> => #{},
        <<"spec">> => #{
            <<"spec-status">> => <<"missing">>,
            <<"summary">> => <<"No published spec for this test.">>
        }
    },
    HTML = render_device_html(Data),
    ?assertEqual(nomatch, binary:match(HTML, <<"hb-docs-section-index">>)),
    ?assert(binary:match(HTML, <<"<h2 id=\"schema\">Schema</h2>">>) =/= nomatch),
    ?assert(binary:match(HTML, <<"<h2 id=\"spec\">Spec</h2>">>) =/= nomatch),
    ?assert(binary:match(HTML, <<"<h2 id=\"recipes\">Recipes</h2>">>) =/= nomatch).

placeholder_command_blocks_are_inspect_only_test() ->
    [Block] = code_blocks(
        <<"```sh\n"
            "curl http://localhost:8734/<process-id>~process@1.0/compute/counter\n"
            "```">>
    ),
    ?assertEqual(false, maps:get(<<"runnable">>, Block)).

arweave_without_spec_is_unsupported_test() ->
    ?assertNot(supported_device(?ARWEAVE_DEVICE)),
    Data = device_info_data(?ARWEAVE_DEVICE, #{}),
    ?assertEqual(<<"device-info">>, maps:get(<<"kind">>, Data)),
    ?assertEqual(<<"not-implemented">>, maps:get(<<"status">>, Data)),
    ?assertNot(maps:is_key(<<"schema">>, Data)),
    ?assertNot(maps:is_key(<<"recipes">>, Data)).

message_info_contract_test() ->
    Data = device_info_data(?MESSAGE_DEVICE, #{}),
    ?assertEqual(<<"device-info">>, maps:get(<<"kind">>, Data)),
    ?assertEqual(<<"message@1.0">>, maps:get(<<"device-id">>, Data)),
    ?assertEqual(<<"not-implemented">>, maps:get(<<"status">>, Data)),
    ?assertEqual(<<"not-documented">>, maps:get(<<"docs-status">>, Data)),
    ?assertNot(maps:is_key(<<"schema">>, Data)),
    ?assertNot(maps:is_key(<<"recipes">>, Data)).

packaged_device_docs_root_test() ->
    Root = hb_util:bin(packaged_device_docs_root()),
    ?assert(binary:match(Root, <<"priv/docs/cookbook/device-docs">>) =/= nomatch).

html_negotiation_test() ->
    {ok, JSON} = device_info(<<"json@1.0">>, #{ <<"accept">> => <<"application/json">> }, #{}),
    ?assertEqual(404, maps:get(<<"status">>, JSON)),
    ?assertEqual(<<"application/json">>, maps:get(<<"content-type">>, JSON)),
    ?assertEqual(<<"not-documented">>, maps:get(<<"docs-status">>, decoded_json_response(JSON))),
    {ok, HTML} = device_info(<<"json@1.0">>, #{ <<"accept">> => <<"text/html">> }, #{}),
    ?assertEqual(404, maps:get(<<"status">>, HTML)),
    ?assertEqual(<<"text/html; charset=utf-8">>, maps:get(<<"content-type">>, HTML)),
    Body = maps:get(<<"body">>, HTML),
    ?assert(binary:match(Body, <<"~json@1.0">>) =/= nomatch),
    ?assertEqual(nomatch, binary:match(Body, <<"<h2 id=\"schema\">Schema</h2><table>">>)),
    ?assertEqual(nomatch, binary:match(Body, <<"<h2 id=\"actions\">Actions</h2>">>)),
    ?assertEqual(nomatch, binary:match(Body, <<"hb-docs-action-grid">>)),
    ?assert(binary:match(Body, <<"docs not available">>) =/= nomatch),
    ?assertEqual(nomatch, binary:match(Body, <<"href=\"/~json@1.0/docs/recipes/serialize-message-to-json\"">>)),
    ?assertEqual(nomatch, binary:match(Body, <<"id=\"recipe-">>)),
    {ok, MissingRecipe} = device_info_route(
        <<"json@1.0">>,
        [<<"recipes">>, <<"serialize-message-to-json">>],
        #{ <<"accept">> => <<"text/html">> },
        #{}
    ),
    ?assertEqual(404, maps:get(<<"status">>, MissingRecipe)).

spec_sections_test() ->
    Spec = device_spec_status(?MESSAGE_DEVICE),
    Sections = spec_sections(Spec),
    ?assert(length(Sections) >= 8),
    ?assertEqual(<<"1-overview">>, element(1, hd(Sections))),
    ?assertEqual(<<"1. Overview">>, element(2, hd(Sections))),
    ?assertEqual(<<"Overview">>, spec_section_nav_label(<<"1. Overview">>)),
    ?assertEqual(<<"Concepts & terminology">>, spec_section_nav_label(<<"2. Concepts & terminology">>)),
    ?assertEqual(<<"Appendix">>, spec_section_nav_label(<<"Appendix">>)),
    ?assert(lists:any(
        fun({Id, _Title}) -> Id =:= <<"4-resolved-keys-normative">> end,
        Sections
    )).

message_markdown_rendering_test() ->
    SpecBody = iolist_to_binary(render_spec_body(device_spec_status(?MESSAGE_DEVICE))),
    ?assert(binary:match(SpecBody, <<"<strong>Device name:</strong>">>) =/= nomatch),
    ?assert(binary:match(SpecBody, <<"<strong>Dispatch shape">>) =/= nomatch),
    ?assertEqual(nomatch, binary:match(SpecBody, <<"**Dispatch shape">>)),
    ?assertEqual(nomatch, binary:match(SpecBody, <<"PRESENT">>)),
    ?assertEqual(nomatch, binary:match(SpecBody, <<"specs/message@1.0.md">>)),
    ?assert(binary:match(SpecBody, <<"<h4 id=\"1-overview\">Overview</h4>">>) =/= nomatch),
    ?assertEqual(nomatch, binary:match(SpecBody, <<"<h4 id=\"1-overview\">1. Overview</h4>">>)),
    ?assertEqual(nomatch, binary:match(SpecBody, <<"href=\"/~message@1.0/docs/spec#">>)).

schema_key_route_test() ->
    Msgs = [
        {as, ?MESSAGE_DEVICE, #{}},
        #{ <<"path">> => <<"docs">> },
        #{ <<"path">> => <<"schema">> },
        #{ <<"path">> => <<"docs">> }
    ],
    Req = #{ <<"accept">> => <<"text/html">> },
    {true, {ok, Response}} = maybe_info_request(Msgs, Req, #{}),
    ?assertEqual(404, maps:get(<<"status">>, Response)).

direct_schema_route_alias_removed_test() ->
    Msgs = hb_singleton:from(#{ <<"path">> => <<"/~message@1.0/schema/docs">> }, #{}),
    ?assertEqual(false, maybe_info_request(Msgs, #{ <<"accept">> => <<"text/html">> }, #{})).

direct_docs_route_alias_test() ->
    Msgs =
        hb_singleton:from(
            #{ <<"path">> => <<"/~message@1.0/docs/schema/docs">> },
            #{}
        ),
    Req = #{ <<"accept">> => <<"text/html">> },
    {true, {ok, Response}} = maybe_info_request(Msgs, Req, #{}),
    ?assertEqual(404, maps:get(<<"status">>, Response)).

node_docs_route_alias_test() ->
    Msgs = hb_singleton:from(#{ <<"path">> => <<"/docs/schema">> }, #{}),
    Req = #{ <<"accept">> => <<"application/json">> },
    {true, {ok, JSONResponse}} = maybe_info_request(Msgs, Req, #{}),
    JSON = decoded_json_response(JSONResponse),
    ?assertEqual(<<"node-schema-index">>, maps:get(<<"kind">>, JSON)).

request_hook_rewrites_docs_routes_test() ->
    Req = #{ <<"path">> => <<"/docs/schema">>, <<"accept">> => <<"application/json">> },
    Msgs = hb_singleton:from(Req, #{}),
    {ok, #{ <<"body">> := [#{ <<"device">> := ?COOKBOOK_DEVICE }, Route] }} =
        request_hook(#{ <<"request">> => Req, <<"body">> => Msgs }, #{}),
    ?assertEqual(<<"route">>, maps:get(<<"path">>, Route)),
    ?assertEqual(<<"node">>, maps:get(<<"docs-kind">>, Route)),
    ?assertEqual([<<"schema">>], maps:get(<<"docs-tail">>, Route)),
    ?assertEqual(Req, maps:get(<<"request">>, Route)),

    DeviceReq = #{ <<"path">> => <<"/~json@1.0/docs/recipes">> },
    DeviceMsgs = hb_singleton:from(DeviceReq, #{}),
    {ok, #{ <<"body">> := [#{ <<"device">> := ?COOKBOOK_DEVICE }, DeviceRoute] }} =
        request_hook(#{ <<"request">> => DeviceReq, <<"body">> => DeviceMsgs }, #{}),
    ?assertEqual(<<"device">>, maps:get(<<"docs-kind">>, DeviceRoute)),
    ?assertEqual(<<"json@1.0">>, maps:get(<<"docs-device">>, DeviceRoute)),
    ?assertEqual([<<"recipes">>], maps:get(<<"docs-tail">>, DeviceRoute)),

    InfoMsgs = hb_singleton:from(#{ <<"path">> => <<"/~meta@1.0/info/address">> }, #{}),
    ?assertEqual(
        {ok, #{ <<"body">> => InfoMsgs }},
        request_hook(#{ <<"body">> => InfoMsgs }, #{})
    ).

schema_source_contract_test() ->
    {Schema, _Order, Source} =
        docs_schema_for_device(
            ?MESSAGE_DEVICE,
            <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>,
            #{}
        ),
    ?assertEqual(<<"implementation-derived">>, maps:get(<<"mode">>, Source)),
    ?assertEqual(<<"present">>, maps:get(<<"status">>, Source)),
    ?assertNot(maps:is_key(<<"docs">>, Schema)),
    ?assertNot(maps:is_key(<<"schema">>, Schema)),
    SetSchema = maps:get(<<"set">>, Schema),
    ?assertEqual(<<"none">>, maps:get(<<"description-source">>, SetSchema)),
    ?assertNot(maps:is_key(<<"description">>, SetSchema)),
    ?assertNot(maps:is_key(<<"generated">>, Schema)).

schema_table_hides_blank_description_column_test() ->
    BlankSchema = #{
        <<"lookup">> => #{
            <<"description">> => <<>>,
            <<"parameters">> => #{}
        }
    },
    BlankHTML = iolist_to_binary(schema_table(<<"match@1.0">>, BlankSchema, [<<"lookup">>])),
    ?assertEqual(nomatch, binary:match(BlankHTML, <<"<th>Description</th>">>)),
    ?assert(binary:match(BlankHTML, <<"<th>Parameters</th>">>) =/= nomatch),
    ?assert(binary:match(BlankHTML, <<"param-pills-none\">none</span>">>) =/= nomatch),
    DescribedSchema = #{
        <<"lookup">> => #{
            <<"description">> => <<"Find matching messages.">>,
            <<"parameters">> => #{}
        }
    },
    DescribedHTML = iolist_to_binary(schema_table(<<"match@1.0">>, DescribedSchema, [<<"lookup">>])),
    ?assert(binary:match(DescribedHTML, <<"<th>Description</th>">>) =/= nomatch),
    ?assert(binary:match(DescribedHTML, <<"Find matching messages.">>) =/= nomatch).

device_summary_omits_spec_derived_prose_test() ->
    Summary = <<"match@1.0 maintains a **reverse index** that maps a (key, value) pair to">>,
    ?assertEqual(<<>>, device_summary(#{ <<"spec-status">> => <<"present">>, <<"summary">> => Summary })),
    ?assertEqual([], device_summary_paragraph(#{ <<"summary">> => <<>> })),
    ?assertEqual(
        [<<"<p>">>, <<"No published spec.">>, <<"</p>">>],
        device_summary_paragraph(#{ <<"summary">> => <<"No published spec.">> })
    ).

json_safe_schema_payload_test() ->
    ?assertEqual(
        #{
            <<"presence">> => <<"required">>,
            <<"ok">> => true,
            <<"tuple">> => [<<"ok">>, <<"optional">>],
            <<"1">> => <<"arity-key">>
        },
        json_safe(#{
            presence => required,
            ok => true,
            tuple => {ok, optional},
            1 => <<"arity-key">>
        })
    ),
    {ok, Schema, _Order, _Source} =
        implementation_derived_schema(?MESSAGE_DEVICE, #{}),
    SetSchema = maps:get(<<"set">>, Schema),
    SetRequest = maps:get(<<"request">>, maps:get(<<"type-schema">>, SetSchema)),
    SetWildcard = maps:get(<<"wildcard">>, SetRequest),
    ?assertEqual(<<"optional">>, maps:get(<<"presence">>, SetWildcard)).

canonical_specs_branch_registry_test() ->
    ?assertEqual(33, length(canonical_spec_devices())),
    ?assert(canonical_spec_device(<<"json@1.0">>)),
    ?assert(canonical_spec_device(<<"ans104@1.0">>)),
    ?assert(canonical_spec_device(<<"structured@1.0">>)),
    ?assertNot(canonical_spec_device(<<"arweave@2.9">>)),
    Data = device_info_data(<<"json@1.0">>, #{}),
    ?assertEqual(<<"device-info">>, maps:get(<<"kind">>, Data)),
    ?assertEqual(<<"json@1.0">>, maps:get(<<"device-id">>, Data)),
    ?assertEqual(<<"not-documented">>, maps:get(<<"docs-status">>, Data)),
    ?assertNot(maps:is_key(<<"schema">>, Data)),
    SpecID = <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>,
    Opts = #{
        <<"forge-bootstrap">> => #{SpecID => dev_json},
        <<"forge_bootstrap">> => #{SpecID => dev_json},
        forge_bootstrap => #{SpecID => dev_json},
        <<"name-resolvers">> => [#{<<"json@1.0">> => SpecID}]
    },
    Listed = maps:get(<<"devices">>, node_info_data(Opts)),
    ?assertEqual(1, length(Listed)),
    [Device] = Listed,
    ?assertEqual(<<"json">>, maps:get(<<"name">>, Device)),
    ?assertEqual(<<"/~json@1.0/docs">>, maps:get(<<"href">>, Device)).

derived_schema_description_source_test() ->
    {ok, Schema, _Order, _Source} =
        implementation_derived_schema(<<"json@1.0">>, #{}),
    ToSchema = maps:get(<<"to">>, Schema),
    ?assertNot(maps:is_key(<<"description">>, ToSchema)),
    ?assertEqual(<<"none">>, maps:get(<<"description-source">>, ToSchema)),
    ?assertEqual(<<"hb_types:extract/2">>, maps:get(<<"source">>, ToSchema)).

on_weave_schema_source_unavailable_test() ->
    {Schema, Order, Source} =
        docs_schema_for_device(
            <<"unknown-device@1.0">>,
            <<"spec-tx">>,
            #{}
        ),
    ?assertEqual(#{}, Schema),
    ?assertEqual([], Order),
    ?assertEqual(<<"implementation-derived-unavailable">>, maps:get(<<"mode">>, Source)),
    ?assertEqual(<<"unavailable">>, maps:get(<<"status">>, Source)),
    ?assert(maps:is_key(<<"reason">>, Source)).

schema_parameter_route_test() ->
    {ok, HTML} = device_info_route(
        <<"json@1.0">>,
        [<<"schema">>, <<"deserialize">>, <<"target">>],
        #{ <<"accept">> => <<"text/html">> },
        #{}
    ),
    ?assertEqual(404, maps:get(<<"status">>, HTML)).

recipes_index_route_test() ->
    {ok, HTML} = device_info_route(
        ?MESSAGE_DEVICE,
        [<<"recipes">>],
        #{ <<"accept">> => <<"text/html">> },
        #{}
    ),
    ?assertEqual(404, maps:get(<<"status">>, HTML)).

recipe_route_test() ->
    Msgs =
        hb_singleton:from(
            #{
                <<"path">> =>
                    <<"/~message@1.0/docs/recipes/build-a-message-and-serialize-it">>
            },
            #{}
        ),
    Req = #{ <<"accept">> => <<"text/html">> },
    {true, {ok, Response}} = maybe_info_request(Msgs, Req, #{}),
    ?assertEqual(404, maps:get(<<"status">>, Response)).

recipe_blacklist_filters_operator_config_test() ->
    Good = #{
        <<"name">> => <<"keep-this-recipe">>,
        <<"title">> => <<"Keep this recipe">>,
        <<"txid">> => <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>
    },
    Bad = #{
        <<"name">> => <<"bad-template">>,
        <<"title">> => <<"Bad template">>,
        <<"txid">> => <<"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb">>
    },
    Opts = #{
        <<"docs-recipe-blacklist">> => [
            #{
                <<"device">> => <<"match@1.0">>,
                <<"slug">> => <<"bad-template">>,
                <<"reason">> => <<"requires unseeded query index">>
            }
        ]
    },
    ?assert(recipe_blacklisted(<<"match@1.0">>, <<"spec-id">>, Bad, Opts)),
    ?assertNot(recipe_blacklisted(<<"match@1.0">>, <<"spec-id">>, Good, Opts)),
    ?assertEqual(
        [Good],
        apply_recipe_blacklist(<<"match@1.0">>, <<"spec-id">>, [Good, Bad], Opts)
    ).

recipe_blacklist_loads_operator_file_test() ->
    TXID = <<"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb">>,
    Dir = filename:join(["/tmp", "hb-docs-recipe-blacklist-test"]),
    ok = filelib:ensure_dir(filename:join(Dir, "blacklist.json")),
    Path = filename:join(Dir, "blacklist.json"),
    JSON =
        <<"{\"recipes\":[{\"txid\":\"", TXID/binary,
            "\",\"reason\":\"known bad fixture\"}]}">>,
    ok = file:write_file(Path, JSON),
    Recipe = #{
        <<"name">> => <<"bad-template">>,
        <<"title">> => <<"Bad template">>,
        <<"txid">> => TXID
    },
    Opts = #{ <<"docs-recipe-blacklist-file">> => hb_util:bin(Path) },
    ?assert(recipe_blacklisted(<<"match@1.0">>, <<"spec-id">>, Recipe, Opts)),
    BadPath = filename:join(Dir, "bad.json"),
    ok = file:write_file(BadPath, <<"{bad json">>),
    ?assertEqual(
        [],
        docs_recipe_blacklist(#{ <<"docs-recipe-blacklist-file">> => hb_util:bin(BadPath) })
    ).

footer_nav_test() ->
    {ok, SpecSectionHTML} = device_info_route(
        ?MESSAGE_DEVICE,
        [<<"spec">>, <<"1-overview">>],
        #{ <<"accept">> => <<"text/html">> },
        #{}
    ),
    ?assertEqual(404, maps:get(<<"status">>, SpecSectionHTML)).

spec_section_route_test() ->
    Msgs =
        hb_singleton:from(
            #{
                <<"path">> => <<"/~message@1.0/docs/spec/1-overview">>
            },
            #{}
        ),
    Req = #{ <<"accept">> => <<"text/html">> },
    {true, {ok, HTML}} = maybe_info_request(Msgs, Req, #{}),
    ?assertEqual(404, maps:get(<<"status">>, HTML)),
    {ok, NotFound} = device_info_route(
        ?MESSAGE_DEVICE,
        [<<"spec">>, <<"missing-section">>],
        #{ <<"accept">> => <<"text/html">> },
        #{}
    ),
    ?assertEqual(404, maps:get(<<"status">>, NotFound)).

device_recipes_summary_test() ->
    {ok, HTML} = device_info(?MESSAGE_DEVICE, #{ <<"accept">> => <<"text/html">> }, #{}),
    ?assertEqual(404, maps:get(<<"status">>, HTML)),
    Body = maps:get(<<"body">>, HTML),
    ?assertEqual(nomatch, binary:match(Body, <<"<h2 id=\"recipes\">Recipes</h2>">>)),
    ?assertEqual(nomatch, binary:match(Body, <<"href=\"/~message@1.0/docs/recipes/build-a-typed-message-and-read-fields\"">>)),
    ?assertEqual(nomatch, binary:match(Body, <<"href=\"/~message@1.0/docs/recipes/">>)),
    ?assertEqual(nomatch, binary:match(Body, <<"id=\"recipe-">>)),
    ?assertEqual(nomatch, binary:match(Body, <<"Runnable Workflows">>)).

card_summary_test() ->
    Long =
        <<"Use `~arweave@2.9` as the publishing boundary for signed ANS-104 data items "
            "and signed L1 transactions. This workflow also shows extra detail.">>,
    Short = card_summary(Long),
    ?assertEqual(
        <<"Use `~arweave@2.9` as the publishing boundary for signed ANS-104 data items "
            "and signed L1 transactions.">>,
        Short
    ),
    ?assert(byte_size(Short) =< ?CARD_SUMMARY_MAX),
    OneLine = <<"Fetch Arweave transactions as HyperBEAM messages.">>,
    ?assertEqual(OneLine, card_summary(OneLine)),
    OverLimit = lists:duplicate(130, $a),
    Truncated = card_summary(OverLimit),
    ?assertEqual(123, byte_size(Truncated)),
    ?assertEqual(<<"...">>, binary:part(Truncated, 120, 3)).

recipe_card_summary_test() ->
    Long =
        <<"Use `~arweave@2.9` as the publishing boundary for signed ANS-104 data items "
            "and signed L1 transactions. This workflow also shows extra detail.">>,
    Short = recipe_card_summary(#{ <<"summary">> => Long }),
    ?assertEqual(
        <<"Use `~arweave@2.9` as the publishing boundary for signed ANS-104 data items">>,
        Short
    ),
    ?assert(byte_size(Short) =< ?RECIPE_CARD_SUMMARY_MAX),
    ?assertEqual(
        <<"Custom tagline">>,
        recipe_card_summary(#{
            <<"summary">> => Long,
            <<"tagline">> => <<"Custom tagline">>
        })
    ).

recipe_card_layout_test() ->
    Recipe = #{
        <<"name">> => <<"quote-arweave-bytes">>,
        <<"title">> => <<"Quote Arweave Bytes">>,
        <<"summary">> =>
            <<"Use `~arweave-byte-pricing@1.1` to quote byte upload costs and "
                "inspect payment behavior before sending data. This sentence "
                "should not fit on the recipe card.">>,
        <<"runnable-block-count">> => 1,
        <<"block-count">> => 1
    },
    Body = iolist_to_binary(recipe_nav(<<"arweave-byte-pricing@1.1">>, #{
        <<"quote-arweave-bytes">> => Recipe
    })),
    FullSummary = maps:get(<<"summary">>, Recipe),
    CardSummary = recipe_card_summary(Recipe),
    ?assert(byte_size(CardSummary) < byte_size(FullSummary)),
    ?assert(byte_size(CardSummary) =< ?RECIPE_CARD_SUMMARY_MAX),
    ?assert(binary:match(Body, CardSummary) =/= nomatch),
    ?assertEqual(nomatch, binary:match(Body, <<"This sentence should not fit">>)),
    ?assert(binary:match(Body, <<"hb-docs-recipe-card-header">>) =/= nomatch),
    ?assert(binary:match(Body, <<"hb-docs-recipe-card-title">>) =/= nomatch),
    ?assert(binary:match(Body, <<"hb-docs-recipe-card-desc">>) =/= nomatch),
    ?assert(binary:match(Body, <<"hb-docs-recipe-card-cta\">Open &rarr;</span>">>) =/= nomatch),
    ?assert(binary:match(Body, <<"runnable</small></div></div></a>">>) =/= nomatch).

implementations_route_test() ->
    {ok, HTML} = device_info_route(
        ?MESSAGE_DEVICE,
        [<<"implementations">>],
        #{ <<"accept">> => <<"text/html">> },
        #{}
    ),
    ?assertEqual(404, maps:get(<<"status">>, HTML)).

node_component_routes_test() ->
    {ok, SchemaHTML} = node_info_route([<<"schema">>], #{ <<"accept">> => <<"text/html">> }, #{}),
    ?assert(binary:match(maps:get(<<"body">>, SchemaHTML), <<"Schema index">>) =/= nomatch),
    {ok, RecipesResponse} = node_info_route([<<"recipes">>], #{ <<"accept">> => <<"application/json">> }, #{}),
    Recipes = decoded_json_response(RecipesResponse),
    ?assertEqual(<<"node-recipes-index">>, maps:get(<<"kind">>, Recipes)),
    ?assertEqual([], maps:get(<<"devices">>, Recipes)).

boilerplate_routes_test() ->
    {ok, IndexResponse} = node_info_route([<<"guides">>], #{ <<"accept">> => <<"application/json">> }, #{}),
    Index = decoded_json_response(IndexResponse),
    ?assertEqual(<<"node-boilerplate-index">>, maps:get(<<"kind">>, Index)),
    ?assertEqual(<<"/docs/guides">>, maps:get(<<"href">>, Index)),
    Pages = maps:get(<<"pages">>, Index),
    ?assertEqual(21, length(Pages)),
    RelPaths = [maps:get(<<"source-relative">>, Page) || Page <- Pages],
    ProcessPages = boilerplate_pages_for_section(<<"Processes">>, Pages),
    ?assertEqual(7, length(ProcessPages)),
    ?assertEqual(
        [
            <<"Process Overview">>,
            <<"State And Reads">>,
            <<"Builder Templates">>,
            <<"AO Connect Mainnet">>,
            <<"AOS Lua Reference">>,
            <<"Migration To HyperBEAM">>,
            <<"Legacynet Appendix">>
        ],
        [maps:get(<<"title">>, Page) || Page <- ProcessPages]
    ),
    ?assertEqual(
        [
            <<"/docs/processes/overview">>,
            <<"/docs/processes/state-and-reads">>,
            <<"/docs/processes/builder-templates">>,
            <<"/docs/processes/ao-connect-mainnet">>,
            <<"/docs/processes/aos-lua-reference">>,
            <<"/docs/processes/migration-to-hyperbeam">>,
            <<"/docs/processes/legacynet-appendix">>
        ],
        [maps:get(<<"href">>, Page) || Page <- ProcessPages]
    ),
    ?assertNot(lists:member(<<"docs/index.md">>, RelPaths)),
    ?assert(lists:member(<<"docs/introduction/ao-devices.md">>, RelPaths)),
    ?assertNot(lists:member(<<"docs/devices/index.md">>, RelPaths)),
    ?assertNot(lists:member(<<"docs/recipes/index.md">>, RelPaths)),
    ?assertNot(lists:member(<<"docs/device-recipes/index.md">>, RelPaths)),
    ?assertNot(lists:member(<<"docs/reference/device-inventory.md">>, RelPaths)),
    ?assert(lists:all(
        fun(RelPath) -> binary:match(RelPath, <<"docs/devices/">>) =:= nomatch end,
        RelPaths
    )),
    ?assert(lists:all(
        fun(RelPath) -> binary:match(RelPath, <<"docs/reference/">>) =:= nomatch end,
        RelPaths
    )),
    ?assertNot(lists:member(
        <<"docs/devices/compute-and-processes/process-at-1-0/index.md">>,
        RelPaths
    )),
    ?assertNot(lists:member(
        <<"docs/devices/compute-and-processes/process-at-1-0/SUMMARY.md">>,
        RelPaths
    )),
    ?assertNot(lists:member(
        <<"docs/devices/compute-and-processes/process-at-1-0/SOURCE-MAP.md">>,
        RelPaths
    )),
    {ok, JSONResponse} = node_info_route(
        [<<"introduction">>, <<"what-is-hyperbeam">>],
        #{ <<"accept">> => <<"application/json">> },
        #{}
    ),
    JSON = decoded_json_response(JSONResponse),
    ?assertEqual(<<"node-boilerplate-page">>, maps:get(<<"kind">>, JSON)),
    ?assertEqual(<<"/docs/introduction/what-is-hyperbeam">>, maps:get(<<"href">>, JSON)),
    ?assertEqual(<<"docs/introduction/what-is-hyperbeam.md">>, maps:get(<<"source-relative">>, JSON)),
    ?assert(maps:get(<<"markdown-bytes">>, JSON) > 0),
    {ok, HTML} = node_info_route(
        [<<"introduction">>, <<"what-is-hyperbeam">>],
        #{ <<"accept">> => <<"text/html">> },
        #{}
    ),
    Body = maps:get(<<"body">>, HTML),
    ?assert(binary:match(Body, <<"What is HyperBEAM">>) =/= nomatch),
    ?assert(binary:match(Body, <<"HyperBEAM is the primary">>) =/= nomatch),
    ?assertEqual(nomatch, binary:match(Body, <<"Merged from the HyperBEAM">>)),
    ?assertEqual(nomatch, binary:match(Body, <<"/devices/">>)),
    ?assertEqual(nomatch, binary:match(Body, <<"href=\"/~process@1.0/docs\"">>)),
    ?assert(binary:match(Body, <<"class=\"theme-invert-video\"">>) =/= nomatch),
    ?assert(binary:match(Body, <<"src=\"/docs/assets/images/aosvg1.svg\"">>) =/= nomatch),
    ?assert(binary:match(Body, <<"class=\"core-concepts-flex\"">>) =/= nomatch),
    ?assertEqual(nomatch, binary:match(Body, <<"/docs/boilerplate">>)),
    {ok, IntroHTML} = node_info_route(
        [<<"introduction">>, <<"index">>],
        #{ <<"accept">> => <<"text/html">> },
        #{}
    ),
    IntroBody = maps:get(<<"body">>, IntroHTML),
    ?assert(binary:match(IntroBody, <<"href=\"/docs/introduction/what-is-hyperbeam\"">>) =/= nomatch),
    ?assert(binary:match(IntroBody, <<"href=\"/docs/introduction/ao-devices\"">>) =/= nomatch),
    ?assertEqual(nomatch, binary:match(IntroBody, <<"href=\"/docs/getting-started/example-style\"">>)),
    ?assertEqual(nomatch, binary:match(IntroBody, <<"href=\"/docs/devices/index\"">>)),
    ?assertEqual(nomatch, binary:match(IntroBody, <<"/docs/boilerplate">>)),
    ?assertEqual(nomatch, binary:match(IntroBody, <<"(what-is-hyperbeam.md)">>)),
    {ok, PathingHTML} = node_info_route(
        [<<"introduction">>, <<"pathing-in-ao-core">>],
        #{ <<"accept">> => <<"text/html">> },
        #{}
    ),
    PathingBody = maps:get(<<"body">>, PathingHTML),
    ?assert(binary:match(PathingBody, <<"Pathing in AO-Core">>) =/= nomatch),
    ?assertEqual(nomatch, binary:match(PathingBody, <<"Merged from the HyperBEAM">>)),
    ?assert(binary:match(PathingBody, <<"href=\"/~message@1.0/docs\"">>) =/= nomatch),
    ?assert(binary:match(PathingBody, <<"href=\"/~process@1.0/docs\"">>) =/= nomatch),
    ?assert(binary:match(PathingBody, <<"href=\"/~patch@1.0/docs\"">>) =/= nomatch),
    ?assert(binary:match(PathingBody, <<"href=\"/~structured@1.0/docs\"">>) =/= nomatch),
    ?assertEqual(nomatch, binary:match(PathingBody, <<"/devices/">>)),
    ?assertEqual(nomatch, binary:match(PathingBody, <<"/recipes/">>)),
    ?assertEqual(nomatch, binary:match(PathingBody, <<"/docs/recipes/patch-process-state">>)),
    ?assertEqual(nomatch, binary:match(PathingBody, <<"/docs/recipes/arweave-json-to-lua">>)),
    ?assertEqual(nomatch, binary:match(PathingBody, <<"/docs/boilerplate">>)),
    {ok, ProcessRootJSONResponse} = node_info_route(
        [<<"processes">>],
        #{ <<"accept">> => <<"application/json">> },
        #{}
    ),
    ProcessRootJSON = decoded_json_response(ProcessRootJSONResponse),
    ?assertEqual(<<"/docs/processes/overview">>, maps:get(<<"href">>, ProcessRootJSON)),
    ?assertEqual(<<"Process Overview">>, maps:get(<<"title">>, ProcessRootJSON)),
    {ok, ProcessJSONResponse} = node_info_route(
        [<<"processes">>, <<"state-and-reads">>],
        #{ <<"accept">> => <<"application/json">> },
        #{}
    ),
    ProcessJSON = decoded_json_response(ProcessJSONResponse),
    ?assertEqual(<<"State And Reads">>, maps:get(<<"title">>, ProcessJSON)),
    ?assertEqual(
        <<"docs/processes/state-and-reads.md">>,
        maps:get(<<"source-relative">>, ProcessJSON)
    ),
    {ok, ProcessHTML} = node_info_route(
        [<<"processes">>, <<"state-and-reads">>],
        #{ <<"accept">> => <<"text/html">> },
        #{}
    ),
    ProcessBody = maps:get(<<"body">>, ProcessHTML),
    ?assert(binary:match(ProcessBody, <<"State And Reads">>) =/= nomatch),
    ?assert(binary:match(ProcessBody, <<"<code>patch@1.0</code>">>) =/= nomatch),
    ?assertEqual(nomatch, binary:match(ProcessBody, <<"02-state-and-reads">>)),
    {ok, ForgeJSONResponse} = node_info_route(
        [<<"forge">>, <<"index">>],
        #{ <<"accept">> => <<"application/json">> },
        #{}
    ),
    ForgeJSON = decoded_json_response(ForgeJSONResponse),
    ?assertEqual(<<"/docs/forge/index">>, maps:get(<<"href">>, ForgeJSON)),
    ?assertEqual(<<"docs/forge/index.md">>, maps:get(<<"source-relative">>, ForgeJSON)),
    {ok, ForgeHTML} = node_info_route(
        [<<"forge">>, <<"index">>],
        #{ <<"accept">> => <<"text/html">> },
        #{}
    ),
    ForgeBody = maps:get(<<"body">>, ForgeHTML),
    ?assert(binary:match(ForgeBody, <<"Device Forge">>) =/= nomatch),
    ?assert(binary:match(ForgeBody, <<"href=\"/docs/forge/runbook\"">>) =/= nomatch),
    ?assertEqual(nomatch, binary:match(ForgeBody, <<"/docs/boilerplate">>)),
    IntroMsgs = hb_singleton:from(#{ <<"path">> => <<"/docs/introduction/what-is-ao-core">> }, #{}),
    {true, {ok, RootIntroHTML}} =
        maybe_info_request(IntroMsgs, #{ <<"accept">> => <<"text/html">> }, #{}),
    RootIntroBody = maps:get(<<"body">>, RootIntroHTML),
    ?assert(binary:match(RootIntroBody, <<"What is AO-Core">>) =/= nomatch),
    ?assert(binary:match(RootIntroBody, <<"data-active-path=\"/docs/introduction/what-is-ao-core\"">>) =/= nomatch),
    {ok, GuidesHTML} = node_info_route([<<"guides">>], #{ <<"accept">> => <<"text/html">> }, #{}),
    GuidesBody = maps:get(<<"body">>, GuidesHTML),
    ?assert(binary:match(GuidesBody, <<"hb-docs-recipe-card-title\">Create A Device</strong>">>) =/= nomatch),
    ?assert(binary:match(GuidesBody, <<"hb-docs-recipe-card-title\">Process Overview</strong>">>) =/= nomatch),
    ?assert(binary:match(GuidesBody, <<"hb-docs-recipe-card-cta\">Open &rarr;</span>">>) =/= nomatch),
    ?assert(binary:match(GuidesBody, <<"href=\"/docs/introduction/what-is-ao-core\"">>) =/= nomatch),
    ?assert(binary:match(GuidesBody, <<"href=\"/docs/processes/state-and-reads\"">>) =/= nomatch),
    ?assert(binary:match(GuidesBody, <<"href=\"/docs/forge/create-a-device\"">>) =/= nomatch),
    ?assertEqual(nomatch, binary:match(GuidesBody, <<"Merged from the HyperBEAM">>)),
    ?assertEqual(nomatch, binary:match(GuidesBody, <<"/docs/boilerplate">>)),
    ?assertEqual(nomatch, binary:match(GuidesBody, <<"01-intro-to-process">>)),
    ?assertEqual(nomatch, binary:match(GuidesBody, <<"SOURCE-MAP">>)),
    ?assert(binary:match(GuidesBody, <<"The HTTP-native protocol for decentralized computation">>) =/= nomatch),
    ?assertEqual(nomatch, binary:match(GuidesBody, <<"hb-docs-recipe-card-title\">Device Recipe Format</strong>">>)),
    ?assertEqual(nomatch, binary:match(GuidesBody, <<"Device Recipes">>)),
    ?assert(binary:match(GuidesBody, <<"AO Devices">>) =/= nomatch),
    ?assertEqual(nomatch, binary:match(GuidesBody, <<"Device Inventory">>)),
    {ok, OldIndex} = node_info_route([<<"boilerplate">>], #{ <<"accept">> => <<"application/json">> }, #{}),
    ?assertEqual(404, maps:get(<<"status">>, OldIndex)),
    {ok, OldOverview} = node_info_route([<<"boilerplate">>, <<"index">>], #{ <<"accept">> => <<"application/json">> }, #{}),
    ?assertEqual(404, maps:get(<<"status">>, OldOverview)),
    {ok, OldDevices} = node_info_route([<<"boilerplate">>, <<"devices">>, <<"index">>], #{ <<"accept">> => <<"application/json">> }, #{}),
    ?assertEqual(404, maps:get(<<"status">>, OldDevices)),
    {ok, OldAODevices} = node_info_route([<<"boilerplate">>, <<"introduction">>, <<"ao-devices">>], #{ <<"accept">> => <<"application/json">> }, #{}),
    ?assertEqual(404, maps:get(<<"status">>, OldAODevices)),
    {ok, OldRecipes} = node_info_route([<<"boilerplate">>, <<"recipes">>, <<"index">>], #{ <<"accept">> => <<"application/json">> }, #{}),
    ?assertEqual(404, maps:get(<<"status">>, OldRecipes)),
    {ok, OldDeviceRecipes} = node_info_route([<<"boilerplate">>, <<"device-recipes">>, <<"index">>], #{ <<"accept">> => <<"application/json">> }, #{}),
    ?assertEqual(404, maps:get(<<"status">>, OldDeviceRecipes)),
    {ok, OldDeviceInventory} = node_info_route([<<"boilerplate">>, <<"reference">>, <<"device-inventory">>], #{ <<"accept">> => <<"application/json">> }, #{}),
    ?assertEqual(404, maps:get(<<"status">>, OldDeviceInventory)),
    {ok, ReferenceJSONResponse} = node_info_route([<<"reference">>, <<"example">>], #{ <<"accept">> => <<"application/json">> }, #{}),
    ?assertEqual(404, maps:get(<<"status">>, ReferenceJSONResponse)),
    {ok, DeviceInventory} = node_info_route([<<"reference">>, <<"device-inventory">>], #{ <<"accept">> => <<"application/json">> }, #{}),
    ?assertEqual(404, maps:get(<<"status">>, DeviceInventory)),
    {ok, ProcessIndex} = node_info_route([<<"processes">>, <<"index">>], #{ <<"accept">> => <<"application/json">> }, #{}),
    ?assertEqual(404, maps:get(<<"status">>, ProcessIndex)),
    {ok, ProcessSummary} = node_info_route([<<"processes">>, <<"summary">>], #{ <<"accept">> => <<"application/json">> }, #{}),
    ?assertEqual(404, maps:get(<<"status">>, ProcessSummary)),
    {ok, ProcessSourceMap} = node_info_route([<<"processes">>, <<"source-map">>], #{ <<"accept">> => <<"application/json">> }, #{}),
    ?assertEqual(404, maps:get(<<"status">>, ProcessSourceMap)).

cookbook_device_contract_test() ->
    Data = device_info_data(?COOKBOOK_DEVICE, #{}),
    ?assertEqual(<<"device-info">>, maps:get(<<"kind">>, Data)),
    ?assertEqual(<<"not-documented">>, maps:get(<<"docs-status">>, Data)),
    {ok, Schema, _Order, _Source} = implementation_derived_schema(?COOKBOOK_DEVICE, #{}),
    ?assert(maps:is_key(<<"device">>, Schema)),
    DeviceKey = maps:get(<<"device">>, Schema),
    ?assertEqual(<<"for">>, maps:get(<<"parameter-names">>, DeviceKey)),
    ?assertEqual(<<>>, maps:get(<<"required-parameters">>, DeviceKey)).

recipe_card_icons_test() ->
    ?assertEqual(<<"package">>, recipe_icon_name(<<"inspect-and-reassemble-bundles">>, <<"Inspect And Reassemble Bundles">>)),
    ?assertEqual(<<"upload">>, recipe_icon_name(<<"post-signed-data-to-arweave">>, <<"Post Signed Data">>)),
    ?assertEqual(<<"export">>, recipe_icon_name(<<"build-a-message-and-serialize-it">>, <<"Build a message">>)),
    Recipes = #{
        <<"inspect-and-reassemble-bundles">> => #{
            <<"name">> => <<"inspect-and-reassemble-bundles">>,
            <<"title">> => <<"Inspect And Reassemble Bundles">>,
            <<"summary">> => <<"Inspect a bundle transaction.">>,
            <<"runnable-block-count">> => 1
        }
    },
    Body = iolist_to_binary(recipe_nav(<<"arweave-byte-pricing@1.1">>, Recipes)),
    ?assert(binary:match(Body, <<"hb-docs-recipe-card">>) =/= nomatch),
    ?assert(binary:match(Body, <<"hb-docs-recipe-card-header">>) =/= nomatch),
    ?assert(binary:match(Body, <<"hb-docs-recipe-card-icon">>) =/= nomatch),
    ?assert(binary:match(Body, <<"hb-docs-recipe-card-title">>) =/= nomatch),
    PackagePath = maps:get(<<"package">>, recipe_icon_paths()),
    ?assert(binary:match(Body, PackagePath) =/= nomatch).

on_chain_link_rendering_test() ->
    TXID = <<"dsVrhmExq_Bz8PXs7CYnaqXRG5pHLjJhRTT69wFsrvY">>,
    Recipe = #{
        <<"txid">> => TXID,
        <<"source-relative">> => <<"weave:", TXID/binary>>
    },
    RecipeLink = iolist_to_binary(on_chain_link_paragraph(Recipe, <<"View recipe transaction">>)),
    ?assert(binary:match(RecipeLink, <<"hb-docs-chain-link">>) =/= nomatch),
    ?assert(binary:match(RecipeLink, <<"hb-docs-chain-link-icon">>) =/= nomatch),
    ?assert(binary:match(RecipeLink, <<"View recipe transaction">>) =/= nomatch),
    ?assert(binary:match(RecipeLink, <<"https://viewblock.io/arweave/tx/", TXID/binary>>) =/= nomatch),
    ?assertEqual(nomatch, binary:match(RecipeLink, <<"weave:", TXID/binary>>)),
    ?assertEqual(TXID, on_chain_txid(<<"weave:", TXID/binary>>)),
    ImplCell = iolist_to_binary(implementation_source_cell(#{ <<"source">> => TXID })),
    ?assert(binary:match(ImplCell, <<"View implementation transaction">>) =/= nomatch),
    ?assert(binary:match(ImplCell, <<"https://viewblock.io/arweave/tx/", TXID/binary>>) =/= nomatch),
    SpecLink = iolist_to_binary(spec_tx_link(#{ <<"txid">> => TXID }, <<>>)),
    ?assert(binary:match(SpecLink, <<"View spec transaction">>) =/= nomatch).

device_card_label_test() ->
    ?assertEqual(<<"~arweave@2.9">>, device_marked_id(<<"arweave@2.9">>)),
    ?assertEqual(<<"~message@1.0">>, device_marked_id(<<"message@1.0">>)),
    ?assertEqual(<<"~arweave@2.9">>, device_marked_id(<<"~arweave@2.9">>)),
    Msgs = hb_singleton:from(#{ <<"path">> => <<"/docs">> }, #{}),
    Req = #{ <<"accept">> => <<"text/html">> },
    {true, {ok, HTML}} = maybe_info_request(Msgs, Req, #{}),
    Body = maps:get(<<"body">>, HTML),
    ?assertEqual(nomatch, binary:match(Body, <<"hb-docs-device-card-id\">~arweave@2.9</span>">>)),
    ?assertEqual(nomatch, binary:match(Body, <<"hb-docs-device-card-id\">~message@1.0</span>">>)),
    ?assertEqual(nomatch, binary:match(Body, <<"hb-docs-device-card-header">>)).

docs_asset_route_test() ->
    Msgs = [
        #{},
        #{ <<"path">> => <<"docs">> },
        #{ <<"path">> => <<"assets">> },
        #{ <<"path">> => <<"site.css">> }
    ],
    {true, {ok, CSS}} = maybe_info_request(Msgs, #{}, #{}),
    ?assertEqual(200, maps:get(<<"status">>, CSS)),
    ?assertEqual(<<"text/css; charset=utf-8">>, maps:get(<<"content-type">>, CSS)),
    ?assert(binary:match(maps:get(<<"body">>, CSS), <<"hb-runner">>) =/= nomatch),
    ImageMsgs = [
        #{},
        #{ <<"path">> => <<"docs">> },
        #{ <<"path">> => <<"assets">> },
        #{ <<"path">> => <<"images">> },
        #{ <<"path">> => <<"aosvg1.svg">> }
    ],
    {true, {ok, SVG}} = maybe_info_request(ImageMsgs, #{}, #{}),
    ?assertEqual(200, maps:get(<<"status">>, SVG)),
    ?assertEqual(<<"image/svg+xml">>, maps:get(<<"content-type">>, SVG)),
    ?assert(binary:match(maps:get(<<"body">>, SVG), <<"<svg">>) =/= nomatch).

canonical_and_unsupported_device_info_route_test() ->
    JSONMsgs = hb_singleton:from(#{ <<"path">> => <<"/~json@1.0/docs">> }, #{}),
    {true, {ok, JSONResponse}} =
        maybe_info_request(JSONMsgs, #{ <<"accept">> => <<"application/json">> }, #{}),
    JSON = decoded_json_response(JSONResponse),
    ?assertEqual(404, maps:get(<<"status">>, JSONResponse)),
    ?assertEqual(<<"json@1.0">>, maps:get(<<"device-id">>, JSON)),
    ?assertEqual(<<"not-documented">>, maps:get(<<"docs-status">>, JSON)),
    ?assertNotEqual(<<"message@1.0">>, maps:get(<<"device-id">>, JSON)),

    HTMLMsgs = hb_singleton:from(#{ <<"path">> => <<"/~ans104@1.0/docs">> }, #{}),
    {true, {ok, HTML}} =
        maybe_info_request(HTMLMsgs, #{ <<"accept">> => <<"text/html">> }, #{}),
    ?assertEqual(404, maps:get(<<"status">>, HTML)),
    ?assertEqual(<<"text/html; charset=utf-8">>, maps:get(<<"content-type">>, HTML)),
    Body = maps:get(<<"body">>, HTML),
    ?assert(binary:match(Body, <<"~ans104@1.0">>) =/= nomatch),
    ?assertEqual(nomatch, binary:match(Body, <<"Construct messages from URL fields">>)),

    {ok, StructuredSchemaResponse} = device_info_route(
        <<"structured@1.0">>,
        [<<"schema">>],
        #{ <<"accept">> => <<"application/json">> },
        #{}
    ),
    StructuredSchema = decoded_json_response(StructuredSchemaResponse),
    ?assertEqual(404, maps:get(<<"status">>, StructuredSchemaResponse)),
    ?assertEqual(<<"not-documented">>, maps:get(<<"docs-status">>, StructuredSchema)),

    UnknownMsgs = hb_singleton:from(#{ <<"path">> => <<"/~not-real@1.0/docs">> }, #{}),
    {true, {ok, UnknownResponse}} =
        maybe_info_request(UnknownMsgs, #{ <<"accept">> => <<"application/json">> }, #{}),
    Unknown = decoded_json_response(UnknownResponse),
    ?assertEqual(404, maps:get(<<"status">>, UnknownResponse)),
    ?assertEqual(<<"not-real@1.0">>, maps:get(<<"device-id">>, Unknown)),
    ?assertEqual(<<"not-documented">>, maps:get(<<"docs-status">>, Unknown)).

node_info_sidebar_context_test() ->
    Msgs = hb_singleton:from(#{ <<"path">> => <<"/docs">> }, #{}),
    Req = #{ <<"accept">> => <<"text/html">> },
    {true, {ok, HTML}} = maybe_info_request(Msgs, Req, #{}),
    Body = maps:get(<<"body">>, HTML),
    ?assert(binary:match(Body, <<"<p class=\"eyebrow\">You are viewing</p>">>) =/= nomatch),
    ?assert(binary:match(Body, <<"sidebar-viewing-device is-active\" href=\"/docs\">Node</a>">>) =/= nomatch),
    ?assert(binary:match(Body, <<"<h2 id=\"devices\">Devices</h2>">>) =/= nomatch),
    ?assertEqual(nomatch, binary:match(Body, <<"sidebar-viewing-back\" href=\"/docs\">View All Node Info</a>">>)).

device_info_sidebar_all_devices_anchor_test() ->
    Markup = iolist_to_binary(sidebar_device_context(<<"/~json@1.0/docs">>, <<"json@1.0">>)),
    ?assert(binary:match(Markup, <<"href=\"/docs#devices\"">>) =/= nomatch),
    ?assert(binary:match(Markup, <<"View All Devices</a>">>) =/= nomatch),
    ?assertEqual(nomatch, binary:match(Markup, <<"href=\"/docs/schema\"">>)).

node_info_request_match_test() ->
    Msgs = hb_singleton:from(#{ <<"path">> => <<"/docs">> }, #{}),
    ?assert(is_node_info_request(Msgs, #{})),
    DeviceMsgs = hb_singleton:from(#{ <<"path">> => <<"/~arweave@2.9/docs">> }, #{}),
    ?assertNot(is_node_info_request(DeviceMsgs, #{})).

info_paths_remain_device_paths_test() ->
    NodeInfo = hb_singleton:from(#{ <<"path">> => <<"/info">> }, #{}),
    MetaInfoAddress =
        hb_singleton:from(#{ <<"path">> => <<"/~meta@1.0/info/address">> }, #{}),
    MessageInfoSchema =
        hb_singleton:from(#{ <<"path">> => <<"/~message@1.0/info/schema">> }, #{}),
    ?assertEqual(false, maybe_info_request(NodeInfo, #{}, #{})),
    ?assertEqual(false, maybe_info_request(MetaInfoAddress, #{}, #{})),
    ?assertEqual(false, maybe_info_request(MessageInfoSchema, #{}, #{})).
