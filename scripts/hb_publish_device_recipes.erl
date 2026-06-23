%%% @doc Publish staged device recipes as on-weave Device-Recipe messages.
-module(hb_publish_device_recipes).

-export([publish/4]).

publish(WalletPath0, StagingDir0, MappingFile0, OutDir0) ->
    WalletPath = hb_util:bin(WalletPath0),
    StagingDir = hb_util:bin(StagingDir0),
    MappingFile = hb_util:bin(MappingFile0),
    OutDir = hb_util:bin(OutDir0),
    ok = filelib:ensure_dir(filename:join(OutDir, <<".keep">>)),
    SpecMap = load_spec_map(MappingFile),
    PublishCodec = <<"ans104@1.0">>,
    Wallet = hb_forge_args:load_wallet(WalletPath),
    Opts =
        #{
            <<"priv-wallet">> => Wallet,
            <<"prometheus">> => false,
            <<"commitment-device">> => PublishCodec,
            <<"bootstrap-device-src">> =>
                hb_forge_args:bootstrap_preloaded_dirs()
        },
    {ok, _} = application:ensure_all_started(hackney),
    case hb_http_client:start_link(Opts) of
        {ok, _} -> ok;
        {error, {already_started, _}} -> ok
    end,
    NodeOpts = hb_forge_seed:with_forge_bootstrap(Opts, fun(Seed) -> Seed end),
    UploadOpts =
        (without_forge_bootstrap(NodeOpts))#{
            <<"linkify-mode">> => false
        },
    Recipes = selected_recipes(StagingDir, SpecMap),
    Items =
        [
            publish_recipe(Recipe, StagingDir, NodeOpts, UploadOpts, PublishCodec)
        || Recipe <- Recipes
        ],
    Export = #{
        created_at => timestamp(),
        publish_codec => PublishCodec,
        recipe_count => length(Items),
        items => Items
    },
    ExportFile = filename:join(OutDir, <<"device-recipes-published.etf">>),
    MappingOut = filename:join(OutDir, <<"device-recipes-published.mapping">>),
    ok = file:write_file(ExportFile, term_to_binary(Export, [compressed])),
    ok = file:write_file(MappingOut, recipe_mapping_text(Items)),
    io:format("recipes=~p~nexport=~s~nmapping=~s~n", [
        length(Items),
        ExportFile,
        MappingOut
    ]),
    {ok, ExportFile}.

load_spec_map(MappingFile) ->
    {ok, Bin} = file:read_file(MappingFile),
    maps:from_list(
        [
            {Device, SpecID}
        || Line <- binary:split(Bin, <<"\n">>, [global]),
            Line =/= <<>>,
            {ok, Device, SpecID} <- [parse_mapping_line(Line)]
        ]
    ).

parse_mapping_line(Line) ->
    case binary:split(Line, <<" ">>, [global]) of
        [Device, <<"spec=", SpecID/binary>>, <<"impl=", _ImplID/binary>>] ->
            {ok, Device, SpecID};
        _ ->
            skip
    end.

