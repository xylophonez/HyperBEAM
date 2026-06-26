%%% @doc Prototype protocol-native documentation payloads for HyperBEAM.
-module(hb_docs).
-export([node_info/2, device_info/3, maybe_info_request/3, is_node_info_request/2]).
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
    render_unsupported_device_html/1
]).

-include("include/hb.hrl").
-include_lib("eunit/include/eunit.hrl").

-define(ARWEAVE_DEVICE, <<"arweave@2.9">>).
-define(MESSAGE_DEVICE, <<"message@1.0">>).
-define(COOKBOOK_DEVICE, <<"cookbook@1.0">>).
-define(PACKAGED_DEVICE_DOCS_ROOT, ["docs", "cookbook", "device-docs"]).

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
node_info_route([<<"reference">> | Parts], Req, _Opts) ->
    boilerplate_page_response([<<"reference">> | Parts], Req);
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

prototype_node_device(DeviceID, Name, Version, Summary) ->
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
    Recipes = maps:merge(
        static_device_recipes(Device),
        on_weave_recipe_docs_if_enabled(Device, SpecID, <<>>, Opts)
    ),
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
    prototype_node_device(
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
    Recipes = maps:merge(
        static_device_recipes(Device),
        on_weave_recipe_docs_if_enabled(Device, SpecID, SpecSigner, Opts)
    ),
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

on_weave_recipe_docs_if_enabled(_Device, <<>>, _SpecSigner, _Opts) ->
    #{};
on_weave_recipe_docs_if_enabled(Device, SpecID, SpecSigner, Opts) ->
    case docs_recipe_source_mode(Opts) of
        <<"static-curated">> ->
            #{};
        <<"static-only">> ->
            #{};
        <<"off">> ->
            #{};
        _ ->
            on_weave_recipe_docs(Device, SpecID, SpecSigner, Opts)
    end.

docs_recipe_source_mode(Opts) ->
    hb_opts:get(
        <<"docs-recipe-source-mode">>,
        hb_opts:get(docs_recipe_source_mode, <<"on-weave-and-static">>, Opts),
        Opts
    ).

static_device_recipes(Device) ->
    lists:foldl(
        fun({Slug, RelPath, Devices}, Acc) ->
            case lists:member(Device, Devices) of
                true ->
                    Acc#{Slug => static_recipe_doc(Slug, RelPath, Devices)};
                false ->
                    Acc
            end
        end,
        #{},
        static_recipe_pages()
    ).

static_recipe_doc(Slug, RelPath, Devices) ->
    Source = device_docs_path(RelPath),
    case file:read_file(binary_to_list(Source)) of
        {ok, RawMarkdown} ->
            Markdown = sanitize_boilerplate_markdown(RawMarkdown),
            Blocks = code_blocks(Markdown),
            Runnable = [Block || Block <- Blocks, maps:get(<<"runnable">>, Block, false) =:= true],
            #{
                <<"name">> => Slug,
                <<"title">> => markdown_title(Markdown, Slug),
                <<"summary">> => markdown_summary(Markdown),
                <<"source">> => <<"static-cookbook">>,
                <<"source-relative">> => RelPath,
                <<"recipe-status">> => <<"curated">>,
                <<"block-count">> => length(Blocks),
                <<"runnable-block-count">> => length(Runnable),
                <<"blocks">> => Blocks,
                <<"markdown">> => Markdown,
                <<"devices">> => Devices
            };
        {error, Reason} ->
            #{
                <<"name">> => Slug,
                <<"title">> => Slug,
                <<"summary">> => <<"Curated recipe source could not be loaded.">>,
                <<"source">> => <<"static-cookbook">>,
                <<"source-relative">> => RelPath,
                <<"recipe-status">> => <<"missing">>,
                <<"error">> => format_reason(Reason),
                <<"block-count">> => 0,
                <<"runnable-block-count">> => 0,
                <<"devices">> => Devices
            }
    end.

static_recipe_pages() ->
    [
        {<<"arweave-json-to-lua">>, <<"docs/recipes/arweave-json-to-lua.md">>,
            [<<"lua@5.3a">>, <<"json@1.0">>, <<"message@1.0">>]},
        {<<"bundle-data-locally">>, <<"docs/recipes/bundle-data-locally.md">>,
            [<<"ans104@1.0">>, <<"message@1.0">>]},
        {<<"create-a-process">>, <<"docs/recipes/create-a-process.md">>,
            [<<"message@1.0">>, <<"scheduler@1.0">>, <<"push@1.0">>, <<"lua@5.3a">>, <<"node-process@1.0">>]},
        {<<"gzip-round-trip">>, <<"docs/recipes/gzip-round-trip.md">>,
            [<<"gzip@1.0">>, <<"message@1.0">>]},
        {<<"inspect-transaction-codec">>, <<"docs/recipes/inspect-transaction-codec.md">>,
            [<<"tx@1.0">>, <<"ans104@1.0">>]},
        {<<"message-to-json-pipe">>, <<"docs/recipes/message-to-json-pipe.md">>,
            [<<"message@1.0">>, <<"json@1.0">>]},
        {<<"paid-device-access">>, <<"docs/recipes/paid-device-access.md">>,
            [<<"metering@1.0">>, <<"p4@1.0">>]},
        {<<"patch-process-state">>, <<"docs/recipes/patch-process-state.md">>,
            [<<"patch@1.0">>, <<"message@1.0">>, <<"node-process@1.0">>]},
        {<<"query-local-cache">>, <<"docs/recipes/query-local-cache.md">>,
            [<<"match@1.0">>]},
        {<<"read-meta-node-info">>, <<"docs/recipes/read-meta-node-info.md">>,
            [<<"meta@1.0">>]},
        {<<"read-seeded-process-state">>, <<"docs/recipes/read-seeded-process-state.md">>,
            [<<"node-process@1.0">>, <<"scheduler@1.0">>, <<"push@1.0">>]},
        {<<"recorder-debug-flight">>, <<"docs/recipes/recorder-debug-flight.md">>,
            [<<"recorder@1.0">>]},
        {<<"relay-fetch-transform">>, <<"docs/recipes/relay-fetch-transform.md">>,
            [<<"relay@1.0">>, <<"router@1.0">>]},
        {<<"scheduled-lua-process">>, <<"docs/recipes/scheduled-lua-process.md">>,
            [<<"lua@5.3a">>, <<"scheduler@1.0">>, <<"message@1.0">>, <<"node-process@1.0">>]}
    ].

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
    Pages = [boilerplate_page_entry(Page) || Page <- boilerplate_pages()],
    #{
        <<"kind">> => <<"node-boilerplate-index">>,
        <<"href">> => <<"/docs/guides">>,
        <<"summary">> =>
            <<"Conceptual HyperBEAM, AO-Core, process, and Device Forge guides.">>,
        <<"source-root">> => hb_util:bin(device_docs_root()),
        <<"ui-source">> => <<"priv/docs/cookbook/device-docs/site">>,
        <<"build-script">> => <<"priv/docs/cookbook/device-docs/scripts/build-docs-site.mjs">>,
        <<"pages">> => Pages
    }.

boilerplate_page_payload(Parts) ->
    case boilerplate_relpath_from_parts(Parts) of
        undefined ->
            not_found;
        RelPath ->
            case lists:keyfind(RelPath, 2, boilerplate_pages()) of
                false ->
                    not_found;
                Page ->
                    Entry = boilerplate_page_entry(Page),
                    Source = device_docs_path(RelPath),
                    case file:read_file(binary_to_list(Source)) of
                        {ok, RawMarkdown} ->
                            Markdown = sanitize_boilerplate_markdown(RawMarkdown),
                            {ok, Entry#{
                                <<"kind">> => <<"node-boilerplate-page">>,
                                <<"markdown">> => Markdown,
                                <<"markdown-bytes">> => byte_size(Markdown)
                            }};
                        {error, Reason} ->
                            {ok, Entry#{
                                <<"kind">> => <<"node-boilerplate-page">>,
                                <<"markdown">> => <<>>,
                                <<"error">> => hb_util:bin(io_lib:format("~tp", [Reason]))
                            }}
                    end
            end
    end.

boilerplate_relpath_from_parts([]) ->
    undefined;
boilerplate_relpath_from_parts([Section])
    when Section =:= <<"introduction">>; Section =:= <<"forge">> ->
    boilerplate_relpath_from_parts([Section, <<"index">>]);
boilerplate_relpath_from_parts([<<"processes">>]) ->
    boilerplate_relpath_from_parts([<<"processes">>, <<"overview">>]);
boilerplate_relpath_from_parts([<<"processes">>, Slug]) ->
    boilerplate_process_route(Slug);
boilerplate_relpath_from_parts(Parts) ->
    case lists:all(fun safe_route_part/1, Parts) of
        true ->
            iolist_to_binary([<<"docs/">>, lists:join(<<"/">>, Parts), <<".md">>]);
        false ->
            undefined
    end.

safe_route_part(Part) when is_binary(Part) ->
    Part =/= <<>> andalso
        binary:match(Part, <<"/">>) =:= nomatch andalso
        binary:match(Part, <<"..">>) =:= nomatch;
safe_route_part(_) ->
    false.

boilerplate_page_entry({Section, RelPath, FallbackTitle}) ->
    Source = device_docs_path(RelPath),
    Markdown =
        case file:read_file(binary_to_list(Source)) of
            {ok, Body} -> sanitize_boilerplate_markdown(Body);
            {error, _Reason} -> <<>>
        end,
    Title =
        case boilerplate_title_override(RelPath) of
            undefined -> markdown_title(Markdown, FallbackTitle);
            OverrideTitle -> OverrideTitle
        end,
    #{
        <<"section">> => Section,
        <<"title">> => Title,
        <<"summary">> => boilerplate_card_summary(RelPath, Markdown),
        <<"href">> => boilerplate_href(RelPath),
        <<"source">> => Source,
        <<"source-relative">> => RelPath
    }.

boilerplate_title_override(RelPath) ->
    case lists:keyfind(RelPath, 2, boilerplate_process_pages()) of
        {_, RelPath, Title} -> Title;
        false -> undefined
    end.

boilerplate_href(<<"docs/", Rest/binary>>) ->
    case boilerplate_href_override(<<"docs/", Rest/binary>>) of
        undefined ->
            WithoutExt = strip_suffix(Rest, <<".md">>),
            boilerplate_href_from_doc_path(WithoutExt);
        Href ->
            Href
    end;
boilerplate_href(RelPath) ->
    case boilerplate_href_override(RelPath) of
        undefined ->
            WithoutExt = strip_suffix(RelPath, <<".md">>),
            boilerplate_href_from_doc_path(WithoutExt);
        Href ->
            Href
    end.

boilerplate_href_override(RelPath) ->
    case lists:keyfind(RelPath, 2, boilerplate_process_pages()) of
        {Slug, RelPath, _Title} -> <<"/docs/processes/", Slug/binary>>;
        false -> undefined
    end.

boilerplate_href_from_doc_path(<<"introduction/", Rest/binary>>) ->
    <<"/docs/introduction/", Rest/binary>>;
boilerplate_href_from_doc_path(<<"forge/", Rest/binary>>) ->
    <<"/docs/forge/", Rest/binary>>;
boilerplate_href_from_doc_path(Path) ->
    <<"/docs/", Path/binary>>.

boilerplate_card_summary(RelPath, Markdown) ->
    case boilerplate_card_summary_override(RelPath) of
        undefined ->
            markdown_summary(Markdown);
        Summary ->
            Summary
    end.

boilerplate_card_summary_override(<<"docs/introduction/index.md">>) ->
    <<"The conceptual start for this corpus: HyperBEAM, AO-Core, devices, and pathing.">>;
boilerplate_card_summary_override(<<"docs/introduction/what-is-hyperbeam.md">>) ->
    <<"The production-ready AO-Core runtime that powers decentralized compute on Erlang/OTP.">>;
boilerplate_card_summary_override(<<"docs/introduction/what-is-ao-core.md">>) ->
    <<"The HTTP-native protocol for decentralized computation on the Arweave permaweb.">>;
boilerplate_card_summary_override(<<"docs/introduction/pathing-in-ao-core.md">>) ->
    <<"How HyperPATH URLs address messages, devices, and computation results.">>;
boilerplate_card_summary_override(<<"docs/devices/compute-and-processes/process-at-1-0/01-intro-to-process@1.0.md">>) ->
    <<"Create and understand HyperBEAM process@1.0 processes, messages, and authorities.">>;
boilerplate_card_summary_override(<<"docs/devices/compute-and-processes/process-at-1-0/02-state-and-reads.md">>) ->
    <<"Expose process state through patch@1.0 and read it over HTTP.">>;
boilerplate_card_summary_override(<<"docs/devices/compute-and-processes/process-at-1-0/03-builder-templates.md">>) ->
    <<"Copy practical Lua process templates for tokens, chats, and public state.">>;
boilerplate_card_summary_override(<<"docs/devices/compute-and-processes/process-at-1-0/04-aoconnect-mainnet.md">>) ->
    <<"Spawn, message, and read HyperBEAM processes from JavaScript clients.">>;
boilerplate_card_summary_override(<<"docs/devices/compute-and-processes/process-at-1-0/05-aos-lua-reference.md">>) ->
    <<"Keep the AOS Lua commands, globals, handlers, and replies close at hand.">>;
boilerplate_card_summary_override(<<"docs/devices/compute-and-processes/process-at-1-0/06-migration-to-hyperbeam.md">>) ->
    <<"Move legacy AO process patterns to HyperBEAM HTTP reads and patch updates.">>;
boilerplate_card_summary_override(<<"docs/devices/compute-and-processes/process-at-1-0/07-legacynet-appendix.md">>) ->
    <<"Reference old Legacynet AO patterns only when supporting existing processes.">>;
boilerplate_card_summary_override(_) ->
    undefined.

sanitize_boilerplate_markdown(Markdown) ->
    lists:foldl(
        fun(Needle, Acc) ->
            binary:replace(Acc, Needle, <<>>, [global])
        end,
        Markdown,
        [
            <<"> Merged from the HyperBEAM `edge` documentation at commit "
                "c6a16a26dc4ddca55c57db2fd7be6b898d105bb3. Local links have been "
                "adjusted for this combined docs corpus.\n\n">>,
            <<"> Merged from the HyperBEAM `edge` documentation at commit "
                "`c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`. Local links have been "
                "adjusted for this combined docs corpus.\n\n">>,
            <<"> Merged from the HyperBEAM edge documentation at commit "
                "c6a16a26dc4ddca55c57db2fd7be6b898d105bb3. Local links have been "
                "adjusted for this combined docs corpus.\n\n">>,
            <<"> Merged from the HyperBEAM `edge` documentation at commit "
                "c6a16a26dc4ddca55c57db2fd7be6b898d105bb3. Local links have been "
                "adjusted for this combined docs corpus.\n">>,
            <<"> Merged from the HyperBEAM `edge` documentation at commit "
                "`c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`. Local links have been "
                "adjusted for this combined docs corpus.\n">>,
            <<"> Merged from the HyperBEAM edge documentation at commit "
                "c6a16a26dc4ddca55c57db2fd7be6b898d105bb3. Local links have been "
                "adjusted for this combined docs corpus.\n">>
        ]
    ).

strip_suffix(Bin, Suffix) ->
    case ends_with(Bin, Suffix) of
        true -> binary:part(Bin, 0, byte_size(Bin) - byte_size(Suffix));
        false -> Bin
    end.

boilerplate_pages() ->
    [
        {<<"Introduction">>, <<"docs/introduction/index.md">>, <<"Introduction">>},
        {<<"Introduction">>, <<"docs/introduction/what-is-hyperbeam.md">>, <<"What Is HyperBEAM?">>},
        {<<"Introduction">>, <<"docs/introduction/what-is-ao-core.md">>, <<"What Is AO-Core?">>},
        {<<"Introduction">>, <<"docs/introduction/pathing-in-ao-core.md">>, <<"Pathing In AO-Core">>}
    ] ++ [
        {<<"Processes">>, RelPath, Title}
    || {_Slug, RelPath, Title} <- boilerplate_process_pages()
    ] ++ [
        {<<"Device Forge">>, <<"docs/forge/index.md">>, <<"Device Forge">>},
        {<<"Device Forge">>, <<"docs/forge/create-a-device.md">>, <<"Create A Device">>},
        {<<"Device Forge">>, <<"docs/forge/install-template.md">>, <<"Install Template">>},
        {<<"Device Forge">>, <<"docs/forge/operator-configuration.md">>, <<"Operator Configuration">>},
        {<<"Device Forge">>, <<"docs/forge/publish-and-load.md">>, <<"Publish And Load">>},
        {<<"Device Forge">>, <<"docs/forge/run-local.md">>, <<"Run Local">>},
        {<<"Device Forge">>, <<"docs/forge/runbook.md">>, <<"Runbook">>},
        {<<"Device Forge">>, <<"docs/forge/test-package-verify.md">>, <<"Test Package Verify">>},
        {<<"Device Forge">>, <<"docs/forge/trusted-signers-and-pins.md">>, <<"Trusted Signers And Pins">>}
    ] ++ [
        {<<"Reference">>, <<"docs/reference/example-validation.md">>, <<"Example Validation">>},
        {<<"Reference">>, <<"docs/reference/process-fixture.md">>, <<"Process Fixture">>},
        {<<"Reference">>, <<"docs/reference/recipe-standards.md">>, <<"Recipe Standards">>},
        {<<"Reference">>, <<"docs/reference/recipe-audit-2026-06-25.md">>, <<"Recipe Audit 2026-06-25">>}
    ].

boilerplate_process_route(Slug) ->
    case lists:keyfind(Slug, 1, boilerplate_process_pages()) of
        {Slug, RelPath, _Title} -> RelPath;
        false -> undefined
    end.

boilerplate_process_pages() ->
    Base = <<"docs/devices/compute-and-processes/process-at-1-0/">>,
    [
        {<<"overview">>, <<Base/binary, "01-intro-to-process@1.0.md">>, <<"Process Overview">>},
        {<<"state-and-reads">>, <<Base/binary, "02-state-and-reads.md">>, <<"State And Reads">>},
        {<<"builder-templates">>, <<Base/binary, "03-builder-templates.md">>, <<"Builder Templates">>},
        {<<"ao-connect-mainnet">>, <<Base/binary, "04-aoconnect-mainnet.md">>, <<"AO Connect Mainnet">>},
        {<<"aos-lua-reference">>, <<Base/binary, "05-aos-lua-reference.md">>, <<"AOS Lua Reference">>},
        {<<"migration-to-hyperbeam">>, <<Base/binary, "06-migration-to-hyperbeam.md">>, <<"Migration To HyperBEAM">>},
        {<<"legacynet-appendix">>, <<Base/binary, "07-legacynet-appendix.md">>, <<"Legacynet Appendix">>}
    ].

extract_markdown_section(Markdown, SectionTitle) ->
    Lines = binary:split(Markdown, <<"\n">>, [global]),
    extract_markdown_section_lines(Lines, SectionTitle).

extract_markdown_section_lines([], _SectionTitle) ->
    false;
extract_markdown_section_lines([Line | Rest], SectionTitle) ->
    case heading(trim(Line)) of
        {Level, Text} when Text =:= SectionTitle ->
            {SectionLines, _After} = take_section_body(Rest, Level, []),
            {ok,
                iolist_to_binary(
                    lists:join(<<"\n">>, [<<"# ", SectionTitle/binary>> | SectionLines])
                )};
        _ ->
            extract_markdown_section_lines(Rest, SectionTitle)
    end.

take_section_body([Line | Rest] = All, Level, Acc) ->
    case heading(trim(Line)) of
        {NextLevel, _Text} when NextLevel =< Level ->
            {lists:reverse(Acc), All};
        _ ->
            take_section_body(Rest, Level, [Line | Acc])
    end;
take_section_body([], _Level, Acc) ->
    {lists:reverse(Acc), []}.

device_docs_path(RelPath) ->
    hb_util:bin(filename:join([device_docs_root(), binary_to_list(RelPath)])).

device_docs_root() ->
    case os:getenv("HB_DEVICE_DOCS_ROOT") of
        false -> packaged_device_docs_root();
        "" -> packaged_device_docs_root();
        Root -> Root
    end.

packaged_device_docs_root() ->
    case code:priv_dir(hb) of
        {error, _Reason} ->
            filename:join(["priv" | ?PACKAGED_DEVICE_DOCS_ROOT]);
        PrivDir ->
            filename:join([PrivDir | ?PACKAGED_DEVICE_DOCS_ROOT])
    end.

command_preview(Text) ->
    OneLine0 = binary:replace(Text, <<"\r">>, <<" ">>, [global]),
    OneLine = binary:replace(OneLine0, <<"\n">>, <<" ">>, [global]),
    case byte_size(OneLine) > 1200 of
        true -> <<(binary:part(OneLine, 0, 1200))/binary, "...">>;
        false -> OneLine
    end.

render_node_html(Data) ->
    Devices = maps:get(<<"devices">>, Data),
    Renderer = maps:get(<<"renderer">>, Data, cookbook_renderer()),
    Boilerplate = maps:get(<<"boilerplate">>, Data, boilerplate_index()),
    Content =
        [
            <<"<p class=\"eyebrow\">Node</p><h1>HyperBEAM Docs</h1><p>">>,
            esc(maps:get(<<"summary">>, Data)),
            <<"</p><p class=\"hb-docs-renderer-note\">Rendered by <a href=\"">>,
            esc(maps:get(<<"node-renderer">>, Renderer)),
            <<"\">~">>, esc(maps:get(<<"device">>, Renderer)), <<"</a>.</p>">>,
            <<"<h2>Guides</h2>">>,
            boilerplate_structured_index(Boilerplate),
            <<"<h2 id=\"devices\">Devices</h2><div class=\"hb-docs-card-grid\">">>,
            [device_row(Device) || Device <- Devices],
            <<"</div><h2>Concepts</h2>">>,
            concept_rows(maps:get(<<"concepts">>, Data))
        ],
    docs_page_html(<<"HyperBEAM Node Info">>, <<"/docs">>, node_sidebar(Devices, <<"/docs">>), Content).

render_device_html(Data) ->
    Device = maps:get(<<"device">>, Data),
    DeviceID = maps:get(<<"id">>, Device),
    Schema = maps:get(<<"schema">>, Data),
    SchemaOrder = maps:get(<<"schema-order">>, Data, []),
    Recipes = maps:get(<<"recipes">>, Data),
    Spec = maps:get(<<"spec">>, Data),
    Content =
        [
            <<"<p class=\"eyebrow\">Device</p><h1>~">>,
            esc(maps:get(<<"id">>, Device)),
            <<"</h1>">>,
            device_summary_paragraph(Data),
            schema_source_note(Data),
            <<"<h2 id=\"schema\">Schema</h2>">>,
            schema_table(DeviceID, Schema, SchemaOrder),
            render_spec_section(DeviceID, Spec),
            <<"<h2 id=\"recipes\">Recipes</h2><div class=\"hb-docs-card-grid\">">>,
            recipe_nav(DeviceID, Recipes),
            <<"</div>">>
        ],
    docs_page_html(
        <<"HyperBEAM Device Info">>,
        device_info_path(DeviceID),
        device_sidebar(Data, device_info_path(DeviceID)),
        Content
    ).

