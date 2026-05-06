-module(hb_external_device_loading_tests).

-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").

external_devices_load_by_spec_test_() ->
    {timeout, 60, fun external_devices_load_by_spec/0}.

external_devices_load_by_spec() ->
    Wallet = ar_wallet:new(),
    Store = #{
        <<"store-module">> => hb_store_fs,
        <<"name">> => <<"cache-TEST/external-devices/fs">>
    },
    Opts0 = #{
        <<"load-remote-devices">> => true,
        <<"trusted-device-signers">> =>
            [hb_util:human_id(ar_wallet:to_address(Wallet))],
        <<"store">> => Store,
        <<"priv-wallet">> => Wallet
    },
    hb_store:reset(Store),
    purge_external_modules(),
    Devices = [
        #{
            name => <<"ao-payment@1.0">>,
            source => "external_devices/dev_ao_payment.erl",
            module => dev_ao_payment,
            smoke => fun smoke_ao_payment/2
        },
        #{
            name => <<"bundler-settlement@1.0">>,
            source => "external_devices/dev_bundler_settlement.erl",
            module => dev_bundler_settlement,
            smoke => fun smoke_bundler_settlement/2
        },
        #{
            name => <<"pricing-router@1.0">>,
            source => "external_devices/dev_pricing_router.erl",
            module => dev_pricing_router,
            smoke => fun smoke_pricing_router/2
        },
        #{
            name => <<"process-ledger@1.0">>,
            source => "external_devices/dev_process_ledger.erl",
            module => dev_process_ledger,
            smoke => fun smoke_process_ledger/2
        }
    ],
    Published = [publish_device(Device, Opts0) || Device <- Devices],
    Gateway = hb_http_server:start_node(Opts0),
    Opts = Opts0#{ <<"routes">> => local_gateway_routes(Gateway) },
    lists:foreach(fun(Device) -> assert_loads_by_spec(Device, Opts) end, Published).

publish_device(Device, Opts) ->
    SpecMsg =
        hb_message:commit(
            #{
                <<"data-protocol">> => <<"ao">>,
                <<"type">> => <<"Device-Spec">>,
                <<"name">> => maps:get(name, Device)
            },
            Opts
        ),
    {ok, _SpecUnsignedID} = hb_cache:write(SpecMsg, Opts),
    SpecID = hb_message:id(SpecMsg, signed, Opts),
    {ok, ModName, Beam} =
        compile:file(maps:get(source, Device), [binary, {i, "src"}]),
    ?assertEqual(maps:get(module, Device), ModName),
    ImplMsg =
        hb_message:commit(
            hb_ao:normalize_keys(
                #{
                    <<"data-protocol">> => <<"ao">>,
                    <<"variant">> => <<"ao.N.1">>,
                    <<"content-type">> => <<"application/beam">>,
                    <<"implements-device">> => SpecID,
                    <<"module-name">> => ModName,
                    <<"requires-otp-release">> =>
                        hb_util:bin(erlang:system_info(otp_release)),
                    <<"body">> => Beam
                },
                Opts
            ),
            Opts
        ),
    {ok, _ImplUnsignedID} = hb_cache:write(ImplMsg, Opts),
    Device#{ spec_id => SpecID }.

assert_loads_by_spec(Device, Opts) ->
    SpecID = maps:get(spec_id, Device),
    ModName = maps:get(module, Device),
    ?assertMatch(<<_:43/binary>>, SpecID),
    ?assertEqual({ok, ModName}, hb_ao_device:load(SpecID, Opts)),
    (maps:get(smoke, Device))(SpecID, Opts),
    ?assertEqual({ok, ModName}, hb_ao_device:load(SpecID, Opts)).

smoke_ao_payment(SpecID, Opts) ->
    ?assertMatch(
        {error, #{ <<"status">> := 400 }},
        hb_ao:resolve(
            #{ <<"device">> => SpecID },
            #{ <<"path">> => <<"verify">> },
            Opts
        )
    ).

smoke_bundler_settlement(SpecID, Opts) ->
    PricingDevice = #{
        quote => fun(_Base, _Req, _Opts) -> {ok, 0} end
    },
    Req = #{
        <<"path">> => <<"bundled-message-complete">>,
        <<"bundled-size">> => 128,
        <<"body">> => <<"completed bundle">>
    },
    ?assertMatch(
        {ok, #{
            <<"path">> := <<"bundled-message-complete">>,
            <<"bundled-size">> := 128,
            <<"body">> := <<"completed bundle">>
        }},
        hb_ao:resolve(
            #{
                <<"device">> => SpecID,
                <<"pricing-device">> => PricingDevice
            },
            Req,
            Opts
        )
    ).

smoke_pricing_router(SpecID, Opts) ->
    RoutedPricingDevice = #{
        estimate => fun(_Base, _Req, _Opts) -> {ok, <<"routed">>} end
    },
    DefaultPricingDevice = #{
        estimate => fun(_Base, _Req, _Opts) -> {ok, <<"default">>} end
    },
    ?assertEqual(
        {ok, <<"routed">>},
        hb_ao:resolve(
            #{
                <<"device">> => SpecID,
                <<"default-pricing-device">> => DefaultPricingDevice,
                <<"pricing-routes">> => [
                    #{
                        <<"template">> => <<"/paid-route">>,
                        <<"pricing-device">> => RoutedPricingDevice
                    }
                ]
            },
            #{
                <<"path">> => <<"estimate">>,
                <<"request">> => #{ <<"path">> => <<"/paid-route">> }
            },
            Opts
        )
    ).

smoke_process_ledger(SpecID, Opts) ->
    ?assertMatch(
        {error, #{ <<"status">> := 500 }},
        hb_ao:resolve(
            #{ <<"device">> => SpecID },
            #{
                <<"path">> => <<"balance">>,
                <<"target">> => <<"alice">>
            },
            Opts
        )
    ).

local_gateway_routes(Gateway) ->
    [
        #{
            <<"template">> => <<"/graphql">>,
            <<"node">> => #{
                <<"uri">> => <<Gateway/binary, "/~query@1.0/graphql">>
            }
        },
        #{
            <<"template">> => <<"^/arweave/raw">>,
            <<"node">> => #{
                <<"match">> => <<"^/arweave/raw/(.*)$">>,
                <<"with">> => <<Gateway/binary, "/\\1/body">>
            }
        }
    ].

purge_external_modules() ->
    lists:foreach(
        fun(Mod) ->
            code:purge(Mod),
            code:delete(Mod),
            code:purge(Mod)
        end,
        [
            dev_ao_payment,
            dev_bundler_settlement,
            dev_pricing_router,
            dev_process_ledger
        ]
    ).

-endif.