selected_recipes(StagingDir, SpecMap) ->
    Manifest = filename:join(StagingDir, <<"manifest.jsonl">>),
    {ok, Bin} = file:read_file(Manifest),
    Recipes0 =
        [
            Recipe
        || Line <- binary:split(Bin, <<"\n">>, [global]),
            Line =/= <<>>,
            Recipe <- [hb_json:decode(Line)],
            maps:is_key(hb_maps:get(<<"primary_device">>, Recipe, <<>>, #{}), SpecMap)
        ],
    Recipes =
        [
            Recipe#{
                <<"spec-id">> =>
                    maps:get(hb_maps:get(<<"primary_device">>, Recipe, <<>>, #{}), SpecMap)
            }
        || Recipe <- Recipes0
        ],
    case length(Recipes) of
        102 -> Recipes;
        N -> erlang:error({unexpected_publishable_recipe_count, N})
    end.

publish_recipe(Recipe, StagingDir, NodeOpts, UploadOpts, PublishCodec) ->
    Msg = recipe_message(Recipe, StagingDir),
    Signed = commit_for_publish(Msg, NodeOpts, PublishCodec),
    ok = upload_or_error(Signed, UploadOpts, PublishCodec),
    ID = hb_message:id(Signed, all, UploadOpts),
    Device = maps:get(<<"primary_device">>, Recipe),
    Slug = maps:get(<<"slug">>, Recipe),
    SpecID = maps:get(<<"spec-id">>, Recipe),
    io:format("published recipe ~s/~s id=~s spec=~s~n", [
        Device,
        Slug,
        ID,
        SpecID
    ]),
    #{
        device => Device,
        spec_id => SpecID,
        slug => Slug,
        title => maps:get(<<"title">>, Recipe),
        id => ID,
        message => Signed
    }.

recipe_message(Recipe, StagingDir) ->
    Device = maps:get(<<"primary_device">>, Recipe),
    SpecID = maps:get(<<"spec-id">>, Recipe),
    Slug = maps:get(<<"slug">>, Recipe),
    Title = maps:get(<<"title">>, Recipe),
    RelPath = maps:get(<<"output_path">>, Recipe),
    {ok, RawMarkdown} = file:read_file(filename:join(StagingDir, RelPath)),
    Body = strip_front_matter(RawMarkdown),
    Base = #{
        <<"data-protocol">> => <<"ao">>,
        <<"variant">> => <<"ao.N.1">>,
        <<"type">> => <<"Device-Recipe">>,
        <<"recipe-for-device">> => SpecID,
        <<"slug">> => Slug,
        <<"title">> => Title,
        <<"content-type">> => <<"text/markdown">>,
        <<"primary-device">> => Device,
        <<"body">> => Body
    },
    lists:foldl(
        fun({JsonKey, TagKey}, Acc) ->
            case hb_maps:get(JsonKey, Recipe, <<>>, #{}) of
                <<>> -> Acc;
                Value -> Acc#{TagKey => Value}
            end
        end,
        Base,
        [
            {<<"source_path">>, <<"source-path">>},
            {<<"source_heading">>, <<"source-heading">>},
            {<<"promotion_status">>, <<"promotion-status">>},
            {<<"recipe_kind">>, <<"recipe-kind">>}
        ]
    ).

strip_front_matter(<<"---\n", Rest/binary>>) ->
    case binary:match(Rest, <<"\n---\n">>) of
        {Pos, Len} ->
            binary:part(Rest, Pos + Len, byte_size(Rest) - Pos - Len);
        nomatch ->
            Rest
    end;
strip_front_matter(Bin) ->
    Bin.

upload_or_error(Msg, Opts, PublishCodec) ->
    case hb_client_remote:upload(Msg, Opts, PublishCodec) of
        {ok, #{<<"status">> := Status}} when is_integer(Status), Status >= 200, Status < 300 ->
            ok;
        {ok, #{<<"status">> := Status} = Response} ->
            erlang:error({upload_rejected, Status, Response});
        {ok, Response} ->
            erlang:error({upload_response_missing_status, Response});
        {error, Reason} ->
            erlang:error({upload_failed, Reason})
    end.

commit_for_publish(Msg, Opts, PublishCodec) ->
    CommitOpts = Opts#{<<"linkify-mode">> => false},
    Loaded = hb_message:convert(Msg, tabm, CommitOpts),
    {ok, Committed} =
        hb_ao:raw(
            PublishCodec,
            <<"commit">>,
            Loaded,
            #{
                <<"commitment-device">> => PublishCodec,
                <<"type">> => <<"signed">>
            },
            CommitOpts
        ),
    hb_message:convert(
        Committed,
        <<"structured@1.0">>,
        tabm,
        CommitOpts
    ).

without_forge_bootstrap(Opts) ->
    maps:remove(
        forge_bootstrap,
        maps:remove(<<"forge-bootstrap">>, Opts)
    ).

recipe_mapping_text(Items) ->
    iolist_to_binary([
        [
            maps:get(device, Item),
            <<"/">>,
            maps:get(slug, Item),
            <<" recipe=">>,
            maps:get(id, Item),
            <<" spec=">>,
            maps:get(spec_id, Item),
            <<"\n">>
        ]
    || Item <- Items
    ]).

timestamp() ->
    {{Y, Mo, D}, {H, Mi, S}} = calendar:universal_time(),
    iolist_to_binary(
        io_lib:format(
            "~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0BZ",
            [Y, Mo, D, H, Mi, S]
        )
    ).