render_schema_index_html(Data) ->
    Device = maps:get(<<"device">>, Data),
    DeviceID = maps:get(<<"id">>, Device),
    Schema = maps:get(<<"schema">>, Data, #{}),
    SchemaOrder = maps:get(<<"schema-order">>, Data, []),
    Content =
        [
            <<"<p class=\"eyebrow\">Schema</p><h1>~">>, esc(DeviceID),
            <<" schema</h1>">>,
            schema_source_note(Data),
            schema_table(DeviceID, Schema, SchemaOrder)
        ],
    docs_page_html(
        <<"HyperBEAM Schema">>,
        device_schema_path(DeviceID),
        device_sidebar(Data, device_schema_path(DeviceID)),
        Content
    ).

device_summary_paragraph(Data) ->
    case trim(maps:get(<<"summary">>, Data, <<>>)) of
        <<>> -> [];
        Summary -> [<<"<p>">>, esc(Summary), <<"</p>">>]
    end.

render_schema_key_html(Payload) ->
    Data = maps:get(<<"device-data">>, Payload),
    Device = maps:get(<<"device">>, Payload),
    DeviceID = maps:get(<<"id">>, Device),
    Key = maps:get(<<"key">>, Payload),
    KeySchema = maps:get(<<"schema">>, Payload),
    Params = maps:get(<<"parameters">>, KeySchema, #{}),
    Content =
        [
            <<"<p class=\"eyebrow\">Schema Key</p><h1>~">>, esc(DeviceID),
            <<" / ">>, esc(Key), <<"</h1><p>">>,
            esc(maps:get(<<"description">>, KeySchema, <<>>)),
            <<"</p><h2>Parameters</h2>">>,
            params_table(DeviceID, Key, Params)
        ],
    docs_page_html(
        <<"HyperBEAM Schema Key">>,
        device_schema_key_path(DeviceID, Key),
        device_sidebar(Data, device_schema_key_path(DeviceID, Key)),
        Content
    ).

render_schema_parameter_html(Payload) ->
    Data = maps:get(<<"device-data">>, Payload),
    Device = maps:get(<<"device">>, Payload),
    DeviceID = maps:get(<<"id">>, Device),
    Key = maps:get(<<"key">>, Payload),
    Param = maps:get(<<"parameter">>, Payload),
    ParamSchema = maps:get(<<"schema">>, Payload),
    Content =
        [
            <<"<p class=\"eyebrow\">Schema Parameter</p><h1>~">>, esc(DeviceID),
            <<" / ">>, esc(Key), <<" / ">>, esc(Param), <<"</h1>">>,
            <<"<table><tbody>">>,
            <<"<tr><th>Name</th><td><code>">>, esc(Param), <<"</code></td></tr>">>,
            <<"<tr><th>Required</th><td>">>,
            case maps:get(<<"required">>, ParamSchema, false) of
                true -> <<"yes">>;
                false -> <<"no">>
            end,
            <<"</td></tr><tr><th>Type</th><td>">>,
            esc(maps:get(<<"type">>, ParamSchema, <<>>)),
            <<"</td></tr><tr><th>Description</th><td>">>,
            esc(maps:get(<<"description">>, ParamSchema, <<>>)),
            <<"</td></tr><tr><th>Example</th><td><code>">>,
            esc(maps:get(<<"example">>, ParamSchema, <<>>)),
            <<"</code></td></tr></tbody></table>">>
        ],
    docs_page_html(
        <<"HyperBEAM Schema Parameter">>,
        device_schema_key_path(DeviceID, Key),
        device_sidebar(Data, device_schema_key_path(DeviceID, Key)),
        Content
    ).

render_spec_html(Data) ->
    Device = maps:get(<<"device">>, Data),
    DeviceID = maps:get(<<"id">>, Device),
    Content =
        [
            <<"<p class=\"eyebrow\">Specification</p><h1>~">>, esc(DeviceID),
            <<" spec</h1>">>,
            render_spec_body(maps:get(<<"spec">>, Data, #{}))
        ],
    docs_page_html(
        <<"HyperBEAM Spec">>,
        device_spec_path(DeviceID),
        device_sidebar(Data, device_spec_path(DeviceID)),
        Content
    ).

render_spec_section_page_html(Payload) ->
    Data = maps:get(<<"device-data">>, Payload),
    Device = maps:get(<<"device">>, Payload),
    DeviceID = maps:get(<<"id">>, Device),
    SectionId = maps:get(<<"section-id">>, Payload),
    Title = maps:get(<<"section-title">>, Payload),
    Spec = maps:get(<<"spec">>, Payload),
    ActivePath = device_spec_section_path(DeviceID, SectionId),
    Content =
        [
            <<"<p class=\"eyebrow\">Specification</p><h1>">>, esc(DeviceID),
            <<" / ">>, esc(spec_section_nav_label(Title)), <<"</h1>">>,
            spec_tx_link_paragraph(Spec),
            render_markdown_with_heading_ids(spec_section_markdown(Spec, SectionId), #{
                <<"strip-numbered-headings">> => true
            })
        ],
    docs_page_html(<<"HyperBEAM Spec">>, ActivePath, device_sidebar(Data, ActivePath), Content).

render_recipes_html(Data) ->
    Device = maps:get(<<"device">>, Data),
    DeviceID = maps:get(<<"id">>, Device),
    Recipes = maps:get(<<"recipes">>, Data, #{}),
    Content =
        [
            <<"<p class=\"eyebrow\">Recipes</p><h1>~">>, esc(DeviceID),
            <<" recipes</h1><div class=\"hb-docs-card-grid\">">>,
            recipe_nav(DeviceID, Recipes),
            <<"</div>">>
        ],
    docs_page_html(
        <<"HyperBEAM Recipes">>,
        device_recipes_path(DeviceID),
        device_sidebar(Data, device_recipes_path(DeviceID)),
        Content
    ).

render_recipe_html(Payload) ->
    Data = maps:get(<<"device-data">>, Payload),
    Device = maps:get(<<"device">>, Payload),
    DeviceID = maps:get(<<"id">>, Device),
    Slug = maps:get(<<"slug">>, Payload),
    Recipe = maps:get(<<"recipe">>, Payload),
    ActivePath = device_recipe_path(DeviceID, Slug),
    Content =
        [
            <<"<p class=\"eyebrow\">Recipe</p><h1>">>, esc(DeviceID),
            <<" / ">>, esc(maps:get(<<"title">>, Recipe, Slug)), <<"</h1>">>,
            on_chain_link_paragraph(Recipe, <<"View recipe transaction">>),
            render_markdown(
                drop_first_h1(recipe_markdown(Recipe)),
                #{ <<"source-relative">> => maps:get(<<"source-relative">>, Recipe, undefined) }
            )
        ],
    docs_page_html(<<"HyperBEAM Recipe">>, ActivePath, device_sidebar(Data, ActivePath), Content).

render_implementations_html(Data) ->
    Device = maps:get(<<"device">>, Data),
    DeviceID = maps:get(<<"id">>, Device),
    Implementations = maps:get(<<"implementations">>, Data, []),
    Content =
        [
            <<"<p class=\"eyebrow\">Implementations</p><h1>~">>, esc(DeviceID),
            <<" implementations</h1><table><thead><tr><th>Name</th><th>Module</th>"
                "<th>Source</th><th>Status</th></tr></thead><tbody>">>,
            [
                [
                    <<"<tr><td>">>, esc(maps:get(<<"name">>, Impl, <<>>)),
                    <<"</td><td><code>">>, esc(maps:get(<<"module">>, Impl, <<>>)),
                    <<"</code></td><td>">>, implementation_source_cell(Impl),
                    <<"</td><td>">>, esc(maps:get(<<"status">>, Impl, <<>>)),
                    <<"</td></tr>">>
                ]
            || Impl <- Implementations
            ],
            <<"</tbody></table>">>
        ],
    docs_page_html(
        <<"HyperBEAM Implementations">>,
        device_implementations_path(DeviceID),
        device_sidebar(Data, device_implementations_path(DeviceID)),
        Content
    ).

render_node_component_html(Title, ActivePath, Data) ->
    Devices = maps:get(<<"devices">>, Data, []),
    Content =
        [
            <<"<p class=\"eyebrow\">Node</p><h1>">>, esc(Title),
            <<" index</h1><div class=\"hb-docs-device-grid\">">>,
            [device_row(Device) || Device <- Devices],
            <<"</div>">>
        ],
    docs_page_html(
        <<"HyperBEAM Node Index">>, ActivePath, node_sidebar_from_component(Devices, ActivePath), Content
    ).

render_node_boilerplate_html(Data) ->
    Content =
        [
            <<"<p class=\"eyebrow\">Node</p><h1>Guides</h1><p>">>,
            esc(maps:get(<<"summary">>, Data, <<>>)),
            <<"</p>">>,
            boilerplate_section_cards(Data, h2)
        ],
    docs_page_html(
        <<"HyperBEAM Guides">>, <<"/docs/guides">>, node_sidebar([], <<"/docs/guides">>), Content
    ).

render_node_boilerplate_page_html(Data) ->
    Markdown = maps:get(<<"markdown">>, Data, <<>>),
    ActivePath = maps:get(<<"href">>, Data, <<"/docs/guides">>),
    Content =
        [
            <<"<p class=\"eyebrow\">Guide</p><h1>">>,
            esc(maps:get(<<"title">>, Data, <<>>)),
            <<"</h1>">>,
            render_markdown(
                drop_first_h1(Markdown),
                #{ <<"source-relative">> => maps:get(<<"source-relative">>, Data, undefined) }
            )
        ],
    docs_page_html(<<"HyperBEAM Guide">>, ActivePath, node_sidebar([], ActivePath), Content).

render_node_concepts_html(Data) ->
    Concepts = maps:get(<<"concepts">>, Data, #{}),
    Content =
        [
            <<"<p class=\"eyebrow\">Node</p><h1>Concepts</h1>">>,
            concept_rows(Concepts)
        ],
    docs_page_html(
        <<"HyperBEAM Concepts">>, <<"/docs/concepts">>, node_sidebar([], <<"/docs/concepts">>), Content
    ).

render_node_concept_html(Data) ->
    Concept = maps:get(<<"concept">>, Data, <<>>),
    ActivePath = <<"/docs/concepts/", Concept/binary>>,
    Content =
        [
            <<"<p class=\"eyebrow\">Concept</p><h1>">>, esc(Concept),
            <<"</h1><p>">>, esc(maps:get(<<"description">>, Data, <<>>)), <<"</p>">>
        ],
    docs_page_html(<<"HyperBEAM Concept">>, ActivePath, node_sidebar([], ActivePath), Content).

render_unsupported_device_html(Device) ->
    ActivePath = device_info_path(Device),
    Content =
        [
            <<"<p class=\"eyebrow\">Device</p><h1>">>,
            esc(device_marked_id(Device)),
            <<" docs not available</h1><p>No on-weave spec-loaded documentation is "
                "available for this device.</p><p><a href=\"/docs\">View All Node Info</a></p>">>
        ],
    docs_page_html(<<"HyperBEAM Device Docs Not Available">>, ActivePath, node_sidebar([], ActivePath), Content).

docs_page_html(Title, ActivePath, Sidebar, Content) ->
    iolist_to_binary([
        html_head(Title),
        <<"<body class=\"ready sticky hb-docs-protocol close\" data-active-path=\"">>,
        esc(ActivePath),
        <<"\">">>,
        docs_site_header(),
        docs_mobile_nav_drawer(),
        <<"<main>">>,
        docs_sidebar(Sidebar),
        <<"<section class=\"content\"><article class=\"markdown-section\" id=\"main\">">>,
        Content,
        <<"</article></section></main>">>,
        docs_shell_assets(),
        <<"</body></html>">>
    ]).

docs_site_header() ->
    <<
        "<header class=\"site-header\" id=\"site-header\">"
        "<div class=\"site-header-top\">"
        "<div class=\"site-header-start\">"
        "<a class=\"site-brand site-header-home\" href=\"/docs\">View All Node Info</a>"
        "</div>"
        "<div class=\"site-header-actions\">"
        "<button type=\"button\" class=\"mobile-menu-toggle\" id=\"mobile-menu-toggle\" "
        "aria-label=\"Open sections menu\" aria-expanded=\"false\" aria-controls=\"mobile-nav-panel\">"
        "<svg viewBox=\"0 0 256 256\" fill=\"currentColor\" aria-hidden=\"true\">"
        "<path d=\"M40,88a8,8,0,0,1,8-8H208a8,8,0,0,1,0,16H48A8,8,0,0,1,40,88Zm0,80a8,8,0,0,1,8-8H168a8,8,0,0,1,0,16H48A8,8,0,0,1,40,168Z\"/>"
        "</svg>"
        "</button>"
        "</div>"
        "</div>"
        "</header>"
    >>.

docs_mobile_nav_drawer() ->
    <<
        "<div class=\"mobile-nav-drawer\" id=\"mobile-nav-drawer\" aria-hidden=\"true\">"
        "<div class=\"mobile-nav-backdrop\" data-mobile-nav-close></div>"
        "<nav class=\"mobile-nav-panel\" id=\"mobile-nav-panel\" aria-label=\"Documentation sections\">"
        "<div class=\"mobile-nav-panel-header\">"
        "<span class=\"mobile-nav-panel-title\">Sections</span>"
        "<button type=\"button\" class=\"mobile-nav-close\" data-mobile-nav-close "
        "aria-label=\"Close menu\">"
        "<svg viewBox=\"0 0 256 256\" fill=\"currentColor\" aria-hidden=\"true\">"
        "<path d=\"M205.66,194.34a8,8,0,0,1-11.32,11.32L128,139.31,61.66,205.66a8,8,0,0,1-11.32-11.32L116.69,128,50.34,61.66A8,8,0,0,1,61.66,50.34L128,116.69l66.34-66.35a8,8,0,0,1,11.32,11.32L139.31,128Z\"/>"
        "</svg>"
        "</button>"
        "</div>"
        "<div class=\"mobile-nav-panel-body\" id=\"mobile-nav-body\">"
        "<div class=\"mobile-nav-tabs\" id=\"mobile-nav-tabs\">"
        "<a class=\"mobile-nav-home\" href=\"/docs\">View All Node Info</a>"
        "</div>"
        "<div class=\"mobile-nav-search\" id=\"mobile-nav-search\">"
        "<div class=\"mobile-nav-search-wrap\">"
        "<span class=\"mobile-nav-search-icon\" aria-hidden=\"true\">"
        "<svg viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" "
        "stroke-width=\"1.5\" stroke-linecap=\"round\" stroke-linejoin=\"round\">"
        "<path d=\"m21 21-4.34-4.34\"/>"
        "<circle cx=\"11\" cy=\"11\" r=\"8\"/>"
        "</svg>"
        "</span>"
        "<input type=\"search\" id=\"mobile-nav-search-input\" class=\"mobile-nav-search-input\" "
        "placeholder=\"Search docs...\" autocomplete=\"off\" aria-label=\"Search documentation\">"
        "</div>"
        "</div>"
        "<div class=\"mobile-nav-list\" id=\"mobile-nav-list\"></div>"
        "</div>"
        "</nav>"
        "</div>"
    >>.

html_head(Title) ->
    [
        <<"<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">"
            "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
            "<title>">>,
        esc(Title),
        <<"</title>"
            "<link rel=\"preload\" href=\"/docs/assets/fonts/dm-sans-400.woff2\" "
            "as=\"font\" type=\"font/woff2\" crossorigin>"
            "<link rel=\"preload\" href=\"/docs/assets/fonts/dm-sans-500.woff2\" "
            "as=\"font\" type=\"font/woff2\" crossorigin>"
            "<link rel=\"preload\" href=\"/docs/assets/fonts/dm-sans-600.woff2\" "
            "as=\"font\" type=\"font/woff2\" crossorigin>"
            "<link rel=\"stylesheet\" href=\"/docs/assets/fonts.css\">"
            "<link rel=\"stylesheet\" href=\"/docs/assets/docsify-vue.css\">"
            "<link rel=\"stylesheet\" href=\"/docs/assets/prism.css\">"
            "<link rel=\"stylesheet\" href=\"/docs/assets/site.css\">"
            "<style>">>,
        hb_docs_overrides_css(),
        <<"</style></head>">>
    ].

hb_docs_overrides_css() ->
    <<"
body.hb-docs-protocol {
  background: var(--bg);
  color: var(--text);
  --text-page-title: clamp(1.28125rem, 0.7rem + 2.3vw, 1.875rem);
  --text-section-title: clamp(1.046875rem, 0.605rem + 1.65vw, 1.3125rem);
  --text-subheading: clamp(0.9375rem, 1.2vw, 1.0625rem);
  --text-lead: clamp(0.90625rem, 1.05vw, 1rem);
  --text-body: clamp(0.8125rem, 0.925vw, 0.875rem);
  --text-ui: clamp(0.75rem, 0.875vw, 0.8125rem);
  --text-caption: clamp(0.6875rem, 0.8vw, 0.75rem);
}
body.hb-docs-protocol .site-header { display: none; }
body.hb-docs-protocol .sidebar { top: 0 !important; }
body.hb-docs-protocol .sidebar > h1 { display: none; }
body.hb-docs-protocol .content {
  padding-top: 0 !important;
}
@media (max-width: 1200px) {
  body.hb-docs-protocol .content {
    right: 0 !important;
  }
}
@media (min-width: 1201px) {
  body.hb-docs-protocol .content {
    right: 0 !important;
  }
  body.hb-docs-protocol.page-toc-active .content {
    right: calc(var(--toc-width) + var(--layout-inline-padding)) !important;
  }
  body.hb-docs-protocol.page-toc-active .page-toc {
    top: 28px;
    max-height: calc(100vh - 40px);
  }
}
body.hb-docs-protocol .content .markdown-section,
body.hb-docs-protocol .markdown-section {
  max-width: var(--content-max) !important;
  margin: 0 auto !important;
  width: auto !important;
  box-sizing: border-box;
}
body.hb-docs-protocol .content .markdown-section { padding-top: 36px !important; }
body.hb-docs-protocol .markdown-section table {
  width: 100%;
  max-width: 100%;
}
body.hb-docs-protocol .markdown-section h3 {
  font-size: 1.025rem !important;
}
body.hb-docs-protocol .page-toc-links a[data-level='h2'] {
  font-size: var(--text-body);
}
body.hb-docs-protocol .page-toc-links a[data-level='h3'] {
  font-size: var(--text-caption);
}
body.hb-docs-protocol .site-header-nav-zone { display: none; }
body.hb-docs-protocol .sidebar-nav > ul > li.sidebar-flat-links > ul > li > a,
body.hb-docs-protocol .sidebar-nav > ul > li > ul > li:first-child > a {
  padding-left: var(--sidebar-link-pad-x) !important;
  padding-right: var(--sidebar-link-pad-x) !important;
  color: var(--sidebar-link-color) !important;
  opacity: 1;
}
body.hb-docs-protocol .sidebar-nav > ul > li.sidebar-flat-links > ul > li > a:hover,
body.hb-docs-protocol .sidebar-nav > ul > li > ul > li:first-child > a:hover {
  color: var(--sidebar-link-hover-color) !important;
}
body.hb-docs-protocol .sidebar-nav > ul > li.sidebar-flat-links > ul > li.active > a,
body.hb-docs-protocol .sidebar-nav > ul > li.sidebar-flat-links > ul > li.active > a:hover,
body.hb-docs-protocol .sidebar-nav > ul > li > ul > li:first-child.active > a,
body.hb-docs-protocol .sidebar-nav > ul > li > ul > li:first-child.active > a:hover {
  color: var(--sidebar-link-active-color) !important;
  background: var(--sidebar-link-active-bg) !important;
  font-weight: 600 !important;
  opacity: 1;
  padding-left: var(--sidebar-link-pad-x) !important;
  padding-right: var(--sidebar-link-pad-x) !important;
}
body.hb-docs-protocol .sidebar-nav > ul > li.sidebar-flat-links > ul > li:not(:first-child) > a,
body.hb-docs-protocol .sidebar-nav > ul > li.sidebar-flat-links > ul > li:not(:first-child) > a:hover,
body.hb-docs-protocol .sidebar-nav > ul > li.sidebar-flat-links > ul > li:not(:first-child).active > a,
body.hb-docs-protocol .sidebar-nav > ul > li.sidebar-flat-links > ul > li:not(:first-child).active > a:hover {
  padding-left: var(--sidebar-link-pad-x) !important;
  padding-right: var(--sidebar-link-pad-x) !important;
  color: var(--sidebar-link-color) !important;
  opacity: 1;
}
body.hb-docs-protocol .sidebar-nav > ul > li.sidebar-flat-links > ul > li:not(:first-child).active > a,
body.hb-docs-protocol .sidebar-nav > ul > li.sidebar-flat-links > ul > li:not(:first-child).active > a:hover {
  color: var(--sidebar-link-active-color) !important;
  background: var(--sidebar-link-active-bg) !important;
  font-weight: 600 !important;
  opacity: 1;
}
body.hb-docs-protocol .sidebar-nav > ul > li > ul > li:not(:first-child) > a {
  color: var(--sidebar-nested-link-color) !important;
  opacity: 0.72;
}
body.hb-docs-protocol .sidebar-nav > ul > li > ul > li:not(:first-child) > a:hover {
  color: var(--sidebar-link-hover-color) !important;
  opacity: 0.88;
}
body.hb-docs-protocol .sidebar-nav > ul > li > ul > li:not(:first-child).active > a,
body.hb-docs-protocol .sidebar-nav > ul > li > ul > li:not(:first-child).active > a:hover {
  color: var(--sidebar-nested-link-color) !important;
  background: var(--sidebar-link-active-bg) !important;
  font-weight: 500 !important;
  opacity: 0.9;
}
body.hb-docs-protocol .sidebar-nav > ul > li > ul > li > ul a {
  color: var(--sidebar-nested-link-color) !important;
  opacity: 0.58;
}
body.hb-docs-protocol .sidebar-nav > ul > li > ul > li > ul li.active > a,
body.hb-docs-protocol .sidebar-nav > ul > li > ul > li > ul li.active > a:hover {
  color: var(--sidebar-nested-link-color) !important;
  background: var(--sidebar-link-active-bg) !important;
  font-weight: 500 !important;
  opacity: 0.78;
}
body.hb-docs-protocol .sidebar-nav > ul > li.sidebar-viewing-context {
  margin: 0 0 10px !important;
}
body.hb-docs-protocol .sidebar-viewing-context {
  display: flex;
  flex-direction: column;
  gap: 0;
  padding: 2px 0 14px;
  border-bottom: 1px solid var(--border);
}
body.hb-docs-protocol .sidebar-viewing-context .eyebrow {
  margin: 0 !important;
  padding: 0 !important;
  color: var(--text-tertiary) !important;
  font-size: var(--text-caption) !important;
  font-weight: 400 !important;
  line-height: 1.15;
  letter-spacing: 0 !important;
  text-transform: none !important;
}
body.hb-docs-protocol .sidebar-viewing-context > a {
  padding: 0 !important;
  text-transform: none !important;
}
body.hb-docs-protocol .sidebar-viewing-device {
  display: block;
  padding: 0 !important;
  color: var(--text) !important;
  font-size: var(--text-body) !important;
  font-weight: 600 !important;
  line-height: 1.25;
  letter-spacing: -0.02em;
  text-decoration: none !important;
  transition: opacity 100ms ease;
}
body.hb-docs-protocol .sidebar-viewing-context > a,
body.hb-docs-protocol .sidebar-viewing-context.active > a,
body.hb-docs-protocol li.sidebar-viewing-context.active > a,
body.hb-docs-protocol .sidebar-viewing-context > a.is-active,
body.hb-docs-protocol .sidebar-viewing-context > a.is-active:hover,
body.hb-docs-protocol li.sidebar-viewing-context.active > a:hover {
  background: transparent !important;
  border: none !important;
}
body.hb-docs-protocol .sidebar-viewing-device:hover {
  opacity: 0.72;
}
body.hb-docs-protocol .sidebar-viewing-device.is-active {
  color: var(--text) !important;
}
body.hb-docs-protocol .sidebar-viewing-back {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  margin-top: 0;
  padding: 0 !important;
  color: var(--sidebar-link-color) !important;
  font-size: var(--text-ui) !important;
  font-weight: 400 !important;
  line-height: 1.25;
  letter-spacing: -0.02em;
  text-decoration: none !important;
  transition: opacity 100ms ease, color 100ms ease;
}
body.hb-docs-protocol .sidebar-viewing-back-icon {
  flex: 0 0 auto;
  width: 13px;
  height: 13px;
  opacity: 0.62;
}
body.hb-docs-protocol .sidebar-viewing-back-icon svg {
  display: block;
  width: 100%;
  height: 100%;
}
body.hb-docs-protocol .sidebar-viewing-back:hover {
  color: var(--sidebar-link-hover-color) !important;
  opacity: 0.72;
}
body.hb-docs-protocol .sidebar-viewing-device + .sidebar-viewing-back {
  margin-top: 16px;
}
body.hb-docs-protocol .sidebar-viewing-back + .sidebar-viewing-back {
  margin-top: 6px;
}
body.hb-docs-protocol .sidebar-viewing-back.is-active {
  color: var(--sidebar-link-active-color) !important;
}
.hb-docs-guide-section {
  margin: 0 0 2rem;
}
.hb-docs-guide-section:last-child {
  margin-bottom: 0;
}
.hb-docs-guide-section > h2,
.hb-docs-guide-section > h3 {
  margin: 0 0 0.75rem;
}
.hb-docs-guide-section .hb-docs-card-grid {
  margin-top: 0;
}
.hb-docs-section-header {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 12px;
  margin: 0 0 0.75rem;
}
.hb-docs-section-header h2 {
  margin: 0;
}
.hb-docs-section-link {
  flex: 0 0 auto;
  font-size: var(--text-caption);
  font-weight: 500;
  color: var(--text-secondary) !important;
  text-decoration: none !important;
}
.hb-docs-section-link:hover {
  color: var(--text) !important;
}
.markdown-section .theme-invert-video {
  width: 100%;
  height: auto;
  display: block;
  margin: 0 0 1.5rem;
  background: var(--bg-muted);
}
@media (prefers-color-scheme: dark) {
  .markdown-section .theme-invert-video {
    filter: invert(1) hue-rotate(180deg);
    background: #000;
  }
}
.markdown-section .core-concepts-flex {
  display: flex;
  align-items: flex-start;
  gap: 2rem;
  width: 100%;
  margin: 1.75rem 0 2rem;
}
.markdown-section .core-concepts-fig {
  flex: 1 0 100px;
  width: 100px;
  max-width: 160px !important;
  height: auto;
  margin: 0.25rem 0 0;
}
.markdown-section .core-concepts-column {
  display: flex;
  flex: 1 1 auto;
  min-width: 0;
  flex-direction: column;
}
.markdown-section .core-concepts-column p {
  margin: 0 0 1rem;
}
.markdown-section .core-concept-header-messages,
.markdown-section .core-concept-header-devices,
.markdown-section .core-concept-header-paths {
  margin: 0 0 0.25rem;
  line-height: 1.25;
}
.markdown-section .core-concept-subtitle {
  margin: 0 0 1rem;
  color: var(--text-tertiary);
  font-size: var(--text-caption);
  line-height: 1.3;
}
.markdown-section .core-concept-copy {
  line-height: 1.65;
}
.hb-docs-device-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(min(100%, 260px), 1fr));
  gap: 20px;
  margin: 0 0 2rem;
}
.markdown-section a.hb-docs-device-card,
.markdown-section a.hb-docs-device-card:hover,
.markdown-section a.hb-docs-device-card strong,
.markdown-section a.hb-docs-device-card span {
  text-decoration: none !important;
}
.hb-docs-device-card {
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding: 0;
  border: none;
  border-radius: 0;
  background: transparent;
  color: var(--text) !important;
  text-decoration: none !important;
}
.hb-docs-device-card:hover {
  background: transparent;
}
.hb-docs-device-tint-0 {
  --device-card-accent: #c45c68;
}
.hb-docs-device-tint-1 {
  --device-card-accent: #2a7db5;
}
.hb-docs-device-tint-2 {
  --device-card-accent: #d46a42;
}
.hb-docs-device-tint-3 {
  --device-card-accent: #4a56b8;
}
.hb-docs-device-tint-4 {
  --device-card-accent: #2d8a5c;
}
.hb-docs-device-tint-5 {
  --device-card-accent: #6b8f1a;
}
.hb-docs-device-tint-6 {
  --device-card-accent: #0072c8;
}
.hb-docs-device-tint-7 {
  --device-card-accent: #c75a38;
}
.hb-docs-device-card-body {
  display: flex;
  flex-direction: column;
  gap: 6px;
  min-height: 168px;
}
.hb-docs-device-card-title-row {
  display: flex;
  align-items: baseline;
  flex-wrap: wrap;
  gap: 8px;
}
.hb-docs-device-card-title {
  font-size: var(--text-ui);
  font-weight: 700;
  color: var(--text);
}
.hb-docs-device-card-id {
  font-size: var(--text-ui);
  font-weight: 600;
  color: var(--device-card-accent, var(--text-secondary));
  letter-spacing: -0.02em;
}
.hb-docs-device-card-desc {
  font-size: var(--text-caption);
  line-height: 1.45;
  color: var(--text-secondary);
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}
.hb-docs-reference-list {
  margin: 0;
}
.hb-docs-reference-section > h2 {
  margin: 0 0 0.75rem;
}
.markdown-section .hb-docs-reference-item {
  margin: 0 0 1rem;
  font-size: inherit;
  line-height: inherit;
}
.markdown-section .hb-docs-reference-item:last-child {
  margin-bottom: 0;
}
.markdown-section .hb-docs-reference-item a,
.markdown-section .hb-docs-reference-item a:hover,
.markdown-section .hb-docs-reference-item a strong {
  text-decoration: none !important;
  color: var(--text);
  font-size: inherit;
}
.markdown-section .hb-docs-reference-item a:hover {
  opacity: 0.72;
}
.hb-docs-guide-list-desc {
  font-size: inherit;
  line-height: inherit;
  color: var(--text-secondary);
  font-weight: 400;
  opacity: 0.8;
}
.hb-docs-card-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 12px;
  margin: 1rem 0 1.5rem;
}
@media (max-width: 640px) {
  .hb-docs-card-grid {
    grid-template-columns: 1fr;
  }
}
.markdown-section a.hb-docs-card,
.markdown-section a.hb-docs-card:hover,
.markdown-section a.hb-docs-card strong,
.markdown-section a.hb-docs-card span,
.markdown-section a.hb-docs-card small,
.markdown-section a.hb-docs-recipe-card .hb-docs-recipe-card-cta {
  text-decoration: none !important;
}
.hb-docs-card {
  display: flex;
  flex-direction: column;
  gap: 0;
  min-height: 168px;
  height: 100%;
  padding: 14px;
  border: 1px solid var(--border);
  border-radius: 8px;
  background: var(--bg);
  color: var(--text) !important;
  text-decoration: none !important;
}
.hb-docs-card:hover { background: var(--bg-hover); }
.hb-docs-card span,
.hb-docs-card small { color: var(--text-secondary); }
.hb-docs-recipe-card {
  gap: 8px;
}
.hb-docs-recipe-card-header {
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
}
.hb-docs-recipe-card-icon {
  flex: 0 0 20px;
  width: 20px;
  height: 20px;
  color: var(--text-secondary);
  line-height: 0;
}
.hb-docs-recipe-card-icon svg {
  display: block;
  width: 100%;
  height: 100%;
}
.hb-docs-recipe-card-title {
  min-width: 0;
  line-height: 1.3;
}
.hb-docs-recipe-card-body {
  display: flex;
  flex-direction: column;
  flex: 1 1 auto;
  gap: 8px;
  min-height: 0;
}
.hb-docs-recipe-card-desc {
  flex: 0 1 auto;
  font-size: var(--text-caption);
  line-height: 1.45;
  color: var(--text-secondary);
}
.hb-docs-recipe-card-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-top: auto;
  width: 100%;
}
.hb-docs-recipe-card-cta {
  flex: 0 0 auto;
  font-size: var(--text-caption);
  font-weight: 500;
  color: var(--text-secondary);
}
.hb-docs-recipe-card-meta {
  flex: 0 0 auto;
  margin-left: auto;
  font-size: var(--text-caption);
  color: var(--text-tertiary);
  text-align: right;
  white-space: nowrap;
}
.hb-docs-chain-link-row {
  margin: 0.5rem 0 1rem;
}
.markdown-section a.hb-docs-chain-link,
.markdown-section a.hb-docs-chain-link:hover,
.markdown-section a.hb-docs-chain-link span {
  text-decoration: none !important;
}
.hb-docs-chain-link {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  min-height: 24px;
  padding: 3px 9px;
  border: 1px solid var(--border);
  border-radius: 999px;
  background: var(--bg-muted);
  color: var(--text-secondary) !important;
  font-size: var(--text-caption);
  font-weight: 600;
  line-height: 1.2;
}
.hb-docs-chain-link:hover {
  background: var(--bg-hover);
  color: var(--text) !important;
}
.hb-docs-chain-link-icon {
  flex: 0 0 14px;
  width: 14px;
  height: 14px;
  line-height: 0;
}
.hb-docs-chain-link-icon svg {
  display: block;
  width: 100%;
  height: 100%;
}
.hb-docs-guide-index {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(min(100%, 260px), 1fr));
  column-gap: 28px;
  row-gap: 22px;
  margin: 1rem 0 2rem;
}
.hb-docs-guide-group {
  min-width: 0;
  padding-top: 12px;
  border-top: 1px solid var(--border);
}
.hb-docs-guide-group h3 {
  margin: 0 0 8px;
  font-size: 1rem;
  line-height: 1.3;
}
.hb-docs-guide-group ul {
  display: grid;
  gap: 6px;
  margin: 0;
  padding: 0;
  list-style: none;
}
.hb-docs-guide-group li { margin: 0; }
.hb-docs-guide-group a {
  color: var(--text) !important;
  font-weight: 500;
  text-decoration: none !important;
}
.hb-docs-guide-group a:hover { text-decoration: underline !important; }
		.hb-docs-renderer-note {
		  color: var(--text-secondary);
		  font-size: var(--text-small);
	}
	.spec-meta {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 8px;
  margin: 0.75rem 0 1rem;
}
.status {
  display: inline-flex;
  align-items: center;
  min-height: 24px;
  padding: 0 8px;
  border: 1px solid var(--border);
  border-radius: 999px;
  background: var(--bg-muted);
  color: var(--text-secondary);
  font-size: var(--text-caption);
  font-weight: 600;
  text-transform: uppercase;
}
.pill {
  display: inline-flex;
  align-items: center;
  min-height: 22px;
  padding: 0 8px;
  margin: 0 4px 4px 0;
  border: 1px solid transparent;
  border-radius: 999px;
  font-size: var(--text-caption);
  font-weight: 400;
  line-height: 1.3;
}
.pill-required {
  border-color: transparent;
  background: var(--tag-required-bg) !important;
  color: var(--tag-required-fg) !important;
}
.pill-optional {
  border-color: transparent;
  background: var(--tag-optional-bg) !important;
  color: var(--tag-optional-fg) !important;
}
.pill-tone-0 {
  background: var(--brand-pink-soft);
  color: var(--pill-tone-0-fg);
}
.pill-tone-1 {
  background: var(--brand-coral-soft);
  color: var(--pill-tone-1-fg);
}
.pill-tone-2 {
  background: var(--brand-sky-soft);
  color: var(--pill-tone-2-fg);
}
.pill-tone-3 {
  background: var(--brand-lime-soft);
  color: var(--pill-tone-3-fg);
}
.pill-tone-4 {
  background: var(--brand-mint-soft);
  color: var(--pill-tone-4-fg);
}
.pill-tone-5 {
  background: var(--brand-lavender-soft);
  color: var(--pill-tone-5-fg);
}
.pill-tone-6 {
  background: var(--brand-coral-soft);
  color: var(--pill-tone-6-fg);
}
.pill-tone-7 {
  background: var(--brand-sky-soft);
  color: var(--pill-tone-7-fg);
}
.param-pills-none {
  color: var(--text-tertiary);
  font-size: var(--text-caption);
  font-style: italic;
}
@media (max-width: 1000px) {
  body.hb-docs-protocol .site-header { display: block; }
  body.hb-docs-protocol.mobile-nav-open .site-header { z-index: 280; }
  body.hb-docs-protocol .site-header-home {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-weight: 500;
  }
  body.hb-docs-protocol .sidebar { top: var(--header-height) !important; }
  body.hb-docs-protocol .content { padding-top: var(--header-height) !important; }
}
">>.
docs_sidebar(Items) ->
    [
        <<"<aside class=\"sidebar\" id=\"sidebar\"><h1>HyperBEAM</h1>"
            "<div class=\"sidebar-nav\"><ul>">>,
        Items,
        <<"</ul></div></aside>">>
    ].

