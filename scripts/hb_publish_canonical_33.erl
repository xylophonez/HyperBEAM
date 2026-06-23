%%% @doc Publish the current canonical spec-backed devices and export the exact
%%% signed messages for docs-test cache seeding.
-module(hb_publish_canonical_33).

-export([publish_export/2, seed_cache/1]).

publish_export(WalletPath0, OutDir0) ->
    WalletPath = hb_util:bin(WalletPath0),
    OutDir = hb_util:bin(OutDir0),
    ok = ensure_dir(OutDir),
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
    Groups = selected_groups(hb_packager:scan([<<"src/preloaded">>])),
    Items =
        [
            publish_group(Group, NodeOpts, UploadOpts, PublishCodec)
        || Group <- Groups
        ],
    Export = #{
        created_at => timestamp(),
        publish_codec => PublishCodec,
        signer => <<"kaYP9bJtpqON8Kyy3RbqnqdtDBDUsPTQTNUCvZtKiFI">>,
        items => Items
    },
    ExportFile = filename:join(OutDir, <<"canonical-33-published.etf">>),
    MappingFile = filename:join(OutDir, <<"canonical-33-published.mapping">>),
    DeviceSpecsFile = filename:join(OutDir, <<"canonical-33-device-specs.erlinc">>),
    ok = file:write_file(ExportFile, term_to_binary(Export, [compressed])),
    ok = file:write_file(MappingFile, mapping_text(Items)),
    ok = file:write_file(DeviceSpecsFile, device_specs_text(Items)),
    io:format("export=~s~nmapping=~s~ndevice_specs=~s~n", [
        ExportFile,
        MappingFile,
        DeviceSpecsFile
    ]),
    {ok, ExportFile}.

seed_cache(ExportFile0) ->
    ExportFile = hb_util:bin(ExportFile0),
    {ok, Bin} = file:read_file(ExportFile),
    #{items := Items} = binary_to_term(Bin),
    {ok, _} = application:ensure_all_started(hackney),
    Opts = (hb_opts:default_message_with_env())#{<<"prometheus">> => false},
    lists:foreach(fun(Item) -> seed_item(Item, Opts) end, Items),
    io:format("seeded=~p~n", [length(Items)]),
    ok.

selected_groups(Groups) ->
    Selected =
        [
            begin
                Matches =
                    [
                        Group
                    || Group <- Groups,
                        hb_packager:group_device_name(Group) =:= Device
                    ],
                case Matches of
                    [Group] -> Group;
                    [] -> erlang:error({missing_canonical_device_group, Device});
                    _ -> erlang:error({duplicate_canonical_device_group, Device})
                end
            end
        || Device <- canonical_devices()
        ],
    case length(Selected) of
        33 -> Selected;
        N -> erlang:error({unexpected_canonical_device_count, N})
    end.

publish_group(Group, NodeOpts, UploadOpts, PublishCodec) ->
    Pkg = hb_packager:package(Group, NodeOpts),
    Device = maps:get(device_name, Pkg),
    Spec =
        commit_for_publish(
            hb_packager:spec_message(Pkg, NodeOpts),
            NodeOpts,
            PublishCodec
        ),
    ok = upload_or_error(Spec, UploadOpts, PublishCodec),
    SpecID = hb_message:id(Spec, all, UploadOpts),
    Impl =
        commit_for_publish(
            hb_packager:impl_message(Pkg, SpecID, NodeOpts),
            NodeOpts,
            PublishCodec
        ),
    ok = upload_or_error(Impl, UploadOpts, PublishCodec),
    ImplID = hb_message:id(Impl, all, UploadOpts),
    io:format("published ~s spec=~s impl=~s~n", [Device, SpecID, ImplID]),
    #{
        device => Device,
        spec_id => SpecID,
        impl_id => ImplID,
        spec_message => Spec,
        impl_message => Impl
    }.

seed_item(Item, Opts) ->
    Device = maps:get(device, Item),
    SpecID = maps:get(spec_id, Item),
    ImplID = maps:get(impl_id, Item),
    {ok, _} = hb_cache:write(maps:get(spec_message, Item), Opts),
    {ok, _} = hb_cache:write(maps:get(impl_message, Item), Opts),
    case hb_cache:read(ImplID, Opts) of
        {ok, _} ->
            io:format("seeded ~s spec=~s impl=~s~n", [Device, SpecID, ImplID]),
            ok;
        Other ->
            erlang:error({cache_seed_verify_failed, Device, ImplID, Other})
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

mapping_text(Items) ->
    iolist_to_binary([
        [
            maps:get(device, Item),
            <<" spec=">>,
            maps:get(spec_id, Item),
            <<" impl=">>,
            maps:get(impl_id, Item),
            <<"\n">>
        ]
    || Item <- Items
    ]).

device_specs_text(Items) ->
    Tuples =
        [
            io_lib:format(
                "        {~tp,~n            ~tp,~n            ~tp~n        }",
                [
                    maps:get(device, Item),
                    maps:get(spec_id, Item),
                    maps:get(impl_id, Item)
                ]
            )
        || Item <- Items
        ],
    iolist_to_binary([
        <<"DeviceSpecs =\n    [\n">>,
        join(Tuples, <<",\n">>),
        <<"\n    ].\n">>
    ]).

join([], _Sep) ->
    [];
join([One], _Sep) ->
    One;
join([One | Rest], Sep) ->
    [One, Sep, join(Rest, Sep)].

ensure_dir(Dir) ->
    filelib:ensure_dir(filename:join(Dir, <<".keep">>)).

timestamp() ->
    {{Y, Mo, D}, {H, Mi, S}} = calendar:universal_time(),
    iolist_to_binary(
        io_lib:format(
            "~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0BZ",
            [Y, Mo, D, H, Mi, S]
        )
    ).

canonical_devices() ->
    [
        <<"ans104@1.0">>,
        <<"apply@1.0">>,
        <<"b32-name@1.0">>,
        <<"cookbook@1.0">>,
        <<"dedup@1.0">>,
        <<"delegated-compute@1.0">>,
        <<"flat@1.0">>,
        <<"genesis-wasm@1.0">>,
        <<"gzip@1.0">>,
        <<"httpsig@1.0">>,
        <<"json@1.0">>,
        <<"json-iface@1.0">>,
        <<"local-name@1.0">>,
        <<"lua@5.3a">>,
        <<"match@1.0">>,
        <<"message@1.0">>,
        <<"meta@1.0">>,
        <<"metering@1.0">>,
        <<"multipass@1.0">>,
        <<"name@1.0">>,
        <<"node-process@1.0">>,
        <<"p4@1.0">>,
        <<"patch@1.0">>,
        <<"push@1.0">>,
        <<"relay@1.0">>,
        <<"router@1.0">>,
        <<"scheduler@1.0">>,
        <<"stack@1.0">>,
        <<"structured@1.0">>,
        <<"trie@1.0">>,
        <<"tx@1.0">>,
        <<"wasi@1.0">>,
        <<"wasm-64@1.0">>
    ].