device_info_path(DeviceID) ->
    <<"/~", DeviceID/binary, "/docs">>.
device_docs_route_path(DeviceID) ->
    <<"/~", DeviceID/binary, "/docs">>.
device_schema_path(DeviceID) ->
    <<"/~", DeviceID/binary, "/docs/schema">>.
device_direct_schema_path(DeviceID) ->
    device_schema_path(DeviceID).
device_schema_key_path(DeviceID, Key) ->
    <<"/~", DeviceID/binary, "/docs/schema/", Key/binary>>.
device_spec_path(DeviceID) ->
    <<"/~", DeviceID/binary, "/docs/spec">>.
device_spec_section_path(DeviceID, SectionId) ->
    <<"/~", DeviceID/binary, "/docs/spec/", SectionId/binary>>.
device_recipes_path(DeviceID) ->
    <<"/~", DeviceID/binary, "/docs/recipes">>.
device_recipe_path(DeviceID, Slug) ->
    <<"/~", DeviceID/binary, "/docs/recipes/", Slug/binary>>.
device_implementations_path(DeviceID) ->
    <<"/~", DeviceID/binary, "/docs/implementations">>.
device_schema_param_path(DeviceID, Key, Param) ->
    <<(device_schema_key_path(DeviceID, Key))/binary, "/", Param/binary>>.

device_doc_links(DeviceID) ->
    #{
        <<"self">> => device_info_path(DeviceID),
        <<"docs">> => device_docs_route_path(DeviceID),
        <<"schema">> => device_schema_path(DeviceID),
        <<"schema-direct">> => device_direct_schema_path(DeviceID),
        <<"spec">> => device_spec_path(DeviceID),
        <<"recipes">> => device_recipes_path(DeviceID),
        <<"implementations">> => device_implementations_path(DeviceID)
    }.

device_doc_link_fields(DeviceID) ->
    Links = device_doc_links(DeviceID),
    #{
        <<"links">> => Links,
        <<"schema-link">> => maps:get(<<"schema">>, Links),
        <<"specification-link">> => maps:get(<<"spec">>, Links),
        <<"recipes-link">> => maps:get(<<"recipes">>, Links)
    }.

devices_index_path() ->
    <<"/docs#devices">>.

active_path_match(ActivePath, Href) when is_binary(ActivePath), is_binary(Href) ->
    ActivePath =:= Href.

sidebar_li(ActivePath, Href, Content) ->
    ActiveClass =
        case active_path_match(ActivePath, Href) of
            true -> <<" class=\"active\"">>;
            false -> <<>>
        end,
    [
        <<"<li">>, ActiveClass, <<"><a href=\"">>, esc(Href), <<"\">">>,
        Content,
        <<"</a></li>">>
    ].

node_sidebar_index_items() ->
    [
        {<<"/docs/schema">>, <<"Schema">>},
        {<<"/docs/spec">>, <<"Spec">>},
        {<<"/docs/recipes">>, <<"Recipes">>},
        {<<"/docs/implementations">>, <<"Implementations">>}
    ].

sidebar_nav_section(ActivePath, SectionLabel, AllLabel, AllHref, ItemLis) ->
    [
        <<"<li><p>">>, SectionLabel, <<"</p><ul>">>,
        sidebar_li(ActivePath, AllHref, AllLabel),
        ItemLis,
        <<"</ul></li>">>
    ].

phosphor_icon_path_svg(Icon) ->
    Path = maps:get(Icon, recipe_icon_paths()),
    [
        <<"<svg viewBox=\"0 0 256 256\" fill=\"currentColor\" focusable=\"false\">">>,
        <<"<path d=\"">>, Path, <<"\"></path></svg>">>
    ].

sidebar_context_link_class(ActivePath, Href, Base) ->
    case active_path_match(ActivePath, Href) of
        true -> <<Base/binary, " is-active">>;
        false -> Base
    end.

sidebar_viewing_icon_markup(Icon) ->
    [
        <<"<span class=\"sidebar-viewing-back-icon\" aria-hidden=\"true\">">>,
        phosphor_icon_path_svg(Icon),
        <<"</span>">>
    ].

sidebar_viewing_back_link(ActivePath, Href, Label, Icon) ->
    [
        <<"<a class=\"">>,
        sidebar_context_link_class(ActivePath, Href, <<"sidebar-viewing-back">>),
        <<"\" href=\"">>, esc(Href), <<"\">">>,
        sidebar_viewing_icon_markup(Icon),
        esc(Label),
        <<"</a>">>
    ].

sidebar_node_context(ActivePath) ->
    [
        <<"<li class=\"sidebar-viewing-context\">">>,
        <<"<p class=\"eyebrow\">You are viewing</p>">>,
        <<"<a class=\"">>,
        sidebar_context_link_class(ActivePath, <<"/docs">>, <<"sidebar-viewing-device">>),
        <<"\" href=\"/docs\">Node</a>">>,
        <<"</li>">>
    ].

sidebar_device_context(ActivePath, DeviceID) ->
    DeviceHref = device_info_path(DeviceID),
    DevicesHref = devices_index_path(),
    [
        <<"<li class=\"sidebar-viewing-context\">">>,
        <<"<p class=\"eyebrow\">You are viewing</p>">>,
        <<"<a class=\"">>,
        sidebar_context_link_class(ActivePath, DeviceHref, <<"sidebar-viewing-device">>),
        <<"\" href=\"">>, esc(DeviceHref), <<"\">">>,
        esc(device_marked_id(DeviceID)),
        <<"</a>">>,
        sidebar_viewing_back_link(ActivePath, DevicesHref, <<"View All Devices">>, <<"stack">>),
        sidebar_viewing_back_link(ActivePath, <<"/docs">>, <<"View All Node Info">>, <<"database">>),
        <<"</li>">>
    ].

node_sidebar(Devices, ActivePath) ->
    Boilerplate = boilerplate_index(),
    [
        sidebar_node_context(ActivePath),
        node_sidebar_devices_section(Devices, ActivePath),
        [
            <<"<li class=\"sidebar-flat-links\"><p>Indexes</p><ul>">>,
            [sidebar_li(ActivePath, Href, Label) || {Href, Label} <- node_sidebar_index_items()],
            <<"</ul></li>">>
        ],
        [
            <<"<li><p>Guides</p><ul>">>,
            boilerplate_sidebar_rows(Boilerplate),
            <<"</ul></li>">>
        ]
    ].

node_sidebar_devices_section(Devices, ActivePath) ->
    [
        <<"<li class=\"sidebar-flat-links\"><p>Devices</p><ul>">>,
        [
            sidebar_li(
                ActivePath,
                maps:get(<<"href">>, Device),
                esc(device_marked_id(device_card_label(Device)))
            )
        || Device <- Devices
        ],
        <<"</ul></li>">>
    ].

boilerplate_sidebar_rows(Index) ->
    Pages = maps:get(<<"pages">>, Index, []),
    [
        <<"<li><a href=\"/docs/guides\">All guides</a></li>">>,
        [
            boilerplate_sidebar_section(Section, Pages)
        || Section <- boilerplate_section_order()
        ]
    ].

boilerplate_sidebar_section(<<"Overview">>, Pages) ->
    case boilerplate_pages_for_section(<<"Overview">>, Pages) of
        [] ->
            [];
        [Page | _Rest] ->
            [
                <<"<li><a href=\"">>, esc(maps:get(<<"href">>, Page, <<>>)),
                <<"\">Overview</a></li>">>
            ]
    end;
boilerplate_sidebar_section(Section, Pages) ->
    case boilerplate_pages_for_section(Section, Pages) of
        [] ->
            [];
        SectionPages ->
            [
                <<"<li><p>">>, esc(Section), <<"</p><ul>">>,
                [
                    [
                        <<"<li><a href=\"">>, esc(maps:get(<<"href">>, Page, <<>>)),
                        <<"\">">>, esc(maps:get(<<"title">>, Page, <<>>)), <<"</a></li>">>
                    ]
                || Page <- SectionPages
                ],
                <<"</ul></li>">>
            ]
    end.

boilerplate_pages_for_section(Section, Pages) ->
    [
        Page
    || Page <- Pages,
       maps:get(<<"section">>, Page, <<>>) =:= Section
    ].

boilerplate_section_order() ->
    [
        <<"Introduction">>,
        <<"Processes">>,
        <<"Device Forge">>
    ].

index_section_li_open(ActivePath) ->
    NodeIndexPaths = [Href || {Href, _} <- node_sidebar_index_items()],
    case lists:member(ActivePath, NodeIndexPaths) of
        true -> <<"<li class=\"sidebar-flat-links active\">">>;
        false -> <<"<li class=\"sidebar-flat-links\">">>
    end.

node_sidebar_from_component(Devices, ActivePath) ->
    [
        sidebar_node_context(ActivePath),
        [
            index_section_li_open(ActivePath),
            <<"<p>Index</p><ul>">>,
            [
                sidebar_li(
                    ActivePath,
                    maps:get(<<"href">>, Device, <<>>),
                    esc(device_marked_id(maps:get(<<"device">>, Device, <<>>)))
                )
            || Device <- Devices
            ],
            <<"</ul></li>">>
        ]
    ].

device_sidebar(Data, ActivePath) ->
    Device = maps:get(<<"device">>, Data, #{}),
    DeviceID = maps:get(<<"id">>, Device, <<>>),
    SchemaOrder = maps:get(<<"schema-order">>, Data, []),
    Spec = maps:get(<<"spec">>, Data, #{}),
    SpecSections = spec_sections(Spec),
    Recipes = maps:get(<<"recipes">>, Data, #{}),
    [
        sidebar_device_context(ActivePath, DeviceID),
        sidebar_nav_section(
            ActivePath, <<"Schema">>, <<"All keys">>, device_schema_path(DeviceID),
            [sidebar_li(ActivePath, device_schema_key_path(DeviceID, Key), esc(Key)) || Key <- SchemaOrder]
        ),
        sidebar_nav_section(
            ActivePath, <<"Spec">>, <<"All spec">>, device_spec_path(DeviceID),
            [
                sidebar_li(
                    ActivePath,
                    device_spec_section_path(DeviceID, SectionId),
                    esc(spec_section_nav_label(Title))
                )
            || {SectionId, Title} <- SpecSections
            ]
        ),
        sidebar_nav_section(
            ActivePath, <<"Recipes">>, <<"All recipes">>, device_recipes_path(DeviceID),
            [
                sidebar_li(
                    ActivePath,
                    device_recipe_path(DeviceID, Slug),
                    esc(maps:get(<<"title">>, Recipe, Slug))
                )
            || {Slug, Recipe} <- lists:sort(maps:to_list(Recipes))
            ]
        )
    ].

device_row(Device) ->
    Label = device_card_label(Device),
    Title = device_card_title(Device),
    Summary = device_card_summary_text(Device),
    TintClass = device_tint_class(Label),
    [
        <<"<a class=\"hb-docs-device-card\" href=\"">>,
        esc(device_card_href(Device)),
        <<"\">">>,
        <<"<div class=\"hb-docs-device-card-body\">">>,
        <<"<div class=\"hb-docs-device-card-title-row ">>,
        TintClass,
        <<"\">">>,
        <<"<strong class=\"hb-docs-device-card-title\">">>,
        esc(Title),
        <<"</strong>">>,
        <<"<span class=\"hb-docs-device-card-id\">">>,
        esc(device_marked_id(Label)),
        <<"</span>">>,
        <<"</div>">>,
        <<"<span class=\"hb-docs-device-card-desc\">">>,
        esc(card_summary(Summary)),
        <<"</span></div></a>">>
    ].

devices_section(Devices) ->
    [
        <<"<div class=\"hb-docs-section-header\"><h2 id=\"devices\">Devices</h2>">>,
        <<"<a class=\"hb-docs-section-link\" href=\"/docs#devices\">">>,
        <<"View all</a></div><div class=\"hb-docs-device-grid\">">>,
        [device_row(Device) || Device <- Devices],
        <<"</div>">>
    ].

device_card_label(#{<<"device">> := Id}) ->
    Id;
device_card_label(Device) ->
    <<(maps:get(<<"name">>, Device))/binary, "@",
        (maps:get(<<"version">>, Device))/binary>>.

device_marked_id(Label) when is_binary(Label) ->
    case Label of
        <<$~, _/binary>> -> Label;
        _ -> <<$~, Label/binary>>
    end.

device_card_href(Device) ->
    maps:get(<<"href">>, Device, <<>>).

device_card_title(#{<<"device">> := Id}) ->
    device_display_title(Id);
device_card_title(Device) ->
    device_display_title(maps:get(<<"name">>, Device, device_card_label(Device))).

device_card_summary_text(Device) ->
    maps:get(<<"summary">>, Device,
        maps:get(<<"schema">>, Device, maps:get(<<"href">>, Device, <<>>))).

device_display_names() ->
    #{
        <<"arweave">> => <<"Arweave">>,
        <<"message">> => <<"Message">>,
        <<"cookbook">> => <<"Cookbook">>
    }.

device_display_title(Id) when is_binary(Id) ->
    case maps:get(Id, device_display_names(), undefined) of
        undefined ->
            case binary:split(Id, <<"@">>) of
                [Name, _Version] -> device_display_title(Name);
                _ ->
                    case Id of
                        <<C, Rest/binary>> ->
                            <<(string:uppercase(<<C>>))/binary, Rest/binary>>;
                        _ ->
                            Id
                    end
            end;
        Title ->
            Title
    end.

device_tint_class(Label) ->
    Index = erlang:phash2(Label) rem 8,
    <<"hb-docs-device-tint-", (integer_to_binary(Index))/binary>>.

boilerplate_section_cards(Index, Heading) ->
    [
        boilerplate_section_block(Section, Pages, Heading)
    || {Section, Pages} <- boilerplate_grouped_pages(Index)
    ].

boilerplate_section_block(Section, Pages, Heading) ->
    Tag =
        case Section of
            <<"Reference">> -> <<"h2">>;
            _ -> boilerplate_section_heading_tag(Heading)
        end,
    SectionClass =
        case Section of
            <<"Reference">> -> <<" hb-docs-reference-section">>;
            _ -> <<>>
        end,
    {ContainerOpen, ContainerClose, RowFun} = boilerplate_section_layout(Section),
    [
        <<"<section class=\"hb-docs-guide-section">>, SectionClass, <<"\">">>,
        ["<", Tag, ">", esc(Section), "</", Tag, ">"],
        ContainerOpen,
        [RowFun(Page, Section) || Page <- Pages],
        ContainerClose,
        <<"</section>">>
    ].

boilerplate_section_layout(<<"Reference">>) ->
    {<<"<div class=\"hb-docs-reference-list\">">>, <<"</div>">>, fun boilerplate_list_row/2};
boilerplate_section_layout(_) ->
    {<<"<div class=\"hb-docs-card-grid\">">>, <<"</div>">>, fun boilerplate_card_row/2}.

boilerplate_section_heading_tag(h2) -> <<"h2">>;
boilerplate_section_heading_tag(h3) -> <<"h3">>;
boilerplate_section_heading_tag(_) -> <<"h2">>.

boilerplate_grouped_pages(Index) ->
    boilerplate_group_pages_by_section(maps:get(<<"pages">>, Index, []), []).

boilerplate_group_pages_by_section([], Acc) ->
    [{Section, lists:reverse(Pages)} || {Section, Pages} <- lists:reverse(Acc)];
boilerplate_group_pages_by_section([Page | Rest], Acc) ->
    Section = maps:get(<<"section">>, Page, <<>>),
    case Acc of
        [{Section, Pages} | Tail] ->
            boilerplate_group_pages_by_section(Rest, [{Section, [Page | Pages]} | Tail]);
        _ ->
            boilerplate_group_pages_by_section(Rest, [{Section, [Page]} | Acc])
    end.

boilerplate_card_row(Page, Section)
        when Section =:= <<"Device Forge">>; Section =:= <<"Processes">> ->
    boilerplate_recipe_card_row(Page);
boilerplate_card_row(Page, _Section) ->
    [
        <<"<a class=\"hb-docs-card\" href=\"">>,
        esc(maps:get(<<"href">>, Page, <<>>)),
        <<"\"><strong>">>, esc(maps:get(<<"title">>, Page, <<>>)),
        <<"</strong><span>">>, esc(card_summary(maps:get(<<"summary">>, Page, <<>>))),
        <<"</span></a>">>
    ].

boilerplate_list_row(Page, _Section) ->
    [
        <<"<p class=\"hb-docs-reference-item\"><a href=\"">>,
        esc(maps:get(<<"href">>, Page, <<>>)),
        <<"\"><strong>">>, esc(maps:get(<<"title">>, Page, <<>>)),
        <<"</strong></a><br><span class=\"hb-docs-guide-list-desc\">">>,
        esc(card_summary(maps:get(<<"summary">>, Page, <<>>))),
        <<"</span></p>">>
    ].

boilerplate_recipe_card_row(Page) ->
    Title = maps:get(<<"title">>, Page, <<>>),
    Slug = boilerplate_page_slug(Page),
    Summary = card_summary(maps:get(<<"summary">>, Page, <<>>)),
    [
        <<"<a class=\"hb-docs-card hb-docs-recipe-card\" href=\"">>,
        esc(maps:get(<<"href">>, Page, <<>>)),
        <<"\">">>,
        <<"<div class=\"hb-docs-recipe-card-header\">">>,
        recipe_icon_markup(Slug, #{<<"title">> => Title}),
        <<"<strong class=\"hb-docs-recipe-card-title\">">>,
        esc(Title),
        <<"</strong></div>">>,
        <<"<div class=\"hb-docs-recipe-card-body\">">>,
        <<"<span class=\"hb-docs-recipe-card-desc\">">>,
        esc(Summary),
        <<"</span><div class=\"hb-docs-recipe-card-footer\">">>,
        <<"<span class=\"hb-docs-recipe-card-cta\">Open &rarr;</span>">>,
        <<"</div></div></a>">>
    ].

boilerplate_structured_index(Index) ->
    Pages = maps:get(<<"pages">>, Index, []),
    [
        <<"<nav class=\"hb-docs-guide-index\" aria-label=\"Guides\">">>,
        [
            boilerplate_guide_group(Section, Pages)
        || Section <- boilerplate_section_order()
        ],
        <<"</nav>">>
    ].

boilerplate_guide_group(Section, Pages) ->
    case boilerplate_pages_for_section(Section, Pages) of
        [] ->
            [];
        SectionPages ->
            [
                <<"<section class=\"hb-docs-guide-group\"><h3>">>, esc(Section),
                <<"</h3><ul>">>,
                [
                    boilerplate_guide_link(Page)
                || Page <- SectionPages
                ],
                <<"</ul></section>">>
            ]
    end.

boilerplate_guide_link(Page) ->
    [
        <<"<li><a href=\"">>, esc(maps:get(<<"href">>, Page, <<>>)),
        <<"\">">>, esc(maps:get(<<"title">>, Page, <<>>)), <<"</a></li>">>
    ].

boilerplate_page_slug(Page) ->
    Href = maps:get(<<"href">>, Page, <<>>),
    case binary:split(Href, <<"/">>, [global]) of
        Parts ->
            case lists:reverse(Parts) of
                [Slug | _] when Slug =/= <<>> -> Slug;
                _ -> <<"guide">>
            end
    end.

concept_rows(Concepts) ->
    [
        [
            <<"<p><strong>">>, esc(Key), <<"</strong><br>">>, esc(Value), <<"</p>">>
        ]
    || {Key, Value} <- lists:sort(maps:to_list(Concepts))
    ].

schema_table(DeviceID, Schema, Order) ->
    IncludeDescriptions = schema_has_descriptions(Schema, Order),
    [
        <<"<table><thead><tr><th>Key</th>">>,
        case IncludeDescriptions of
            true -> <<"<th>Description</th>">>;
            false -> []
        end,
        <<"<th>Parameters</th></tr></thead><tbody>">>,
        schema_rows(DeviceID, Schema, Order, IncludeDescriptions),
        <<"</tbody></table>">>
    ].

schema_has_descriptions(Schema, Order) ->
    lists:any(
        fun(Name) ->
            case maps:get(Name, Schema, undefined) of
                undefined -> false;
                KeySchema -> trim(maps:get(<<"description">>, KeySchema, <<>>)) =/= <<>>
            end
        end,
        Order
    ).

schema_rows(DeviceID, Schema, Order, IncludeDescriptions) ->
    [
        case maps:get(Name, Schema, undefined) of
            undefined -> [];
            KeySchema ->
                [
                    <<"<tr><td><a href=\"">>,
                    esc(device_schema_key_path(DeviceID, Name)),
                    <<"\">">>, esc(Name), <<"</a></td>">>,
                    schema_description_cell(KeySchema, IncludeDescriptions),
                    <<"<td>">>,
                    param_pills(DeviceID, Name, maps:get(<<"parameters">>, KeySchema, #{})),
                    <<"</td></tr>">>
                ]
        end
    || Name <- Order
    ].

schema_description_cell(KeySchema, true) ->
    [<<"<td>">>, esc(maps:get(<<"description">>, KeySchema, <<>>)), <<"</td>">>];
schema_description_cell(_KeySchema, false) ->
    [].

param_pills(_DeviceID, _Key, Params) when map_size(Params) =:= 0 ->
    <<"<span class=\"param-pills-none\">none</span>">>;
param_pills(_DeviceID, _Key, Params) ->
    [
        [
            <<"<span class=\"">>, pill_class_for_label(param_required_label(Param)), <<"\">">>,
            esc(Name),
            <<" ">>, param_required_label(Param),
            <<"</span>">>
        ]
    || {Name, Param} <- lists:sort(maps:to_list(Params))
    ].

param_required_label(Param) ->
    case maps:get(<<"required">>, Param, false) of
        true -> <<"required">>;
        false -> <<"optional">>
    end.

pill_class_for_label(<<"required">>) ->
    <<"pill pill-required">>;
pill_class_for_label(<<"optional">>) ->
    <<"pill pill-optional">>;
pill_class_for_label(Label) when is_binary(Label) ->
    Tone = erlang:phash2(Label) rem 8,
    <<"pill pill-tone-", (integer_to_binary(Tone))/binary>>.

param_required_cell(_DeviceID, _Key, _Name, Param) ->
    Label = param_required_label(Param),
    [<<"<span class=\"">>, pill_class_for_label(Label), <<"\">">>, esc(Label), <<"</span>">>].

recipe_icon_keywords() ->
    [
        {<<"bundle">>, <<"package">>},
        {<<"reassembl">>, <<"puzzle-piece">>},
        {<<"inspect">>, <<"magnifying-glass">>},
        {<<"post">>, <<"upload">>},
        {<<"upload">>, <<"upload">>},
        {<<"chunk">>, <<"stack">>},
        {<<"offset">>, <<"crosshair">>},
        {<<"resolve">>, <<"crosshair">>},
        {<<"verify">>, <<"seal-check">>},
        {<<"commitment">>, <<"seal-check">>},
        {<<"serialize">>, <<"export">>},
        {<<"typed">>, <<"book-open">>},
        {<<"key">>, <<"key">>},
        {<<"list">>, <<"list-bullets">>},
        {<<"message">>, <<"chat-dots">>},
        {<<"transaction">>, <<"chat-dots">>},
        {<<"raw">>, <<"database">>},
        {<<"range">>, <<"database">>},
        {<<"read">>, <<"book-open">>}
    ].

recipe_icon_paths() ->
    #{
        <<"package">> =>
            <<"M223.68,66.15,135.68,18a15.88,15.88,0,0,0-15.36,0l-88,48.17a16,16,0,0,0-8.32,14v95.64a16,16,0,0,0,8.32,14l88,48.17a15.88,15.88,0,0,0,15.36,0l88-48.17a16,16,0,0,0,8.32-14V80.18A16,16,0,0,0,223.68,66.15ZM128,32l80.34,44-29.77,16.3-80.35-44ZM128,120,47.66,76l33.9-18.56,80.34,44ZM40,90l80,43.78v85.79L40,175.82Zm176,85.78h0l-80,43.79V133.82l32-17.51V152a8,8,0,0,0,16,0V107.55L216,90v85.77Z">>,
        <<"upload">> =>
            <<"M240,136v64a16,16,0,0,1-16,16H32a16,16,0,0,1-16-16V136a16,16,0,0,1,16-16H80a8,8,0,0,1,0,16H32v64H224V136H176a8,8,0,0,1,0-16h48A16,16,0,0,1,240,136ZM85.66,77.66,120,43.31V128a8,8,0,0,0,16,0V43.31l34.34,34.35a8,8,0,0,0,11.32-11.32l-48-48a8,8,0,0,0-11.32,0l-48,48A8,8,0,0,0,85.66,77.66ZM200,168a12,12,0,1,0-12,12A12,12,0,0,0,200,168Z">>,
        <<"book-open">> =>
            <<"M232,48H160a40,40,0,0,0-32,16A40,40,0,0,0,96,48H24a8,8,0,0,0-8,8V200a8,8,0,0,0,8,8H96a24,24,0,0,1,24,24,8,8,0,0,0,16,0,24,24,0,0,1,24-24h72a8,8,0,0,0,8-8V56A8,8,0,0,0,232,48ZM96,192H32V64H96a24,24,0,0,1,24,24V200A39.81,39.81,0,0,0,96,192Zm128,0H160a39.81,39.81,0,0,0-24,8V88a24,24,0,0,1,24-24h64Z">>,
        <<"stack">> =>
            <<"M230.91,172A8,8,0,0,1,228,182.91l-96,56a8,8,0,0,1-8.06,0l-96-56A8,8,0,0,1,36,169.09l92,53.65,92-53.65A8,8,0,0,1,230.91,172ZM220,121.09l-92,53.65L36,121.09A8,8,0,0,0,28,134.91l96,56a8,8,0,0,0,8.06,0l96-56A8,8,0,1,0,220,121.09ZM24,80a8,8,0,0,1,4-6.91l96-56a8,8,0,0,1,8.06,0l96,56a8,8,0,0,1,0,13.82l-96,56a8,8,0,0,1-8.06,0l-96-56A8,8,0,0,1,24,80Zm23.88,0L128,126.74,208.12,80,128,33.26Z">>,
        <<"crosshair">> =>
            <<"M232,120h-8.34A96.14,96.14,0,0,0,136,32.34V24a8,8,0,0,0-16,0v8.34A96.14,96.14,0,0,0,32.34,120H24a8,8,0,0,0,0,16h8.34A96.14,96.14,0,0,0,120,223.66V232a8,8,0,0,0,16,0v-8.34A96.14,96.14,0,0,0,223.66,136H232a8,8,0,0,0,0-16Zm-96,87.6V200a8,8,0,0,0-16,0v7.6A80.15,80.15,0,0,1,48.4,136H56a8,8,0,0,0,0-16H48.4A80.15,80.15,0,0,1,120,48.4V56a8,8,0,0,0,16,0V48.4A80.15,80.15,0,0,1,207.6,120H200a8,8,0,0,0,0,16h7.6A80.15,80.15,0,0,1,136,207.6ZM128,88a40,40,0,1,0,40,40A40,40,0,0,0,128,88Zm0,64a24,24,0,1,1,24-24A24,24,0,0,1,128,152Z">>,
        <<"magnifying-glass">> =>
            <<"M229.66,218.34l-50.07-50.06a88.11,88.11,0,1,0-11.31,11.31l50.06,50.07a8,8,0,0,0,11.32-11.32ZM40,112a72,72,0,1,1,72,72A72.08,72.08,0,0,1,40,112Z">>,
        <<"export">> =>
            <<"M216,112v96a16,16,0,0,1-16,16H56a16,16,0,0,1-16-16V112A16,16,0,0,1,56,96H80a8,8,0,0,1,0,16H56v96H200V112H176a8,8,0,0,1,0-16h24A16,16,0,0,1,216,112ZM93.66,69.66,120,43.31V136a8,8,0,0,0,16,0V43.31l26.34,26.35a8,8,0,0,0,11.32-11.32l-40-40a8,8,0,0,0-11.32,0l-40,40A8,8,0,0,0,93.66,69.66Z">>,
        <<"key">> =>
            <<"M216.57,39.43A80,80,0,0,0,83.91,120.78L28.69,176A15.86,15.86,0,0,0,24,187.31V216a16,16,0,0,0,16,16H72a8,8,0,0,0,8-8V208H96a8,8,0,0,0,8-8V184h16a8,8,0,0,0,5.66-2.34l9.56-9.57A79.73,79.73,0,0,0,160,176h.1A80,80,0,0,0,216.57,39.43ZM224,98.1c-1.09,34.09-29.75,61.86-63.89,61.9H160a63.7,63.7,0,0,1-23.65-4.51,8,8,0,0,0-8.84,1.68L116.69,168H96a8,8,0,0,0-8,8v16H72a8,8,0,0,0-8,8v16H40V187.31l58.83-58.82a8,8,0,0,0,1.68-8.84A63.72,63.72,0,0,1,96,95.92c0-34.14,27.81-62.8,61.9-63.89A64,64,0,0,1,224,98.1ZM192,76a12,12,0,1,1-12-12A12,12,0,0,1,192,76Z">>,
        <<"seal-check">> =>
            <<"M225.86,102.82c-3.77-3.94-7.67-8-9.14-11.57-1.36-3.27-1.44-8.69-1.52-13.94-.15-9.76-.31-20.82-8-28.51s-18.75-7.85-28.51-8c-5.25-.08-10.67-.16-13.94-1.52-3.56-1.47-7.63-5.37-11.57-9.14C146.28,23.51,138.44,16,128,16s-18.27,7.51-25.18,14.14c-3.94,3.77-8,7.67-11.57,9.14C88,40.64,82.56,40.72,77.31,40.8c-9.76.15-20.82.31-28.51,8S41,67.55,40.8,77.31c-.08,5.25-.16,10.67-1.52,13.94-1.47,3.56-5.37,7.63-9.14,11.57C23.51,109.72,16,117.56,16,128s7.51,18.27,14.14,25.18c3.77,3.94,7.67,8,9.14,11.57,1.36,3.27,1.44,8.69,1.52,13.94.15,9.76.31,20.82,8,28.51s18.75,7.85,28.51,8c5.25.08,10.67.16,13.94,1.52,3.56,1.47,7.63,5.37,11.57,9.14C109.72,232.49,117.56,240,128,240s18.27-7.51,25.18-14.14c3.94-3.77,8-7.67,11.57-9.14,3.27-1.36,8.69-1.44,13.94-1.52,9.76-.15,20.82-.31,28.51-8s7.85-18.75,8-28.51c.08-5.25.16-10.67,1.52-13.94,1.47-3.56,5.37-7.63,9.14-11.57C232.49,146.28,240,138.44,240,128S232.49,109.73,225.86,102.82Zm-11.55,39.29c-4.79,5-9.75,10.17-12.38,16.52-2.52,6.1-2.63,13.07-2.73,19.82-.1,7-.21,14.33-3.32,17.43s-10.39,3.22-17.43,3.32c-6.75.1-13.72.21-19.82,2.73-6.35,2.63-11.52,7.59-16.52,12.38S132,224,128,224s-9.15-4.92-14.11-9.69-10.17-9.75-16.52-12.38c-6.1-2.52-13.07-2.63-19.82-2.73-7-.1-14.33-.21-17.43-3.32s-3.22-10.39-3.32-17.43c-.1-6.75-.21-13.72-2.73-19.82-2.63-6.35-7.59-11.52-12.38-16.52S32,132,32,128s4.92-9.15,9.69-14.11,9.75-10.17,12.38-16.52c2.52-6.1,2.63-13.07,2.73-19.82.1-7,.21-14.33,3.32-17.43S70.51,56.9,77.55,56.8c6.75-.1,13.72-.21,19.82-2.73,6.35-2.63,11.52-7.59,16.52-12.38S124,32,128,32s9.15,4.92,14.11,9.69,10.17,9.75,16.52,12.38c6.1,2.52,13.07,2.63,19.82,2.73,7,.1,14.33.21,17.43,3.32s3.22,10.39,3.32,17.43c.1,6.75.21,13.72,2.73,19.82,2.63,6.35,7.59,11.52,12.38,16.52S224,124,224,128,219.08,137.15,214.31,142.11ZM173.66,98.34a8,8,0,0,1,0,11.32l-56,56a8,8,0,0,1-11.32,0l-24-24a8,8,0,0,1,11.32-11.32L112,148.69l50.34-50.35A8,8,0,0,1,173.66,98.34Z">>,
        <<"list-bullets">> =>
            <<"M80,64a8,8,0,0,1,8-8H216a8,8,0,0,1,0,16H88A8,8,0,0,1,80,64Zm136,56H88a8,8,0,0,0,0,16H216a8,8,0,0,0,0-16Zm0,64H88a8,8,0,0,0,0,16H216a8,8,0,0,0,0-16ZM44,52A12,12,0,1,0,56,64,12,12,0,0,0,44,52Zm0,64a12,12,0,1,0,12,12A12,12,0,0,0,44,116Zm0,64a12,12,0,1,0,12,12A12,12,0,0,0,44,180Z">>,
        <<"database">> =>
            <<"M128,24C74.17,24,32,48.6,32,80v96c0,31.4,42.17,56,96,56s96-24.6,96-56V80C224,48.6,181.83,24,128,24Zm80,104c0,9.62-7.88,19.43-21.61,26.92C170.93,163.35,150.19,168,128,168s-42.93-4.65-58.39-13.08C55.88,147.43,48,137.62,48,128V111.36c17.06,15,46.23,24.64,80,24.64s62.94-9.68,80-24.64ZM69.61,53.08C85.07,44.65,105.81,40,128,40s42.93,4.65,58.39,13.08C200.12,60.57,208,70.38,208,80s-7.88,19.43-21.61,26.92C170.93,115.35,150.19,120,128,120s-42.93-4.65-58.39-13.08C55.88,99.43,48,89.62,48,80S55.88,60.57,69.61,53.08ZM186.39,202.92C170.93,211.35,150.19,216,128,216s-42.93-4.65-58.39-13.08C55.88,195.43,48,185.62,48,176V159.36c17.06,15,46.23,24.64,80,24.64s62.94-9.68,80-24.64V176C208,185.62,200.12,195.43,186.39,202.92Z">>,
        <<"chat-dots">> =>
            <<"M116,128a12,12,0,1,1,12,12A12,12,0,0,1,116,128ZM84,140a12,12,0,1,0-12-12A12,12,0,0,0,84,140Zm88,0a12,12,0,1,0-12-12A12,12,0,0,0,172,140Zm60-76V192a16,16,0,0,1-16,16H83l-32.6,28.16-.09.07A15.89,15.89,0,0,1,40,240a16.13,16.13,0,0,1-6.8-1.52A15.85,15.85,0,0,1,24,224V64A16,16,0,0,1,40,48H216A16,16,0,0,1,232,64ZM40,224h0ZM216,64H40V224l34.77-30A8,8,0,0,1,80,192H216Z">>,
        <<"link">> =>
            <<"M165.66,90.34a8,8,0,0,1,0,11.32l-64,64a8,8,0,0,1-11.32-11.32l64-64A8,8,0,0,1,165.66,90.34ZM215.6,40.4a56.08,56.08,0,0,0-79.2,0L112,64.8a8,8,0,0,0,11.31,11.31l24.4-24.4a40,40,0,1,1,56.57,56.57l-24.4,24.4A8,8,0,0,0,191.2,144l24.4-24.4A56.08,56.08,0,0,0,215.6,40.4ZM132.69,179.89l-24.4,24.4a40,40,0,1,1-56.57-56.57l24.4-24.4A8,8,0,0,0,64.8,112l-24.4,24.4a56,56,0,0,0,79.2,79.2L144,191.2a8,8,0,0,0-11.31-11.31Z">>,
        <<"puzzle-piece">> =>
            <<"M220.27,158.54a8,8,0,0,0-7.7-.46,20,20,0,1,1,0-36.16A8,8,0,0,0,224,114.69V72a16,16,0,0,0-16-16H171.78a35.36,35.36,0,0,0,.22-4,36.11,36.11,0,0,0-11.36-26.24,36,36,0,0,0-60.55,23.62,36.56,36.56,0,0,0,.14,6.62H64A16,16,0,0,0,48,72v32.22a35.36,35.36,0,0,0-4-.22,36.12,36.12,0,0,0-26.24,11.36,35.7,35.7,0,0,0-9.69,27,36.08,36.08,0,0,0,33.31,33.6,35.68,35.68,0,0,0,6.62-.14V208a16,16,0,0,0,16,16H208a16,16,0,0,0,16-16V165.31A8,8,0,0,0,220.27,158.54ZM208,208H64V165.31a8,8,0,0,0-11.43-7.23,20,20,0,1,1,0-36.16A8,8,0,0,0,64,114.69V72h46.69a8,8,0,0,0,7.23-11.43,20,20,0,1,1,36.16,0A8,8,0,0,0,161.31,72H208v32.23a35.68,35.68,0,0,0-6.62-.14A36,36,0,0,0,204,176a35.36,35.36,0,0,0,4-.22Z">>,
        <<"cooking-pot">> =>
            <<"M88,48V16a8,8,0,0,1,16,0V48a8,8,0,0,1-16,0Zm40,8a8,8,0,0,0,8-8V16a8,8,0,0,0-16,0V48A8,8,0,0,0,128,56Zm32,0a8,8,0,0,0,8-8V16a8,8,0,0,0-16,0V48A8,8,0,0,0,160,56Zm92.8,46.4L224,124v60a32,32,0,0,1-32,32H64a32,32,0,0,1-32-32V124L3.2,102.4a8,8,0,0,1,9.6-12.8L32,104V80a8,8,0,0,1,8-8H216a8,8,0,0,1,8,8v24l19.2-14.4a8,8,0,0,1,9.6,12.8ZM208,88H48v96a16,16,0,0,0,16,16H192a16,16,0,0,0,16-16Z">>
    }.

recipe_icon_name(Slug, Title) ->
    Text =
        iolist_to_binary([
            hb_util:to_lower(hb_util:bin(Slug)),
            <<" ">>,
            hb_util:to_lower(hb_util:bin(Title))
        ]),
    case first_recipe_icon_match(recipe_icon_keywords(), Text) of
        undefined -> <<"cooking-pot">>;
        Icon -> Icon
    end.

first_recipe_icon_match([], _Text) ->
    undefined;
first_recipe_icon_match([{Keyword, Icon} | Rest], Text) ->
    case binary:match(Text, Keyword) of
        nomatch -> first_recipe_icon_match(Rest, Text);
        _ -> Icon
    end.

recipe_icon_markup(Slug, Recipe) ->
    Icon = recipe_icon_name(Slug, maps:get(<<"title">>, Recipe, Slug)),
    [
        <<"<div class=\"hb-docs-recipe-card-icon\" aria-hidden=\"true\">">>,
        phosphor_icon_path_svg(Icon),
        <<"</div>">>
    ].

recipe_nav(DeviceID, Recipes) ->
    [
        [
            <<"<a class=\"hb-docs-card hb-docs-recipe-card\" href=\"">>,
            esc(device_recipe_path(DeviceID, Name)),
            <<"\">">>,
            <<"<div class=\"hb-docs-recipe-card-header\">">>,
            recipe_icon_markup(Name, Recipe),
            <<"<strong class=\"hb-docs-recipe-card-title\">">>,
            esc(maps:get(<<"title">>, Recipe, Name)),
            <<"</strong></div>">>,
            <<"<div class=\"hb-docs-recipe-card-body\">">>,
            <<"<span class=\"hb-docs-recipe-card-desc\">">>,
            esc(recipe_card_summary(Recipe)),
            <<"</span><div class=\"hb-docs-recipe-card-footer\">">>,
            <<"<span class=\"hb-docs-recipe-card-cta\">Open &rarr;</span>">>,
            recipe_card_meta(Recipe),
            <<"</div></div></a>">>
        ]
    || {Name, Recipe} <- lists:sort(maps:to_list(Recipes))
    ].

schema_source_note(Data) ->
    case maps:get(<<"schema-source">>, Data, undefined) of
        Source when is_map(Source) ->
            [
                <<"<p class=\"hb-docs-renderer-note\"><strong>Schema source:</strong> ">>,
                esc(schema_source_label(Source)),
                <<"</p>">>
            ];
        _ ->
            []
    end.

schema_source_label(Source) ->
    Mode = maps:get(<<"mode">>, Source, <<"unknown">>),
    case Mode of
        <<"implementation-derived">> ->
            iolist_to_binary([
                <<"implementation-derived via ">>,
                maps:get(<<"extractor">>, Source, <<"hb_types:extract/2">>),
                <<" (">>,
                hb_util:bin(maps:get(<<"key-count">>, Source, 0)),
                <<" keys)">>
            ]);
        <<"implementation-derived-unavailable">> ->
            iolist_to_binary([
                <<"implementation-derived unavailable">>,
                schema_source_status_suffix(Source)
            ]);
        _ ->
            Mode
    end.

schema_source_status_suffix(Source) ->
    case maps:get(<<"status">>, Source, <<>>) of
        <<>> -> <<>>;
        Status -> iolist_to_binary([<<" (">>, Status, <<")">>])
    end.

render_spec_section(_DeviceID, Spec) ->
    [
        <<"<h2 id=\"spec\">Spec</h2>">>,
        render_spec_body(Spec)
    ].

render_spec_body(Spec) ->
    Status = maps:get(<<"spec-status">>, Spec, <<"missing">>),
    [
        spec_tx_link_paragraph(Spec),
        case {Status, spec_markdown(Spec)} of
            {<<"present">>, Markdown} when byte_size(Markdown) > 0 ->
                render_markdown_with_heading_ids(drop_first_h1(Markdown), #{
                    <<"strip-numbered-headings">> => true
                });
            _ ->
                [<<"<p>">>, esc(maps:get(<<"summary">>, Spec, <<>>)), <<"</p>">>]
        end
    ].

%% @doc Strip leading "N. " numbering from spec section titles for nav display.
spec_section_nav_label(Title) ->
    case spec_section_nav_skip_digits(Title, 0) of
        {Count, <<".", Rest/binary>>} when Count > 0 ->
            trim(Rest);
        _ ->
            Title
    end.

spec_section_nav_skip_digits(<<C, Rest/binary>>, Count) when C >= $0, C =< $9 ->
    spec_section_nav_skip_digits(Rest, Count + 1);
spec_section_nav_skip_digits(Bin, Count) ->
    {Count, Bin}.

spec_sections(Spec) ->
    case maps:get(<<"spec-status">>, Spec, <<"missing">>) of
        <<"present">> ->
            case spec_markdown(Spec) of
                Markdown when byte_size(Markdown) > 0 ->
                    spec_sections_from_markdown(drop_first_h1(Markdown));
                _ ->
                    []
            end;
        _ ->
            []
    end.

spec_sections_from_markdown(Markdown) ->
    spec_sections_from_lines(binary:split(Markdown, <<"\n">>, [global]), [], #{}).

spec_sections_from_lines([], Acc, _UsedIds) ->
    lists:reverse(Acc);
spec_sections_from_lines([Line | Rest], Acc, UsedIds) ->
    case heading(trim(Line)) of
        {2, Text} ->
            Plain = strip_inline_markdown(Text),
            {SectionId, NewUsedIds} = unique_heading_slug(Plain, UsedIds),
            spec_sections_from_lines(Rest, [{SectionId, Plain} | Acc], NewUsedIds);
        _ ->
            spec_sections_from_lines(Rest, Acc, UsedIds)
    end.

spec_section_lookup(Spec, SectionSlug) ->
    case lists:keyfind(SectionSlug, 1, spec_sections(Spec)) of
        false -> undefined;
        {SectionSlug, Title} -> {SectionSlug, Title}
    end.

spec_section_markdown(Spec, SectionSlug) ->
    case spec_markdown(Spec) of
        Markdown when byte_size(Markdown) > 0 ->
            case spec_section_lookup(Spec, SectionSlug) of
                undefined ->
                    <<>>;
                {_Id, Title} ->
                    case extract_markdown_section(drop_first_h1(Markdown), Title) of
                        {ok, SectionMarkdown} -> SectionMarkdown;
                        false -> <<>>
                    end
            end;
        _ ->
            <<>>
    end.

spec_tx_link_paragraph(Spec) ->
    on_chain_link_paragraph(Spec, <<"View spec transaction">>).

spec_tx_link(Spec, Prefix) ->
    case on_chain_txid(Spec) of
        <<>> -> [];
        TXID ->
            [
                Prefix,
                arweave_tx_link(TXID, <<"View spec transaction">>)
            ]
    end.

on_chain_link_paragraph(Item, Label) ->
    case on_chain_txid(Item) of
        <<>> -> [];
        TXID ->
            [
                <<"<p class=\"hb-docs-chain-link-row\">">>,
                arweave_tx_link(TXID, Label),
                <<"</p>">>
            ]
    end.

arweave_tx_link(TXID, Label) ->
    [
        <<"<a class=\"hb-docs-chain-link\" href=\"">>,
        esc(arweave_tx_href(TXID)),
        <<"\" target=\"_blank\" rel=\"noopener\" title=\"">>,
        esc(TXID),
        <<"\">">>,
        <<"<span class=\"hb-docs-chain-link-icon\" aria-hidden=\"true\">">>,
        phosphor_icon_path_svg(<<"link">>),
        <<"</span><span>">>,
        esc(Label),
        <<"</span></a>">>
    ].

arweave_tx_href(TXID) ->
    <<"https://viewblock.io/arweave/tx/", TXID/binary>>.

on_chain_txid(Item) when is_map(Item) ->
    case on_chain_txid_value(maps:get(<<"txid">>, Item, <<>>)) of
        <<>> ->
            case on_chain_txid_value(maps:get(<<"source">>, Item, <<>>)) of
                <<>> -> on_chain_txid_value(maps:get(<<"source-relative">>, Item, <<>>));
                TXID -> TXID
            end;
        TXID ->
            TXID
    end;
on_chain_txid(Item) ->
    on_chain_txid_value(Item).

on_chain_txid_value(Value) ->
    Bin = trim(hb_util:bin(Value)),
    TXID =
        case Bin of
            <<"weave:", Rest/binary>> -> Rest;
            _ -> Bin
        end,
    case is_arweave_txid(TXID) of
        true -> TXID;
        false -> <<>>
    end.

implementation_source_cell(Impl) ->
    Source = maps:get(<<"source">>, Impl, <<>>),
    case on_chain_txid(Source) of
        <<>> ->
            [<<"<code>">>, esc(Source), <<"</code>">>];
        TXID ->
            arweave_tx_link(TXID, <<"View implementation transaction">>)
    end.

spec_markdown(Spec) ->
    case maps:get(<<"markdown">>, Spec, undefined) of
        Markdown when is_binary(Markdown) ->
            Markdown;
        _ ->
            Source = maps:get(<<"source-path">>, Spec, <<>>),
            case file:read_file(binary_to_list(Source)) of
                {ok, Markdown} -> Markdown;
                {error, _Reason} -> <<>>
            end
    end.

params_table(_DeviceID, _Key, Params) when map_size(Params) =:= 0 ->
    <<"<p>No parameters.</p>">>;
params_table(DeviceID, Key, Params) ->
    [
        <<"<table><thead><tr><th>Name</th><th>Required</th><th>Type</th>"
            "<th>Description</th><th>Example</th></tr></thead><tbody>">>,
        [
            [
                <<"<tr><td><a href=\"">>,
                esc(device_schema_param_path(DeviceID, Key, Name)),
                <<"\"><code>">>, esc(Name),
                <<"</code></a></td><td>">>,
                param_required_cell(DeviceID, Key, Name, Param),
                <<"</td><td>">>, esc(maps:get(<<"type">>, Param, <<>>)),
                <<"</td><td>">>, esc(maps:get(<<"description">>, Param, <<>>)),
                <<"</td><td><code>">>, esc(maps:get(<<"example">>, Param, <<>>)),
                <<"</code></td></tr>">>
            ]
        || {Name, Param} <- lists:sort(maps:to_list(Params))
        ],
        <<"</tbody></table>">>
    ].

recipe_markdown(Recipe) ->
    case maps:get(<<"markdown">>, Recipe, undefined) of
        Markdown when is_binary(Markdown) ->
            Markdown;
        _ ->
            <<>>
    end.

docs_shell_assets() ->
    [
        <<"<script src=\"/docs/assets/prism-core.min.js\"></script>">>,
        <<"<script src=\"/docs/assets/prism-bash.min.js\"></script>">>,
        <<"<script src=\"/docs/assets/prism-json.min.js\"></script>">>,
        <<"<script src=\"/docs/assets/prism-http.min.js\"></script>">>,
        <<"<script src=\"/docs/assets/prism-erlang.min.js\"></script>">>,
        <<"<script src=\"/docs/assets/prism-lua.min.js\"></script>">>,
        <<"<script src=\"/docs/assets/prism-markdown.min.js\"></script>">>,
        <<"<script>">>, docs_page_enhancer_js(), <<"</script>">>,
        <<"<script>">>, docs_page_toc_js(), <<"</script>">>,
        <<"<script>">>, docs_footer_nav_js(), <<"</script>">>,
        <<"<script>">>, docs_mobile_nav_js(), <<"</script>">>,
        <<"<script src=\"/docs/assets/example-runner.js\"></script>">>,
        <<"<script>">>,
        <<"window.addEventListener('DOMContentLoaded',function(){">>,
        <<"if(window.Prism){window.Prism.highlightAll();}">>,
        <<"if(window.HBDocsCodeChrome){window.HBDocsCodeChrome.refresh();}">>,
        <<"if(window.HBExampleRunner){window.HBExampleRunner.refresh();}">>,
        <<"if(window.HBDocsMobileNav){window.HBDocsMobileNav.init();}">>,
        <<"if(window.HBDocsPageToc){window.HBDocsPageToc.init();}">>,
        <<"if(window.HBDocsFooterNav){window.HBDocsFooterNav.init();}">>,
        <<"});">>,
        <<"</script>">>
    ].

docs_page_enhancer_js() ->
    <<"
(function(){
  function addLineNumbers(pre, code) {
    if (pre.dataset.lineNumbers) return;
    var lines = (code.textContent || '').split('\\n');
    if (lines.length && lines[lines.length - 1] === '') lines.pop();
    if (!lines.length) return;
    var gutter = document.createElement('div');
    gutter.className = 'code-line-numbers';
    gutter.setAttribute('aria-hidden', 'true');
    lines.forEach(function (_, i) {
      var span = document.createElement('span');
      span.textContent = String(i + 1);
      gutter.appendChild(span);
    });
    pre.classList.add('has-line-numbers');
    pre.insertBefore(gutter, code);
    pre.dataset.lineNumbers = '1';
  }

	  function addCopyButtons() {
	    document.querySelectorAll('.markdown-section pre').forEach(function (pre) {
      var code = pre.querySelector('code');
      if (!code || pre.dataset.codeChrome) return;
      addLineNumbers(pre, code);
      var lang = (pre.getAttribute('data-lang') || '').trim();
      var header = document.createElement('div');
      header.className = 'code-header';
      var langLabel = document.createElement('span');
      langLabel.className = 'code-header-lang';
      langLabel.textContent = lang || 'code';
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'copy-code-btn';
      btn.setAttribute('aria-label', 'Copy code');
      btn.innerHTML =
        '<span class=\"copy-code-btn-stage\" aria-hidden=\"true\">' +
        '<span class=\"copy-code-btn-icon copy-code-btn-icon-copy\">' +
        '<svg viewBox=\"0 0 256 256\" fill=\"currentColor\"><path d=\"M216,32H88a8,8,0,0,0-8,8V80H40a8,8,0,0,0-8,8V216a8,8,0,0,0,8,8H168a8,8,0,0,0,8-8V176h40a8,8,0,0,0,8-8V40A8,8,0,0,0,216,32ZM160,208H48V96H160Zm48-48H176V88a8,8,0,0,0-8-8H96V48H208Z\"/></svg>' +
        '</span><span class=\"copy-code-btn-icon copy-code-btn-icon-check\">' +
        '<svg viewBox=\"0 0 256 256\" fill=\"currentColor\"><path d=\"M232.49,80.49l-128,128a12,12,0,0,1-17,0l-56-56a12,12,0,1,1,17-17L96,183,215.51,63.51a12,12,0,0,1,17,17Z\"/></svg>' +
        '</span></span>';
      btn.addEventListener('click', function () {
        var text = code.textContent || '';
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(text).then(function () {
            btn.classList.add('copied');
            btn.setAttribute('aria-label', 'Copied');
            setTimeout(function () {
              btn.classList.remove('copied');
              btn.setAttribute('aria-label', 'Copy code');
            }, 1800);
          });
        }
      });
      header.appendChild(langLabel);
      header.appendChild(btn);
      pre.insertBefore(header, pre.firstChild);
      pre.classList.add('has-code-header');
      pre.dataset.codeChrome = '1';
	    });
	  }

	  window.HBDocsCodeChrome = {
	    refresh: function () {
	      addCopyButtons();
	    }
	  };
	})();
">>.

docs_page_toc_js() ->
    <<"
(function () {
  var tocScrollRoot = null;
  var tocScrollHandler = null;
  var tocScrollEndHandler = null;
  var tocResizeHandler = null;
  var tocObserver = null;
  var tocScrollRaf = null;

  function teardownPageTocScroll() {
    if (tocObserver) {
      tocObserver.disconnect();
      tocObserver = null;
    }
    if (tocScrollRaf) {
      window.cancelAnimationFrame(tocScrollRaf);
      tocScrollRaf = null;
    }
    if (tocScrollRoot && tocScrollHandler) {
      tocScrollRoot.removeEventListener('scroll', tocScrollHandler);
    }
    if (tocScrollRoot && tocScrollEndHandler) {
      tocScrollRoot.removeEventListener('scrollend', tocScrollEndHandler);
    }
    if (tocResizeHandler) {
      window.removeEventListener('resize', tocResizeHandler);
    }
    tocScrollRoot = null;
    tocScrollHandler = null;
    tocScrollEndHandler = null;
    tocResizeHandler = null;
  }

  function getScrollEl() {
    var content = document.querySelector('.content');
    if (content) {
      var overflowY = window.getComputedStyle(content).overflowY;
      if (/(auto|scroll|overlay)/.test(overflowY) && content.scrollHeight > content.clientHeight + 1) {
        return content;
      }
    }
    return window;
  }

  function getHeaderHeight() {
    var header = document.getElementById('site-header');
    if (!header || window.getComputedStyle(header).display === 'none') return 0;
    return header.getBoundingClientRect().height;
  }

  function getHeaderScrollOffset() {
    return getHeaderHeight() + 12;
  }

  function getAnchorIdFromHref(href) {
    if (!href) return '';
    var idMatch = href.match(/[?&]id=([^&]+)/);
    if (idMatch) return decodeURIComponent(idMatch[1]);
    var hash = href.split('#').pop() || '';
    return hash.replace(/^\\//, '');
  }

  function slugify(text) {
    return String(text || '')
      .trim()
      .toLowerCase()
      .replace(/[^\\w\\s-]/g, '')
      .replace(/\\s+/g, '-')
      .replace(/-+/g, '-');
  }

  function resolveHeadingLink(heading, usedIds) {
    var anchor = heading.querySelector('a.anchor');
    if (anchor) {
      var anchorId = getAnchorIdFromHref(anchor.getAttribute('href') || '');
      if (anchorId && !heading.id) heading.id = anchorId;
      if (heading.id) {
        usedIds[heading.id] = true;
        return { href: anchor.getAttribute('href') || ('#' + heading.id), id: heading.id };
      }
    }
    if (heading.id) {
      usedIds[heading.id] = true;
      return { href: '#' + heading.id, id: heading.id };
    }
    var base = slugify(heading.textContent || '');
    if (!base) return null;
    var id = base;
    var suffix = 2;
    while (usedIds[id]) {
      id = base + '-' + suffix;
      suffix += 1;
    }
    heading.id = id;
    usedIds[id] = true;
    return { href: '#' + id, id: id };
  }

  function addPageToc() {
    if (!document.body.classList.contains('hb-docs-protocol')) return;
    teardownPageTocScroll();
    document.body.classList.remove('page-toc-active');
    document.querySelector('.page-toc')?.remove();

    var markdownSection = document.querySelector('#main.markdown-section') ||
      document.querySelector('.markdown-section');
    var headings = markdownSection
      ? markdownSection.querySelectorAll('h2, h3')
      : document.querySelectorAll('.markdown-section h2, .markdown-section h3');
    if (!headings.length) return;

    var toc = document.createElement('aside');
    toc.className = 'page-toc';
    toc.setAttribute('aria-label', 'On this page');

    var tocNav = document.createElement('nav');
    tocNav.className = 'page-toc-nav';
    tocNav.setAttribute('aria-label', 'On this page sections');

    var tocProgress = document.createElement('div');
    tocProgress.className = 'page-toc-progress';
    tocProgress.setAttribute('aria-hidden', 'true');
    tocProgress.innerHTML =
      '<span class=\"page-toc-progress-rail\"></span>' +
      '<span class=\"page-toc-progress-indicator\"></span>';

    var tocLinksWrap = document.createElement('div');
    tocLinksWrap.className = 'page-toc-links';

    tocNav.appendChild(tocProgress);
    tocNav.appendChild(tocLinksWrap);
    toc.appendChild(tocNav);

    var tocLinks = [];
    var usedIds = {};
    headings.forEach(function (heading) {
      var linkInfo = resolveHeadingLink(heading, usedIds);
      if (!linkInfo) return;
      var link = document.createElement('a');
      link.href = linkInfo.href;
      link.textContent = (heading.textContent || '').trim();
      link.dataset.level = heading.tagName.toLowerCase();
      tocLinksWrap.appendChild(link);
      tocLinks.push({ link: link, heading: heading });
    });

    if (tocLinks.length <= 1) {
      return;
    }

    document.body.classList.add('page-toc-active');
    document.body.appendChild(toc);

    var scrollRoot = getScrollEl();
    var tocSpySuppressUntil = 0;

    function getScrollTop() {
      return scrollRoot === window ? window.pageYOffset : scrollRoot.scrollTop;
    }

    function getScrollHeight() {
      return scrollRoot === window
        ? Math.max(document.documentElement.scrollHeight, document.body.scrollHeight)
        : scrollRoot.scrollHeight;
    }

    function getViewportHeight() {
      return scrollRoot === window ? window.innerHeight : scrollRoot.clientHeight;
    }

    function getHeadingDocumentY(heading) {
      if (scrollRoot === window) {
        return heading.getBoundingClientRect().top + window.pageYOffset;
      }
      var rootRect = scrollRoot.getBoundingClientRect();
      return heading.getBoundingClientRect().top - rootRect.top + scrollRoot.scrollTop;
    }

    function scrollToY(targetY) {
      var top = Math.max(0, targetY);
      if (scrollRoot === window) {
        window.scrollTo({ top: top, behavior: 'smooth' });
      } else {
        scrollRoot.scrollTo({ top: top, behavior: 'smooth' });
      }
    }

    function scrollToHeading(heading, linkHref) {
      var offset = getHeaderScrollOffset();
      scrollToY(getHeadingDocumentY(heading) - offset);
      tocSpySuppressUntil = Date.now() + 900;
      if (linkHref) {
        history.replaceState(null, '', linkHref);
      }
      window.setTimeout(function () {
        setActiveTocLink(heading.id);
      }, 0);
    }

    function updatePageTocProgress() {
      var indicator = toc.querySelector('.page-toc-progress-indicator');
      var progress = toc.querySelector('.page-toc-progress');
      var active = tocLinksWrap.querySelector('a.active');
      if (!indicator || !progress || !active) {
        if (indicator) indicator.style.opacity = '0';
        return;
      }

      var progressRect = progress.getBoundingClientRect();
      var activeRect = active.getBoundingClientRect();
      var top = activeRect.top - progressRect.top;

      indicator.style.opacity = '1';
      indicator.style.height = activeRect.height + 'px';
      indicator.style.transform = 'translateY(' + top + 'px)';
    }

    function setActiveTocLink(targetId) {
      tocLinks.forEach(function (item) {
        var active = item.heading.id === targetId;
        item.link.classList.toggle('active', active);
      });
      updatePageTocProgress();
    }

    function resolveActiveTocIndex() {
      if (!tocLinks.length) return 0;

      var offset = getHeaderScrollOffset();
      var scrollTop = getScrollTop();
      var maxScroll = Math.max(0, getScrollHeight() - getViewportHeight());

      if (scrollTop <= 1) {
        return 0;
      }
      if (maxScroll > 0 && scrollTop >= maxScroll - 1) {
        return tocLinks.length - 1;
      }

      var anchorY = scrollTop + offset;
      var activeIndex = 0;
      for (var i = 0; i < tocLinks.length; i++) {
        if (getHeadingDocumentY(tocLinks[i].heading) <= anchorY + 1) {
          activeIndex = i;
        }
      }
      return activeIndex;
    }

    function syncActiveTocFromScroll() {
      if (!markdownSection || !tocLinks.length) return;
      if (Date.now() < tocSpySuppressUntil) return;
      var activeIndex = resolveActiveTocIndex();
      setActiveTocLink(tocLinks[activeIndex].heading.id);
    }

    function scheduleTocSync() {
      if (tocScrollRaf) return;
      tocScrollRaf = window.requestAnimationFrame(function () {
        tocScrollRaf = null;
        syncActiveTocFromScroll();
      });
    }

    tocLinksWrap.addEventListener('click', function (event) {
      var link = event.target.closest('a');
      if (!link || !tocLinksWrap.contains(link)) return;
      var linkHref = link.getAttribute('href') || '';
      var targetId = getAnchorIdFromHref(linkHref);
      var item = tocLinks.find(function (entry) {
        return entry.heading.id === targetId;
      });
      if (!item) return;
      event.preventDefault();
      scrollToHeading(item.heading, linkHref);
    });

    tocScrollHandler = scheduleTocSync;
    tocScrollEndHandler = syncActiveTocFromScroll;
    tocScrollRoot = scrollRoot === window ? window : scrollRoot;
    tocScrollRoot.addEventListener('scroll', tocScrollHandler, { passive: true });
    if ('onscrollend' in tocScrollRoot) {
      tocScrollRoot.addEventListener('scrollend', tocScrollEndHandler, { passive: true });
    }
    tocResizeHandler = scheduleTocSync;
    window.addEventListener('resize', tocResizeHandler, { passive: true });

    tocObserver = new IntersectionObserver(
      function () {
        scheduleTocSync();
      },
      {
        root: scrollRoot === window ? null : scrollRoot,
        rootMargin: '-' + getHeaderScrollOffset() + 'px 0px -70% 0px',
        threshold: [0, 1]
      }
    );
    tocLinks.forEach(function (item) {
      tocObserver.observe(item.heading);
    });

    window.requestAnimationFrame(function () {
      window.requestAnimationFrame(syncActiveTocFromScroll);
    });

    toc.__updatePageTocProgress = updatePageTocProgress;
    toc.__syncActiveTocFromScroll = syncActiveTocFromScroll;
  }

  if (!window.__pageTocProgressResizeBound) {
    window.__pageTocProgressResizeBound = true;
    window.addEventListener('resize', function () {
      var tocEl = document.querySelector('.page-toc');
      if (!tocEl) return;
      if (typeof tocEl.__syncActiveTocFromScroll === 'function') {
        tocEl.__syncActiveTocFromScroll();
      } else if (typeof tocEl.__updatePageTocProgress === 'function') {
        tocEl.__updatePageTocProgress();
      }
    }, { passive: true });
  }

  window.HBDocsPageToc = {
    init: addPageToc,
    refresh: addPageToc
  };
})();
">>.

docs_footer_nav_js() ->
    <<"
(function () {
  function normalizePath(path) {
    return String(path || '/')
      .split('?')[0]
      .split('#')[0]
      .replace(/\\/$/, '') || '/';
  }

  function getSidebarLinks() {
    return Array.from(document.querySelectorAll('.sidebar-nav a'))
      .map(function (a) {
        return {
          href: a.getAttribute('href') || '',
          text: (a.textContent || '').trim()
        };
      })
      .filter(function (item) {
        return item.href.charAt(0) === '/' && item.text;
      });
  }

  function getCurrentLinkIndex(links) {
    var current = normalizePath(
      document.body.getAttribute('data-active-path') || window.location.pathname
    );
    return links.findIndex(function (item) {
      return normalizePath(item.href) === current;
    });
  }

  function addFooterNav() {
    var section = document.querySelector('.markdown-section');
    if (!section) return;
    section.querySelector('.docs-footer-nav')?.remove();

    var links = getSidebarLinks();
    var index = getCurrentLinkIndex(links);
    if (index < 0) return;

    var nav = document.createElement('nav');
    nav.className = 'docs-footer-nav';
    nav.setAttribute('aria-label', 'Page navigation');

    if (index > 0) {
      var prev = links[index - 1];
      var prevLink = document.createElement('a');
      prevLink.className = 'docs-footer-link prev';
      prevLink.href = prev.href;
      prevLink.innerHTML =
        '<span class=\"docs-footer-label\">Previous</span>' +
        '<span class=\"docs-footer-title\"></span>';
      prevLink.querySelector('.docs-footer-title').textContent = prev.text;
      nav.appendChild(prevLink);
    } else {
      nav.appendChild(document.createElement('span'));
    }

    if (index < links.length - 1) {
      var next = links[index + 1];
      var nextLink = document.createElement('a');
      nextLink.className = 'docs-footer-link next';
      nextLink.href = next.href;
      nextLink.innerHTML =
        '<span class=\"docs-footer-label\">Next</span>' +
        '<span class=\"docs-footer-title\"></span>';
      nextLink.querySelector('.docs-footer-title').textContent = next.text;
      nav.appendChild(nextLink);
    }

    if (nav.children.length) section.appendChild(nav);
  }

  window.HBDocsFooterNav = {
    init: addFooterNav,
    refresh: addFooterNav
  };
})();
">>.

docs_mobile_nav_js() ->
    <<"
(function () {
  var chevronSvg =
    '<svg class=\"nav-megamenu-chevron\" viewBox=\"0 0 12 12\" fill=\"none\" ' +
    'stroke=\"currentColor\" stroke-width=\"1.5\" stroke-linecap=\"round\" ' +
    'stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"M4.5 2.5 8 6 4.5 9.5\"/></svg>';

  function normalizePath(path) {
    return String(path || '/')
      .split('?')[0]
      .split('#')[0]
      .replace(/\\/$/, '') || '/';
  }

  function isMobileNavHomeDuplicate(href, label) {
    var home = document.querySelector('.mobile-nav-home');
    if (!home) return false;
    var homeHref = normalizePath(home.getAttribute('href') || '');
    var homeLabel = (home.textContent || '').trim();
    return normalizePath(href) === homeHref || (!!label && label === homeLabel);
  }

  function closeMobileNav() {
    var drawer = document.getElementById('mobile-nav-drawer');
    var toggle = document.getElementById('mobile-menu-toggle');
    if (!drawer) return;
    drawer.classList.remove('open');
    drawer.setAttribute('aria-hidden', 'true');
    if (toggle) toggle.setAttribute('aria-expanded', 'false');
    document.body.classList.remove('mobile-nav-open');
    var searchInput = document.getElementById('mobile-nav-search-input');
    if (searchInput) {
      searchInput.value = '';
      filterMobileNav('');
    }
  }

  function openMobileNav() {
    var drawer = document.getElementById('mobile-nav-drawer');
    var toggle = document.getElementById('mobile-menu-toggle');
    if (!drawer) return;
    drawer.classList.add('open');
    drawer.setAttribute('aria-hidden', 'false');
    if (toggle) toggle.setAttribute('aria-expanded', 'true');
    document.body.classList.add('mobile-nav-open');
    drawer.querySelectorAll('.mobile-nav-section.active').forEach(function (sectionEl) {
      sectionEl.classList.add('open');
      var trigger = sectionEl.querySelector('.mobile-nav-section-trigger');
      if (trigger) trigger.setAttribute('aria-expanded', 'true');
    });
  }

  function syncLayoutForViewport() {
    if (window.matchMedia('(max-width: 1000px)').matches) {
      document.body.classList.add('close');
    } else {
      document.body.classList.remove('close');
      closeMobileNav();
    }
  }

  function setActiveNav(path) {
    var normalized = normalizePath(path);
    var home = document.querySelector('.mobile-nav-home');
    if (home) {
      home.classList.toggle('active', normalized === '/docs');
    }
    document.querySelectorAll('.mobile-nav-tab').forEach(function (tab) {
      var href = tab.getAttribute('href') || '';
      tab.classList.toggle('active', normalizePath(href) === normalized);
    });
    document.querySelectorAll('.mobile-nav-section').forEach(function (sectionEl) {
      var active = false;
      sectionEl.querySelectorAll('a[href]').forEach(function (link) {
        if (normalizePath(link.getAttribute('href')) === normalized) active = true;
      });
      sectionEl.classList.toggle('active', active);
    });
    document.querySelectorAll('.sidebar-nav a[href]').forEach(function (link) {
      var li = link.parentElement;
      if (!li || li.classList.contains('sidebar-viewing-context')) return;
      li.classList.toggle('active', normalizePath(link.getAttribute('href')) === normalized);
    });
  }

  function textMatchesQuery(text, query) {
    return String(text || '').trim().toLowerCase().indexOf(query) !== -1;
  }

  function filterMobileNav(query) {
    var q = String(query || '').trim().toLowerCase();
    var mobileNavList = document.getElementById('mobile-nav-list');
    var mobileNavTabs = document.getElementById('mobile-nav-tabs');
    if (!mobileNavList) return;

    function setHidden(el, hidden) {
      if (!el) return;
      el.classList.toggle('mobile-nav-filter-hidden', hidden);
    }

    if (mobileNavTabs) {
      mobileNavTabs.querySelectorAll('.mobile-nav-tab').forEach(function (tab) {
        var label = (tab.textContent || '').trim();
        setHidden(tab, q && !textMatchesQuery(label, q));
      });
      setHidden(
        mobileNavTabs.querySelector('.mobile-nav-home'),
        q && !textMatchesQuery((mobileNavTabs.querySelector('.mobile-nav-home')?.textContent || ''), q)
      );
    }

    mobileNavList.querySelectorAll('.mobile-nav-section').forEach(function (sectionEl) {
      var sectionLabel = (
        sectionEl.querySelector('.mobile-nav-section-trigger span')?.textContent || ''
      ).trim();
      var sectionMatches = q && textMatchesQuery(sectionLabel, q);
      var sectionVisible = !q;

      sectionEl.querySelectorAll('.mobile-nav-link').forEach(function (link) {
        var linkMatches = !q || sectionMatches || textMatchesQuery(link.textContent, q);
        var sublinks = link.nextElementSibling;
        var hasVisibleSublink = false;

        if (sublinks && sublinks.classList.contains('mobile-nav-sublinks')) {
          sublinks.querySelectorAll('.mobile-nav-sublink').forEach(function (sublink) {
            var sublinkMatches = !q || sectionMatches || textMatchesQuery(sublink.textContent, q);
            setHidden(sublink, !sublinkMatches);
            if (sublinkMatches) hasVisibleSublink = true;
          });
          setHidden(sublinks, q && !sectionMatches && !hasVisibleSublink && !linkMatches);
        }

        var visible = linkMatches || hasVisibleSublink;
        setHidden(link, q && !visible);
        if (visible) sectionVisible = true;
      });

      setHidden(sectionEl, q && !sectionVisible);

      if (q && sectionVisible) {
        sectionEl.classList.add('open');
        var trigger = sectionEl.querySelector('.mobile-nav-section-trigger');
        if (trigger) trigger.setAttribute('aria-expanded', 'true');
      } else if (!q) {
        var isActive = sectionEl.classList.contains('active');
        sectionEl.classList.toggle('open', isActive);
        var sectionTrigger = sectionEl.querySelector('.mobile-nav-section-trigger');
        if (sectionTrigger) sectionTrigger.setAttribute('aria-expanded', String(isActive));
      }
    });
  }

  function buildMobileNavFromSidebar() {
    var sidebarNav = document.querySelector('.sidebar-nav > ul');
    var mobileNavList = document.getElementById('mobile-nav-list');
    var mobileNavTabs = document.getElementById('mobile-nav-tabs');
    if (!sidebarNav || !mobileNavList || !mobileNavTabs) return;

    mobileNavList.innerHTML = '';
    mobileNavTabs.querySelectorAll('.mobile-nav-tab').forEach(function (el) {
      el.remove();
    });

    Array.prototype.forEach.call(sidebarNav.children, function (li, index) {
      if (li.tagName !== 'LI') return;
      if (li.classList.contains('sidebar-viewing-context')) {
        var deviceLink = li.querySelector('.sidebar-viewing-device');
        if (deviceLink) {
          var deviceHref = deviceLink.getAttribute('href') || '#';
          var deviceLabel = (deviceLink.textContent || '').trim();
          var deviceTab = document.createElement('a');
          deviceTab.className = 'mobile-nav-tab';
          deviceTab.href = deviceHref;
          deviceTab.setAttribute('data-section', 'viewing-context');
          deviceTab.textContent = deviceLabel;
          deviceTab.addEventListener('click', closeMobileNav);
          mobileNavTabs.appendChild(deviceTab);
        }
        return;
      }
      var sectionLabelEl = li.querySelector(':scope > p');
      var directLink = li.querySelector(':scope > a');
      var subUl = li.querySelector(':scope > ul');

      if (sectionLabelEl && subUl) {
        var label = (sectionLabelEl.textContent || '').trim();
        var sectionId = label.toLowerCase().replace(/[^a-z0-9]+/g, '-');
        var firstLink = subUl.querySelector('a[href]');
        var sectionHome = firstLink ? firstLink.getAttribute('href') : '/docs';

        if (!isMobileNavHomeDuplicate(sectionHome, label)) {
          var tab = document.createElement('a');
          tab.className = 'mobile-nav-tab';
          tab.href = sectionHome;
          tab.setAttribute('data-section', sectionId);
          tab.textContent = label;
          tab.addEventListener('click', closeMobileNav);
          mobileNavTabs.appendChild(tab);
        }

        var block = document.createElement('div');
        block.className = 'mobile-nav-section';
        if (li.classList.contains('sidebar-flat-links')) {
          block.classList.add('mobile-nav-flat-links');
        }
        block.setAttribute('data-section', sectionId);

        var trigger = document.createElement('button');
        trigger.type = 'button';
        trigger.className = 'mobile-nav-section-trigger';
        trigger.setAttribute('aria-expanded', 'false');
        trigger.innerHTML = '<span>' + label + '</span>' + chevronSvg;

        var panel = document.createElement('div');
        panel.className = 'mobile-nav-section-panel';

        subUl.querySelectorAll(':scope > li').forEach(function (item, itemIndex) {
          var link = item.querySelector(':scope > a');
          if (!link) return;
          var mobileLink = document.createElement('a');
          mobileLink.className = (itemIndex === 0 || li.classList.contains('sidebar-flat-links'))
            ? 'mobile-nav-link'
            : 'mobile-nav-link mobile-nav-link-nested';
          mobileLink.href = link.getAttribute('href') || '#';
          mobileLink.textContent = (link.textContent || '').trim();
          mobileLink.addEventListener('click', closeMobileNav);
          panel.appendChild(mobileLink);

          var nested = item.querySelector(':scope > ul');
          if (nested) {
            var sublinks = document.createElement('div');
            sublinks.className = 'mobile-nav-sublinks';
            nested.querySelectorAll('a[href]').forEach(function (childLink) {
              var child = document.createElement('a');
              child.className = 'mobile-nav-sublink';
              child.href = childLink.getAttribute('href') || '#';
              child.textContent = (childLink.textContent || '').trim();
              child.addEventListener('click', closeMobileNav);
              sublinks.appendChild(child);
            });
            panel.appendChild(sublinks);
          }
        });

        trigger.addEventListener('click', function () {
          var isOpen = block.classList.contains('open');
          mobileNavList.querySelectorAll('.mobile-nav-section.open').forEach(function (other) {
            if (other !== block) {
              other.classList.remove('open');
              var otherTrigger = other.querySelector('.mobile-nav-section-trigger');
              if (otherTrigger) otherTrigger.setAttribute('aria-expanded', 'false');
            }
          });
          block.classList.toggle('open', !isOpen);
          trigger.setAttribute('aria-expanded', String(!isOpen));
        });

        block.appendChild(trigger);
        block.appendChild(panel);
        mobileNavList.appendChild(block);
        return;
      }

      if (directLink) {
        var linkHref = directLink.getAttribute('href') || '#';
        var linkLabel = (directLink.textContent || '').trim();
        if (!isMobileNavHomeDuplicate(linkHref, linkLabel)) {
          var tabLink = document.createElement('a');
          tabLink.className = 'mobile-nav-tab';
          tabLink.href = linkHref;
          tabLink.setAttribute('data-section', 'link-' + index);
          tabLink.textContent = linkLabel;
          tabLink.addEventListener('click', closeMobileNav);
          mobileNavTabs.appendChild(tabLink);
        }
      }
    });
    var searchInput = document.getElementById('mobile-nav-search-input');
    filterMobileNav(searchInput ? searchInput.value : '');
  }

  function bindMobileNavSearch() {
    var searchInput = document.getElementById('mobile-nav-search-input');
    if (!searchInput || searchInput.__bound) return;
    searchInput.__bound = true;
    searchInput.addEventListener('input', function () {
      filterMobileNav(searchInput.value);
    });
  }

  function bindMobileChrome() {
    var mobileMenuToggle = document.getElementById('mobile-menu-toggle');
    var mobileNavDrawer = document.getElementById('mobile-nav-drawer');
    var navMedia = window.matchMedia('(max-width: 1000px)');

    mobileMenuToggle?.addEventListener('click', function () {
      if (mobileNavDrawer?.classList.contains('open')) closeMobileNav();
      else openMobileNav();
    });

    mobileNavDrawer?.querySelectorAll('[data-mobile-nav-close]').forEach(function (el) {
      el.addEventListener('click', closeMobileNav);
    });

    document.addEventListener('keydown', function (e) {
      if (e.key !== 'Escape') return;
      closeMobileNav();
    });

    navMedia.addEventListener('change', syncLayoutForViewport);
    window.addEventListener('resize', syncLayoutForViewport, { passive: true });
  }

  window.HBDocsMobileNav = {
    init: function () {
      buildMobileNavFromSidebar();
      bindMobileNavSearch();
      bindMobileChrome();
      syncLayoutForViewport();
      setActiveNav(document.body.getAttribute('data-active-path') || window.location.pathname);
      document.querySelector('.mobile-nav-home')?.addEventListener('click', closeMobileNav);
      document.querySelector('.site-header-home')?.addEventListener('click', closeMobileNav);
    }
  };
})();
">>.

docs_asset_response(Parts) ->
    case valid_asset_parts(Parts) of
        true ->
            Path = docs_asset_path(Parts),
            case file:read_file(Path) of
                {ok, Body0} ->
                    Body = docs_asset_body(Parts, Body0),
                    {ok, #{
                        <<"status">> => 200,
                        <<"content-type">> => docs_asset_content_type(Parts),
                        <<"body">> => Body
                    }};
                {error, _Reason} ->
                    {ok, not_found_response()}
            end;
        false ->
            {ok, not_found_response()}
    end.

valid_asset_parts([]) ->
    false;
valid_asset_parts(Parts) ->
    lists:all(fun valid_asset_part/1, Parts).

valid_asset_part(Part) when is_binary(Part) ->
    Part =/= <<>> andalso
        binary:match(Part, <<"/">>) =:= nomatch andalso
        binary:match(Part, <<"..">>) =:= nomatch;
valid_asset_part(_) ->
    false.

docs_asset_path([<<"prism-core.min.js">>]) ->
    filename:join([device_docs_root(), "node_modules", "prismjs", "components", "prism-core.min.js"]);
docs_asset_path(Parts) ->
    filename:join([device_docs_root(), "dist", "assets" | [binary_to_list(Part) || Part <- Parts]]).

docs_asset_body([<<"example-runner.js">>], Body) ->
    binary:replace(
        Body,
        <<"const DEFAULT_NODE = 'http://localhost:8734';">>,
        <<"const DEFAULT_NODE = window.location.origin;">>
    );
docs_asset_body(_Parts, Body) ->
    Body.

docs_asset_content_type(Parts) ->
    Name = lists:last(Parts),
    case filename:extension(binary_to_list(Name)) of
        ".css" -> <<"text/css; charset=utf-8">>;
        ".js" -> <<"text/javascript; charset=utf-8">>;
        ".json" -> <<"application/json">>;
        ".woff2" -> <<"font/woff2">>;
        ".png" -> <<"image/png">>;
        ".svg" -> <<"image/svg+xml">>;
        ".ico" -> <<"image/x-icon">>;
        ".mp4" -> <<"video/mp4">>;
        _ -> <<"application/octet-stream">>
    end.

render_markdown(Markdown) ->
    render_markdown(Markdown, #{}).

render_markdown(Markdown, Opts) ->
    Lines = binary:split(Markdown, <<"\n">>, [global]),
    iolist_to_binary(render_markdown_lines(Lines, [], [], false, #{}, Opts)).

render_markdown_with_heading_ids(Markdown) ->
    render_markdown_with_heading_ids(Markdown, #{}).

render_markdown_with_heading_ids(Markdown, Opts) ->
    Lines = binary:split(Markdown, <<"\n">>, [global]),
    iolist_to_binary(render_markdown_lines(Lines, [], [], true, #{}, Opts)).

render_markdown_lines([], Para, Acc, _AddHeadingIds, _UsedIds, Opts) ->
    lists:reverse([flush_paragraph(Para, Opts) | Acc]);
render_markdown_lines([Line | Rest], Para, Acc, AddHeadingIds, UsedIds, Opts) ->
    Trim = trim(Line),
    case fence_language(Trim) of
        {ok, Lang} ->
            {CodeLines, After} = take_code_block(Rest, []),
            Block = render_code_block(Lang, lists:reverse(CodeLines)),
            render_markdown_lines(After, [], [Block, flush_paragraph(Para, Opts) | Acc], AddHeadingIds, UsedIds, Opts);
        false ->
            case table_block(Trim, Rest, Opts) of
                {ok, Table, AfterTable} ->
                    render_markdown_lines(AfterTable, [], [Table, flush_paragraph(Para, Opts) | Acc], AddHeadingIds, UsedIds, Opts);
                false ->
                    case {Trim, raw_html_line(Trim), heading(Trim), bullet_text(Trim), numbered_text(Trim)} of
                        {<<>>, _, _, _, _} ->
                            render_markdown_lines(Rest, [], [flush_paragraph(Para, Opts) | Acc], AddHeadingIds, UsedIds, Opts);
                        {_, {ok, Html}, _, _, _} ->
                            render_markdown_lines(Rest, [], [Html, flush_paragraph(Para, Opts) | Acc], AddHeadingIds, UsedIds, Opts);
                        {_, _, {Level, Text}, _, _} ->
                            {H, NewUsedIds} = render_heading(Level, Text, AddHeadingIds, UsedIds, Opts),
                            render_markdown_lines(Rest, [], [H, flush_paragraph(Para, Opts) | Acc], AddHeadingIds, NewUsedIds, Opts);
                        {_, _, _, {ok, Text}, _} ->
                            {Items, AfterList} = take_list_block(Rest, unordered, [Text], []),
                            List = render_list(<<"ul">>, Items, Opts),
                            render_markdown_lines(AfterList, [], [List, flush_paragraph(Para, Opts) | Acc], AddHeadingIds, UsedIds, Opts);
                        {_, _, _, _, {ok, Text}} ->
                            {Items, AfterList} = take_list_block(Rest, ordered, [Text], []),
                            List = render_list(<<"ol">>, Items, Opts),
                            render_markdown_lines(AfterList, [], [List, flush_paragraph(Para, Opts) | Acc], AddHeadingIds, UsedIds, Opts);
                        _ ->
                            render_markdown_lines(Rest, [Trim | Para], Acc, AddHeadingIds, UsedIds, Opts)
                    end
            end
    end.

take_code_block([], Acc) ->
    {Acc, []};
take_code_block([Line | Rest], Acc) ->
    case is_fence(Line) of
        true -> {Acc, Rest};
        false -> take_code_block(Rest, [Line | Acc])
    end.

flush_paragraph([], _Opts) ->
    [];
flush_paragraph(Lines, Opts) ->
    Text = iolist_to_binary(lists:join(<<" ">>, lists:reverse(Lines))),
    [<<"<p>">>, render_inline(Text, Opts), <<"</p>">>].

render_heading(Level0, Text, AddHeadingIds, UsedIds, Opts) ->
    Level = max(3, min(6, Level0 + 2)),
    Tag = integer_to_binary(Level),
    DisplayText = heading_display_text(Text, Opts),
    case AddHeadingIds =:= true andalso Level0 =:= 2 of
        true ->
            Plain = strip_inline_markdown(Text),
            {HeadingId, NewUsedIds} = unique_heading_slug(Plain, UsedIds),
            Heading = [
                <<"<h">>, Tag, <<" id=\"">>, esc(HeadingId), <<"\">">>,
                render_inline(DisplayText, Opts),
                <<"</h">>, Tag, <<">">>
            ],
            {Heading, NewUsedIds};
        false ->
            {[<<"<h">>, Tag, <<">">>, render_inline(DisplayText, Opts), <<"</h">>, Tag, <<">">>], UsedIds}
    end.

heading_display_text(Text, Opts) ->
    case maps:get(<<"strip-numbered-headings">>, Opts, false) of
        true ->
            spec_section_nav_label(strip_inline_markdown(Text));
        false ->
            Text
    end.

unique_heading_slug(Text, UsedIds) ->
    unique_heading_slug(heading_slug_base(Text), UsedIds, 2).

unique_heading_slug(Base, UsedIds, _Suffix) when Base =:= <<>> ->
    {Base, UsedIds};
unique_heading_slug(Base, UsedIds, Suffix) ->
    Candidate =
        case Suffix of
            2 -> Base;
            N -> <<Base/binary, "-", (integer_to_binary(N))/binary>>
        end,
    case maps:is_key(Candidate, UsedIds) of
        true ->
            unique_heading_slug(Base, UsedIds, Suffix + 1);
        false ->
            {Candidate, maps:put(Candidate, true, UsedIds)}
    end.

heading_slug_base(Text) ->
    collapse_hyphens(
        slug_spaces_to_hyphens(
            list_to_binary(slug_keep_chars(unicode:characters_to_list(hb_util:to_lower(hb_util:bin(Text))), []))
        )
    ).

slug_keep_chars([], Acc) ->
    lists:reverse(Acc);
slug_keep_chars([C | Rest], Acc)
    when (C >= $a andalso C =< $z) orelse (C >= $0 andalso C =< $9) orelse
        C =:= $_ orelse C =:= $- orelse C =:= $\s ->
    slug_keep_chars(Rest, [C | Acc]);
slug_keep_chars([_ | Rest], Acc) ->
    slug_keep_chars(Rest, Acc).

slug_spaces_to_hyphens(Bin) ->
    slug_spaces_to_hyphens(Bin, <<>>).

slug_spaces_to_hyphens(<<>>, Acc) ->
    Acc;
slug_spaces_to_hyphens(<<" ", Rest/binary>>, Acc) ->
    slug_spaces_to_hyphens(Rest, <<Acc/binary, "-">>);
slug_spaces_to_hyphens(<<C, Rest/binary>>, Acc) ->
    slug_spaces_to_hyphens(Rest, <<Acc/binary, C>>).

collapse_hyphens(Bin) ->
    collapse_hyphen_runs(Bin).

collapse_hyphen_runs(Bin) ->
    case binary:match(Bin, <<"--">>) of
        nomatch -> Bin;
        _ -> collapse_hyphen_runs(binary:replace(Bin, <<"--">>, <<"-">>, [global]))
    end.

render_code_block(Lang, Lines) ->
    NormLang = normalize_lang(Lang),
    Text = join_lines(Lines),
    [
        <<"<pre class=\"language-">>, esc(NormLang), <<"\" data-lang=\"">>,
        esc(NormLang), <<"\"><code class=\"language-">>,
        esc(NormLang), <<"\">">>, esc(Text), <<"</code></pre>">>
    ].

table_block(Header, [Separator | Rest], Opts) ->
    TrimSeparator = trim(Separator),
    case is_table_row(Header) andalso is_table_separator(TrimSeparator) of
        true ->
            {Rows, After} = take_table_rows(Rest, []),
            {ok, render_table([Header | Rows], Opts), After};
        false ->
            false
    end;
table_block(_Header, _Rest, _Opts) ->
    false.

is_table_row(Line) ->
    Line =/= <<>> andalso binary:match(Line, <<"|">>) =/= nomatch.

is_table_separator(Line) ->
    Cells = parse_table_row(Line),
    Cells =/= [] andalso lists:all(fun is_table_separator_cell/1, Cells).

is_table_separator_cell(Cell) ->
    Trimmed = trim(Cell),
    HasDash = binary:match(Trimmed, <<"-">>) =/= nomatch,
    NoColons = binary:replace(Trimmed, <<":">>, <<>>, [global]),
    NoDashes = binary:replace(NoColons, <<"-">>, <<>>, [global]),
    HasDash andalso trim(NoDashes) =:= <<>>.

take_table_rows([Line | Rest], Acc) ->
    Trim = trim(Line),
    case is_table_row(Trim) andalso Trim =/= <<>> of
        true -> take_table_rows(Rest, [Trim | Acc]);
        false -> {lists:reverse(Acc), [Line | Rest]}
    end;
take_table_rows([], Acc) ->
    {lists:reverse(Acc), []}.

render_table([Header | Rows], Opts) ->
    HeaderCells = parse_table_row(Header),
    [
        <<"<table><thead>">>,
        render_table_row(<<"th">>, HeaderCells, Opts),
        <<"</thead><tbody>">>,
        [render_table_row(<<"td">>, parse_table_row(Row), Opts) || Row <- Rows],
        <<"</tbody></table>">>
    ].

render_table_row(Tag, Cells, Opts) ->
    [
        <<"<tr>">>,
        [[<<"<">>, Tag, <<">">>, render_inline(Cell, Opts), <<"</">>, Tag, <<">">>] || Cell <- Cells],
        <<"</tr>">>
    ].

parse_table_row(Row) ->
    Trimmed = trim(Row),
    WithoutLeading =
        case starts_with(Trimmed, <<"|">>) of
            true -> binary:part(Trimmed, 1, byte_size(Trimmed) - 1);
            false -> Trimmed
        end,
    WithoutOuter =
        case ends_with(WithoutLeading, <<"|">>) of
            true -> binary:part(WithoutLeading, 0, byte_size(WithoutLeading) - 1);
            false -> WithoutLeading
        end,
    [trim(Cell) || Cell <- binary:split(WithoutOuter, <<"|">>, [global])].

render_inline(Text) ->
    render_inline(Text, #{}).

render_inline(Text, Opts) ->
    render_inline(Text, [], Opts).

render_inline(<<>>, Acc, _Opts) ->
    lists:reverse(Acc);
render_inline(Text, Acc, Opts) ->
    case inline_markers(Text) of
        [] ->
            lists:reverse([esc(Text) | Acc]);
        [{Pos, Kind, Payload} | _] ->
            Prefix = binary:part(Text, 0, Pos),
            case Kind of
                link ->
                    {Label, Url, TotalLen} = Payload,
                    RestPos = Pos + TotalLen,
                    Rest = binary:part(Text, RestPos, byte_size(Text) - RestPos),
                    Node = render_markdown_link(Label, Url, Opts),
                    render_inline(Rest, [Node, esc(Prefix) | Acc], Opts);
                code ->
                    Marker = Payload,
                    AfterStartPos = Pos + byte_size(Marker),
                    AfterStart = binary:part(Text, AfterStartPos, byte_size(Text) - AfterStartPos),
                    case binary:match(AfterStart, Marker) of
                        {EndPos, _Len} ->
                            Inner = binary:part(AfterStart, 0, EndPos),
                            RestPos = EndPos + byte_size(Marker),
                            Rest = binary:part(AfterStart, RestPos, byte_size(AfterStart) - RestPos),
                            Node = [<<"<code>">>, esc(Inner), <<"</code>">>],
                            render_inline(Rest, [Node, esc(Prefix) | Acc], Opts);
                        nomatch ->
                            render_inline(AfterStart, [esc(Marker), esc(Prefix) | Acc], Opts)
                    end;
                strong ->
                    Marker = Payload,
                    AfterStartPos = Pos + byte_size(Marker),
                    AfterStart = binary:part(Text, AfterStartPos, byte_size(Text) - AfterStartPos),
                    case binary:match(AfterStart, Marker) of
                        {EndPos, _Len} ->
                            Inner = binary:part(AfterStart, 0, EndPos),
                            RestPos = EndPos + byte_size(Marker),
                            Rest = binary:part(AfterStart, RestPos, byte_size(AfterStart) - RestPos),
                            Node = [<<"<strong>">>, render_inline(Inner, Opts), <<"</strong>">>],
                            render_inline(Rest, [Node, esc(Prefix) | Acc], Opts);
                        nomatch ->
                            render_inline(AfterStart, [esc(Marker), esc(Prefix) | Acc], Opts)
                    end
            end
    end.

render_markdown_link(Label, Url, Opts) ->
    case resolve_markdown_link(Label, Url, Opts) of
        {link, Href} ->
            [
                <<"<a href=\"">>, esc(Href), <<"\">">>,
                render_inline(Label, Opts),
                <<"</a>">>
            ];
        {code, Text} ->
            [<<"<code>">>, esc(Text), <<"</code>">>]
    end.

resolve_markdown_link(Label, Href, Opts) ->
    Trim = trim(hb_util:bin(Href)),
    case Trim of
        <<"#", _/binary>> ->
            {link, Trim};
        _ ->
            case is_external_href(Trim) of
                true ->
                    {link, Trim};
                false ->
                    RelPath =
                        case maps:get(<<"source-relative">>, Opts, undefined) of
                            undefined ->
                                resolve_boilerplate_relpath_from_path(Trim);
                            SourceRel ->
                                resolve_doc_relpath(Trim, SourceRel)
                        end,
                    boilerplate_link_target(Label, RelPath)
            end
    end.

is_external_href(<<"http://", _/binary>>) ->
    true;
is_external_href(<<"https://", _/binary>>) ->
    true;
is_external_href(<<"mailto:", _/binary>>) ->
    true;
is_external_href(_) ->
    false.

resolve_boilerplate_relpath_from_path(<<"/", Rest/binary>>) ->
    normalize_doc_relpath(<<"docs/", Rest/binary>>);
resolve_boilerplate_relpath_from_path(Path) ->
    normalize_doc_relpath(<<"docs/", Path/binary>>).

boilerplate_link_target(Label, RelPathWithFragment) ->
    {RelPath, Fragment} = split_href_fragment(RelPathWithFragment),
    case device_id_from_doc_relpath(RelPath) of
        {ok, DeviceID} ->
            case supported_device(DeviceID) of
                true -> {link, append_href_fragment(device_info_path(DeviceID), Fragment)};
                false -> {code, device_marked_id(DeviceID)}
            end;
        false ->
            case lists:keyfind(RelPath, 2, boilerplate_pages()) of
                false -> {code, link_code_label(Label)};
                _Page -> {link, append_href_fragment(boilerplate_href(RelPath), Fragment)}
            end
    end.

split_href_fragment(Href) ->
    case binary:split(Href, <<"#">>) of
        [Path, Fragment] -> {Path, <<"#", Fragment/binary>>};
        [Path] -> {Path, <<>>}
    end.

append_href_fragment(Href, <<>>) ->
    Href;
append_href_fragment(Href, Fragment) ->
    <<Href/binary, Fragment/binary>>.

device_id_from_doc_relpath(<<"docs/devices/", Rest/binary>>) ->
    File = lists:last(binary:split(Rest, <<"/">>, [global])),
    Slug = strip_suffix(File, <<".md">>),
    case binary:split(Slug, <<"-at-">>) of
        [Name, VersionSlug] when Name =/= <<>>, VersionSlug =/= <<>> ->
            Version = binary:replace(VersionSlug, <<"-">>, <<".">>, [global]),
            {ok, <<Name/binary, "@", Version/binary>>};
        _ ->
            false
    end;
device_id_from_doc_relpath(_) ->
    false.

link_code_label(Label) ->
    case trim(strip_inline_markdown(Label)) of
        <<>> -> <<"reference">>;
        Text -> Text
    end.

resolve_doc_relpath(Href, SourceRel) ->
    Trim = trim(hb_util:bin(Href)),
    case Trim of
        <<"/", Rest/binary>> ->
            normalize_doc_relpath(<<"docs/", Rest/binary>>);
        _ ->
            normalize_doc_relpath(join_doc_paths(doc_dirname(SourceRel), Trim))
    end.

doc_dirname(SourceRel) ->
    case binary:split(SourceRel, <<"/">>, [global]) of
        [<<"docs">>] ->
            <<"docs">>;
        [<<"docs">> | Parts] ->
            case Parts of
                [] ->
                    <<"docs">>;
                [_File] ->
                    <<"docs">>;
                _ ->
                    DirParts = lists:droplast(Parts),
                    iolist_to_binary([<<"docs/">>, lists:join(<<"/">>, DirParts)])
            end;
        _ ->
            <<"docs">>
    end.

join_doc_paths(Dir, Href) ->
    iolist_to_binary([Dir, <<"/">>, Href]).

normalize_doc_relpath(Path) ->
    Parts = binary:split(Path, <<"/">>, [global]),
    iolist_to_binary(lists:join(<<"/">>, normalize_doc_parts(Parts, []))).

normalize_doc_parts([], Acc) ->
    lists:reverse(Acc);
normalize_doc_parts([<<>> | Rest], Acc) ->
    normalize_doc_parts(Rest, Acc);
normalize_doc_parts([<<"..">> | Rest], [_ | Acc]) ->
    normalize_doc_parts(Rest, Acc);
normalize_doc_parts([<<"..">> | Rest], Acc) ->
    normalize_doc_parts(Rest, Acc);
normalize_doc_parts([Part | Rest], Acc) ->
    normalize_doc_parts(Rest, [Part | Acc]).

inline_markers(Text) ->
    lists:keysort(
        1,
        marker_matches(Text, <<"**">>, strong) ++
            marker_matches(Text, <<"`">>, code) ++
            link_marker_matches(Text)
    ).

link_marker_matches(Text) ->
    case parse_markdown_link(Text) of
        {ok, Pos, Label, Url, TotalLen} ->
            [{Pos, link, {Label, Url, TotalLen}}];
        error ->
            []
    end.

parse_markdown_link(Text) ->
    case binary:match(Text, <<"[">>) of
        {Pos, _} ->
            AfterOpen = binary:part(Text, Pos + 1, byte_size(Text) - Pos - 1),
            case binary:match(AfterOpen, <<"](">>) of
                {LabelEnd, _} ->
                    Label = binary:part(AfterOpen, 0, LabelEnd),
                    AfterParen = binary:part(AfterOpen, LabelEnd + 2, byte_size(AfterOpen) - LabelEnd - 2),
                    case binary:match(AfterParen, <<")">>) of
                        {UrlEnd, _} ->
                            Url = binary:part(AfterParen, 0, UrlEnd),
                            TotalLen = 1 + LabelEnd + 2 + UrlEnd + 1,
                            {ok, Pos, Label, Url, TotalLen};
                        nomatch ->
                            error
                    end;
                nomatch ->
                    error
            end;
        nomatch ->
            error
    end.

marker_matches(Text, Marker, Kind) ->
    case binary:match(Text, Marker) of
        {Pos, _Len} -> [{Pos, Kind, Marker}];
        nomatch -> []
    end.

drop_first_h1(Markdown) ->
    Lines = binary:split(Markdown, <<"\n">>, [global]),
    iolist_to_binary(lists:join(<<"\n">>, drop_first_h1_lines(Lines))).

drop_first_h1_lines([]) ->
    [];
drop_first_h1_lines([Line | Rest]) ->
    case heading(trim(Line)) of
        {1, _Text} -> Rest;
        _ -> [Line | Rest]
    end.

markdown_title(Markdown, Fallback) ->
    Lines = binary:split(Markdown, <<"\n">>, [global]),
    case [Text || Line <- Lines, {1, Text} <- [heading(trim(Line))]] of
        [Title | _] -> Title;
        [] -> Fallback
    end.

markdown_summary(Markdown) ->
    Lines = binary:split(drop_first_h1(Markdown), <<"\n">>, [global]),
    summary_from_lines(Lines).

-define(CARD_SUMMARY_MAX, 120).
-define(RECIPE_CARD_SUMMARY_MAX, 80).

card_summary(Summary) ->
    Text = trim(hb_util:bin(Summary)),
    truncate_card_summary(first_sentence(Text), ?CARD_SUMMARY_MAX).

recipe_card_summary(Recipe) ->
    Text =
        case maps:get(<<"tagline">>, Recipe, undefined) of
            undefined ->
                first_clause(trim(hb_util:bin(maps:get(<<"summary">>, Recipe, <<>>))));
            Tagline ->
                trim(hb_util:bin(Tagline))
        end,
    truncate_card_summary(Text, ?RECIPE_CARD_SUMMARY_MAX).

recipe_card_meta(Recipe) ->
    case maps:get(<<"runnable-block-count">>, Recipe, 0) of
        0 ->
            <<>>;
        Count ->
            [
                <<"<small class=\"hb-docs-recipe-card-meta\">">>,
                esc(hb_util:bin(Count)),
                <<" runnable</small>">>
            ]
    end.

first_clause(<<>>) ->
    <<>>;
first_clause(Text) ->
    case earliest_clause_split(Text) of
        undefined ->
            first_sentence(Text);
        Pos ->
            binary:part(Text, 0, Pos)
    end.

earliest_clause_split(Text) ->
    Splits = [
        clause_split(Text, <<". ">>),
        clause_split(Text, <<", ">>),
        clause_split(Text, <<" and ">>)
    ],
    case [Pos || Pos <- Splits, Pos =/= undefined] of
        [] -> undefined;
        Positions -> lists:min(Positions)
    end.

clause_split(Text, Sep) ->
    case binary:match(Text, Sep) of
        {Pos, _} when Pos > 0 -> Pos;
        _ -> undefined
    end.

first_sentence(<<>>) ->
    <<>>;
first_sentence(Text) ->
    case binary:match(Text, <<". ">>) of
        {Pos, _} ->
            binary:part(Text, 0, Pos + 1);
        nomatch ->
            Text
    end.

truncate_card_summary(Text, Max) when byte_size(Text) =< Max ->
    Text;
truncate_card_summary(Text, Max) ->
    <<(binary:part(Text, 0, Max))/binary, "...">>.

summary_from_lines([]) ->
    <<>>;
summary_from_lines([Line | Rest]) ->
    Trim = trim(Line),
    case summary_line_usable(Trim) of
        false ->
            summary_from_lines(Rest);
        true ->
            case fence_language(Trim) of
                {ok, _Lang} ->
                    {_CodeLines, AfterFence} = take_code_block(Rest, []),
                    summary_from_lines(AfterFence);
                false ->
                    case heading(Trim) of
                        false -> strip_inline_markdown(Trim);
                        _ -> summary_from_lines(Rest)
                    end
            end
    end.

summary_line_usable(<<>>) ->
    false;
summary_line_usable(<<"- **Device name", _/binary>>) ->
    false;
summary_line_usable(<<"- **Depends-on", _/binary>>) ->
    false;
summary_line_usable(<<"- **Status", _/binary>>) ->
    false;
summary_line_usable(<<"Source tests:", _/binary>>) ->
    false;
summary_line_usable(<<"Prerequisites:", _/binary>>) ->
    false;
summary_line_usable(<<">", _/binary>>) ->
    false;
summary_line_usable(<<"<", _/binary>>) ->
    false;
summary_line_usable(_) ->
    true.

strip_inline_markdown(Text) ->
    NoTicks = binary:replace(Text, <<"`">>, <<>>, [global]),
    NoTicks.

code_blocks(Markdown) ->
    Lines = binary:split(Markdown, <<"\n">>, [global]),
    code_blocks(Lines, outside, <<>>, [], [], 0).

code_blocks([], outside, _Lang, _Lines, Acc, _Index) ->
    lists:reverse(Acc);
code_blocks([], inside, Lang, Lines, Acc, Index) ->
    lists:reverse([code_block(Index, Lang, lists:reverse(Lines)) | Acc]);
code_blocks([Line | Rest], outside, _Lang, _Lines, Acc, Index) ->
    case fence_language(Line) of
        {ok, Lang} -> code_blocks(Rest, inside, Lang, [], Acc, Index);
        false -> code_blocks(Rest, outside, <<>>, [], Acc, Index)
    end;
code_blocks([Line | Rest], inside, Lang, Lines, Acc, Index) ->
    case is_fence(Line) of
        true ->
            Block = code_block(Index, Lang, lists:reverse(Lines)),
            code_blocks(Rest, outside, <<>>, [], [Block | Acc], Index + 1);
        false ->
            code_blocks(Rest, inside, Lang, [Line | Lines], Acc, Index)
    end.

code_block(Index, Lang, Lines) ->
    Text = join_lines(Lines),
    NormLang = normalize_lang(Lang),
    #{
        <<"index">> => Index,
        <<"language">> => NormLang,
        <<"text">> => Text,
        <<"runnable">> => is_runnable_block(NormLang, Text),
        <<"command-count">> => command_count(Text)
    }.

command_count(Text) ->
    Lines = binary:split(Text, <<"\n">>, [global]),
    length([Line || Line <- Lines, is_command_line(trim(Line))]).

is_runnable_block(<<"http">>, Text) ->
    not inspect_only_block(Text) andalso command_count(Text) > 0;
is_runnable_block(<<"bash">>, Text) ->
    not inspect_only_block(Text) andalso binary:match(Text, <<"curl">>) =/= nomatch;
is_runnable_block(<<"sh">>, Text) ->
    not inspect_only_block(Text) andalso binary:match(Text, <<"curl">>) =/= nomatch;
is_runnable_block(_Lang, _Text) ->
    false.

inspect_only_block(Text) ->
    has_angle_placeholder(Text) orelse
        lists:any(
            fun(Pattern) -> binary:match(Text, Pattern) =/= nomatch end,
            [
                <<"PROCESS_ID">>,
                <<"/path/to/">>,
                <<"BAD_MESSAGE_ID">>,
                <<"$(">>,
                <<"`">>
            ]
        ).

has_angle_placeholder(Text) ->
    binary:match(Text, <<"<">>) =/= nomatch andalso
        binary:match(Text, <<">">>) =/= nomatch.

is_command_line(<<"curl">>) -> true;
is_command_line(<<"curl ", _/binary>>) -> true;
is_command_line(<<"GET ", _/binary>>) -> true;
is_command_line(<<"POST ", _/binary>>) -> true;
is_command_line(<<"PUT ", _/binary>>) -> true;
is_command_line(<<"PATCH ", _/binary>>) -> true;
is_command_line(<<"DELETE ", _/binary>>) -> true;
is_command_line(<<"HEAD ", _/binary>>) -> true;
is_command_line(_Line) -> false.

heading(<<"# ", Text/binary>>) -> {1, Text};
heading(<<"## ", Text/binary>>) -> {2, Text};
heading(<<"### ", Text/binary>>) -> {3, Text};
heading(<<"#### ", Text/binary>>) -> {4, Text};
heading(<<"##### ", Text/binary>>) -> {5, Text};
heading(_Line) -> false.

raw_html_line(<<"<video class=\"hb-page-figure\" src=\"../assets/images/what-is-hyperbeam-fig.mp4\" autoplay loop muted playsinline aria-label=\"HyperBEAM modular compute blocks\"></video>">> = Line) ->
    {ok, Line};
raw_html_line(<<"<video class=\"theme-invert-video\" src=\"https://arweave.net/pc73dj9tZtj7AOeIKBGiiOm5ta13FYXzgsqWSePAxiM\" style=\"width: 100%; height: auto; display: block;\" autoplay=\"\" muted=\"\" playsinline=\"\" loop=\"\" controlslist=\"nodownload nofullscreen noremoteplayback\" disablepictureinpicture=\"\" preload=\"auto\"></video>">> = Line) ->
    {ok, Line};
raw_html_line(<<"<div class=\"core-concepts-flex\">">> = Line) ->
    {ok, Line};
raw_html_line(<<"<div class=\"core-concepts-column\">">> = Line) ->
    {ok, Line};
raw_html_line(<<"</div>">> = Line) ->
    {ok, Line};
raw_html_line(<<"<img class=\"core-concepts-fig ", Rest/binary>> = Line) ->
    case allowed_core_concepts_img(Rest) of
        true -> {ok, Line};
        false -> false
    end;
raw_html_line(<<"<p class=\"core-concept-header-", Rest/binary>> = Line) ->
    case allowed_core_concept_header(Rest) of
        true -> {ok, Line};
        false -> false
    end;
raw_html_line(<<"<span class=\"core-concept-subtitle\">", Rest/binary>> = Line) ->
    case ends_with(Rest, <<"</span>">>) of
        true -> {ok, Line};
        false -> false
    end;
raw_html_line(<<"<p class=\"core-concept-copy\">", Rest/binary>> = Line) ->
    case ends_with(Rest, <<"</p>">>) andalso binary:match(Rest, <<"<script">>) =:= nomatch of
        true -> {ok, Line};
        false -> false
    end;
raw_html_line(_Line) ->
    false.

allowed_core_concepts_img(Rest) ->
    (starts_with(Rest, <<"messages\" src=\"/docs/assets/images/aosvg1.svg\"">>) orelse
        starts_with(Rest, <<"devices\" src=\"/docs/assets/images/aosvg2.svg\"">>) orelse
        starts_with(Rest, <<"paths\" src=\"/docs/assets/images/aosvg3.svg\"">>)) andalso
        ends_with(Rest, <<" alt=\"\" loading=\"lazy\">">>).

allowed_core_concept_header(Rest) ->
    (starts_with(Rest, <<"messages\"><b>Messages</b></p>">>) orelse
        starts_with(Rest, <<"devices\"><b>Devices</b></p>">>) orelse
        starts_with(Rest, <<"paths\"><b>Paths</b></p>">>)).

bullet_text(<<"- ", Text/binary>>) -> {ok, trim(Text)};
bullet_text(<<"-   ", Text/binary>>) -> {ok, trim(Text)};
bullet_text(<<"* ", Text/binary>>) -> {ok, trim(Text)};
bullet_text(<<"*   ", Text/binary>>) -> {ok, trim(Text)};
bullet_text(_Line) -> false.

numbered_text(Line) ->
    case binary:split(Line, <<". ">>) of
        [Num, Text] when byte_size(Num) > 0 ->
            case is_digits(Num) of
                true -> {ok, Text};
                false -> false
            end;
        _ -> false
    end.

take_list_block([], _Kind, Current, Items) ->
    {lists:reverse([finish_list_item(Current) | Items]), []};
take_list_block([Line | Rest] = All, Kind, Current, Items) ->
    Trim = trim(Line),
    case Trim of
        <<>> ->
            {lists:reverse([finish_list_item(Current) | Items]), Rest};
        _ ->
            case list_marker(Kind, Trim) of
                {ok, Text} ->
                    take_list_block(Rest, Kind, [Text], [finish_list_item(Current) | Items]);
                false ->
                    case is_list_continuation(Line, Trim) of
                        true ->
                            take_list_block(Rest, Kind, [Trim | Current], Items);
                        false ->
                            {lists:reverse([finish_list_item(Current) | Items]), All}
                    end
            end
    end.

list_marker(unordered, Line) ->
    bullet_text(Line);
list_marker(ordered, Line) ->
    numbered_text(Line).

is_list_continuation(Line, Trim) ->
    is_indented(Line) andalso not is_block_start(Trim).

is_indented(<<" ", _/binary>>) -> true;
is_indented(<<"\t", _/binary>>) -> true;
is_indented(_Line) -> false.

is_block_start(Trim) ->
    heading(Trim) =/= false orelse
        fence_language(Trim) =/= false orelse
        bullet_text(Trim) =/= false orelse
        numbered_text(Trim) =/= false.

finish_list_item(Lines) ->
    iolist_to_binary(lists:join(<<" ">>, lists:reverse(Lines))).

render_list(Tag, Items, Opts) ->
    [
        <<"<">>, Tag, <<">">>,
        [[<<"<li>">>, render_inline(Item, Opts), <<"</li>">>] || Item <- Items],
        <<"</">>, Tag, <<">">>
    ].

is_digits(<<>>) ->
    false;
is_digits(Bin) ->
    lists:all(fun(Char) -> Char >= $0 andalso Char =< $9 end, binary_to_list(Bin)).

fence_language(Line) ->
    Trim = trim(Line),
    case starts_with(Trim, <<"```">>) of
        true ->
            Size = byte_size(Trim),
            Lang =
                case Size of
                    3 -> <<"text">>;
                    _ -> trim(binary:part(Trim, 3, Size - 3))
                end,
            {ok, normalize_lang(Lang)};
        false ->
            false
    end.

is_fence(Line) ->
    fence_language(Line) =/= false.

normalize_lang(<<"">>) -> <<"text">>;
normalize_lang(<<"sh">>) -> <<"bash">>;
normalize_lang(<<"shell">>) -> <<"bash">>;
normalize_lang(Lang) -> hb_util:to_lower(Lang).

join_lines([]) ->
    <<>>;
join_lines(Lines) ->
    iolist_to_binary(lists:join(<<"\n">>, Lines)).

trim(Bin) ->
    unicode:characters_to_binary(string:trim(unicode:characters_to_list(Bin))).

starts_with(Bin, Prefix) when byte_size(Bin) >= byte_size(Prefix) ->
    binary:part(Bin, 0, byte_size(Prefix)) =:= Prefix;
starts_with(_Bin, _Prefix) ->
    false.

ends_with(Bin, Suffix) when byte_size(Bin) >= byte_size(Suffix) ->
    Offset = byte_size(Bin) - byte_size(Suffix),
    binary:part(Bin, Offset, byte_size(Suffix)) =:= Suffix;
ends_with(_Bin, _Suffix) ->
    false.

esc(Value) ->
    B0 = hb_util:bin(Value),
    B1 = binary:replace(B0, <<"&">>, <<"&amp;">>, [global]),
    B2 = binary:replace(B1, <<"<">>, <<"&lt;">>, [global]),
    B3 = binary:replace(B2, <<">">>, <<"&gt;">>, [global]),
    B4 = binary:replace(B3, <<"\"">>, <<"&quot;">>, [global]),
    binary:replace(B4, <<"'">>, <<"&#39;">>, [global]).

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
    ?assertEqual(24, length(maps:get(<<"pages">>, maps:get(<<"boilerplate">>, Data)))),
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
    ?assertEqual(nomatch, binary:match(Body, <<"AO Devices">>)),
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
    ?assert(binary:match(Root, <<"priv/docs/cookbook/device-docs">>) =/= nomatch),
    ?assertEqual(nomatch, binary:match(Root, <<"/home/fn/Dev/device-docs">>)).

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
    ?assertEqual(nomatch, binary:match(SpecBody, <<"<strong>Device name:</strong>">>)),
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

schema_source_contract_test() ->
    {Schema, _Order, Source} =
        docs_schema_for_device(
            ?MESSAGE_DEVICE,
            <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>,
            #{}
        ),
    ?assertEqual(<<"implementation-derived">>, maps:get(<<"mode">>, Source)),
    ?assertEqual(<<"present">>, maps:get(<<"status">>, Source)),
    ?assert(maps:is_key(<<"docs">>, Schema)),
    ?assert(maps:is_key(<<"schema">>, Schema)),
    DocsSchema = maps:get(<<"docs">>, Schema),
    ?assertEqual(<<"none">>, maps:get(<<"description-source">>, DocsSchema)),
    ?assertNot(maps:is_key(<<"description">>, DocsSchema)),
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
    DocsSchema = maps:get(<<"docs">>, Schema),
    DocsRequest = maps:get(<<"request">>, maps:get(<<"type-schema">>, DocsSchema)),
    DocsWildcard = maps:get(<<"wildcard">>, DocsRequest),
    ?assertEqual(<<"optional">>, maps:get(<<"presence">>, DocsWildcard)).

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

static_recipes_attach_to_device_pages_test() ->
    MessageRecipes = static_device_recipes(<<"message@1.0">>),
    RouterRecipes = static_device_recipes(<<"router@1.0">>),
    MetaRecipes = static_device_recipes(<<"meta@1.0">>),
    TXRecipes = static_device_recipes(<<"tx@1.0">>),
    ?assert(maps:is_key(<<"message-to-json-pipe">>, MessageRecipes)),
    ?assert(maps:is_key(<<"relay-fetch-transform">>, RouterRecipes)),
    ?assert(maps:is_key(<<"read-meta-node-info">>, MetaRecipes)),
    ?assertNot(maps:is_key(<<"check-node-readiness">>, MetaRecipes)),
    ?assertNot(maps:is_key(<<"trusted-custom-device">>, MetaRecipes)),
    ?assert(maps:is_key(<<"inspect-transaction-codec">>, TXRecipes)),
    TXRecipe = maps:get(<<"inspect-transaction-codec">>, TXRecipes),
    ?assertEqual(<<"static-cookbook">>, maps:get(<<"source">>, TXRecipe)),
    ?assertEqual(
        <<"docs/recipes/inspect-transaction-codec.md">>,
        maps:get(<<"source-relative">>, TXRecipe)
    ),
    ?assertEqual(2, maps:get(<<"runnable-block-count">>, TXRecipe)),
    Body = iolist_to_binary(recipe_nav(<<"tx@1.0">>, TXRecipes)),
    ?assert(binary:match(Body, <<"href=\"/~tx@1.0/docs/recipes/inspect-transaction-codec\"">>) =/= nomatch),
    ?assert(binary:match(Body, <<"Inspect The Transaction Codec">>) =/= nomatch).

static_curated_recipe_mode_skips_on_weave_lookup_test() ->
    Opts = #{ <<"docs-recipe-source-mode">> => <<"static-curated">> },
    ?assertEqual(
        #{},
        on_weave_recipe_docs_if_enabled(
            <<"message@1.0">>,
            <<"spec-id">>,
            <<"spec-signer">>,
            Opts
        )
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
    ?assertEqual(24, length(Pages)),
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
    ?assertNot(lists:member(<<"docs/introduction/ao-devices.md">>, RelPaths)),
    ?assertNot(lists:member(<<"docs/devices/index.md">>, RelPaths)),
    ?assertNot(lists:member(<<"docs/recipes/index.md">>, RelPaths)),
    ?assertNot(lists:member(<<"docs/device-recipes/index.md">>, RelPaths)),
    ?assertNot(lists:member(<<"docs/reference/device-inventory.md">>, RelPaths)),
    ?assert(lists:member(<<"docs/reference/example-validation.md">>, RelPaths)),
    ?assert(lists:member(<<"docs/reference/process-fixture.md">>, RelPaths)),
    ?assert(lists:member(<<"docs/reference/recipe-standards.md">>, RelPaths)),
    ?assert(lists:member(<<"docs/reference/recipe-audit-2026-06-25.md">>, RelPaths)),
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
    ?assertEqual(nomatch, binary:match(maps:get(<<"source-root">>, Index), <<"/home/fn/Dev/device-docs">>)),
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
    ?assertEqual(nomatch, binary:match(IntroBody, <<"href=\"/docs/introduction/ao-devices\"">>)),
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
    ?assertEqual(nomatch, binary:match(PathingBody, <<"href=\"/~message@1.0/docs\"">>)),
    ?assert(binary:match(PathingBody, <<"<code>~process@1.0</code>">>) =/= nomatch),
    ?assert(binary:match(PathingBody, <<"<code>~patch@1.0</code>">>) =/= nomatch),
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
        <<"docs/devices/compute-and-processes/process-at-1-0/02-state-and-reads.md">>,
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
    ?assert(binary:match(GuidesBody, <<"href=\"/docs/reference/recipe-standards\"">>) =/= nomatch),
    ?assert(binary:match(GuidesBody, <<"href=\"/docs/reference/process-fixture\"">>) =/= nomatch),
    ?assert(binary:match(GuidesBody, <<"Recipe Standards">>) =/= nomatch),
    ?assertEqual(nomatch, binary:match(GuidesBody, <<"Merged from the HyperBEAM">>)),
    ?assertEqual(nomatch, binary:match(GuidesBody, <<"/docs/boilerplate">>)),
    ?assertEqual(nomatch, binary:match(GuidesBody, <<"01-intro-to-process">>)),
    ?assertEqual(nomatch, binary:match(GuidesBody, <<"SOURCE-MAP">>)),
    ?assert(binary:match(GuidesBody, <<"The HTTP-native protocol for decentralized computation">>) =/= nomatch),
    ?assertEqual(nomatch, binary:match(GuidesBody, <<"hb-docs-recipe-card-title\">Device Recipe Format</strong>">>)),
    ?assertEqual(nomatch, binary:match(GuidesBody, <<"Device Recipes">>)),
    ?assertEqual(nomatch, binary:match(GuidesBody, <<"AO Devices">>)),
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
    {ok, StandardsJSONResponse} = node_info_route([<<"reference">>, <<"recipe-standards">>], #{ <<"accept">> => <<"application/json">> }, #{}),
    StandardsJSON = decoded_json_response(StandardsJSONResponse),
    ?assertEqual(<<"docs/reference/recipe-standards.md">>, maps:get(<<"source-relative">>, StandardsJSON)),
    {ok, AuditJSONResponse} = node_info_route([<<"reference">>, <<"recipe-audit-2026-06-25">>], #{ <<"accept">> => <<"application/json">> }, #{}),
    AuditJSON = decoded_json_response(AuditJSONResponse),
    ?assertEqual(<<"docs/reference/recipe-audit-2026-06-25.md">>, maps:get(<<"source-relative">>, AuditJSON)),
    {ok, FixtureJSONResponse} = node_info_route([<<"reference">>, <<"process-fixture">>], #{ <<"accept">> => <<"application/json">> }, #{}),
    FixtureJSON = decoded_json_response(FixtureJSONResponse),
    ?assertEqual(<<"docs/reference/process-fixture.md">>, maps:get(<<"source-relative">>, FixtureJSON)),
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
    ?assert(binary:match(maps:get(<<"body">>, CSS), <<"hb-runner">>) =/= nomatch).

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
