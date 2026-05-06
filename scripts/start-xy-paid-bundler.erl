PublishDevice =
    fun(Name, Source, Module, Opts) ->
        SpecMsg =
            hb_message:commit(
                #{
                    <<"data-protocol">> => <<"ao">>,
                    <<"type">> => <<"Device-Spec">>,
                    <<"name">> => Name
                },
                Opts
            ),
        {ok, _SpecCacheID} = hb_cache:write(SpecMsg, Opts),
        SpecID = hb_message:id(SpecMsg, signed, Opts),
        {ok, Module, Beam} = compile:file(Source, [binary, {i, "src"}]),
        ImplMsg =
            hb_message:commit(
                hb_ao:normalize_keys(
                    #{
                        <<"data-protocol">> => <<"ao">>,
                        <<"variant">> => <<"ao.N.1">>,
                        <<"content-type">> => <<"application/beam">>,
                        <<"implements-device">> => SpecID,
                        <<"module-name">> => Module,
                        <<"requires-otp-release">> =>
                            hb_util:bin(erlang:system_info(otp_release)),
                        <<"body">> => Beam
                    },
                    Opts
                ),
                Opts
            ),
        {ok, _ImplCacheID} = hb_cache:write(ImplMsg, Opts),
        SpecID
    end.

Price =
    case os:getenv("XY_PROCESS_PRICE") of
        false -> 1;
        RawPrice -> list_to_integer(RawPrice)
    end.

BundlerBytePrice =
    case os:getenv("XY_BUNDLER_BYTE_PRICE") of
        false -> 4286;
        RawBundlerBytePrice -> list_to_integer(RawBundlerBytePrice)
    end.

BundlerMaxItems =
    case os:getenv("XY_BUNDLER_MAX_ITEMS") of
        false -> 1;
        RawBundlerMaxItems -> list_to_integer(RawBundlerMaxItems)
    end.

BundlerDispatchMs =
    case os:getenv("XY_BUNDLER_DISPATCH_MS") of
        false -> 2000;
        RawBundlerDispatchMs -> list_to_integer(RawBundlerDispatchMs)
    end.

Port =
    case os:getenv("HB_PORT") of
        false -> 19117;
        RawPort -> list_to_integer(RawPort)
    end.

PrimaryStore = #{
    <<"store-module">> => hb_store_fs,
    <<"name">> => <<"cache-xy-paid-bundler-", (integer_to_binary(Port))/binary>>
}.
ArweaveStore = #{
    <<"store-module">> => hb_store_arweave,
    <<"name">> => <<"cache-xy-paid-bundler-arweave-", (integer_to_binary(Port))/binary>>,
    <<"index-store">> => [PrimaryStore],
    <<"local-store">> => [PrimaryStore]
}.
GatewayStore = #{
    <<"store-module">> => hb_store_gateway,
    <<"local-store">> => [PrimaryStore]
}.
Store = [PrimaryStore, ArweaveStore, GatewayStore].

WalletPath =
    case os:getenv("HB_KEY") of
        false -> <<"hyperbeam-key.json">>;
        RawWalletPath -> list_to_binary(RawWalletPath)
    end.

AOToken =
    case os:getenv("XY_AO_TOKEN") of
        false -> <<"0syT13r0s0tgPmIed95bJnuSqaD29HQNN8D3ElLSrsc">>;
        RawToken -> list_to_binary(RawToken)
    end.

LedgerProcPath =
    case os:getenv("XY_LEDGER_PROCESS_FILE") of
        false ->
            <<"priv/xy-paid-bundler-ledger-", (integer_to_binary(Port))/binary, ".term">>;
        RawLedgerProcPath ->
            list_to_binary(RawLedgerProcPath)
    end.

{ok, TokenScript} = file:read_file("scripts/hyper-token.lua").
{ok, ProcessScript} = file:read_file("scripts/hyper-token-p4.lua").

Wallet = hb:wallet(WalletPath).
Operator = hb:address(Wallet).
Beneficiary =
    case os:getenv("XY_BENEFICIARY") of
        false -> Operator;
        RawBeneficiary -> list_to_binary(RawBeneficiary)
    end.
InitialBalance =
    case {os:getenv("XY_INITIAL_BALANCE_ADDRESS"), os:getenv("XY_INITIAL_BALANCE")} of
        {false, _} -> #{};
        {_, false} -> #{};
        {RawBalanceAddress, RawBalance} ->
            #{ list_to_binary(RawBalanceAddress) => list_to_integer(RawBalance) }
    end.

CommitOpts = #{
    priv_wallet => Wallet,
    <<"priv-wallet">> => Wallet,
    store => Store,
    <<"store">> => Store
}.

ProcessLedgerSpecID =
    PublishDevice(
        <<"process-ledger@1.0">>,
        "external_devices/dev_process_ledger.erl",
        dev_process_ledger,
        CommitOpts
    ).
PricingRouterSpecID =
    PublishDevice(
        <<"pricing-router@1.0">>,
        "external_devices/dev_pricing_router.erl",
        dev_pricing_router,
        CommitOpts
    ).
BundlerSettlementSpecID =
    PublishDevice(
        <<"bundler-settlement@1.0">>,
        "external_devices/dev_bundler_settlement.erl",
        dev_bundler_settlement,
        CommitOpts
    ).
AoPaymentSpecID =
    PublishDevice(
        <<"ao-payment@1.0">>,
        "external_devices/dev_ao_payment.erl",
        dev_ao_payment,
        CommitOpts
    ).

LedgerBaseDef =
    #{
        <<"device">> => <<"process@1.0">>,
        <<"execution-device">> => <<"lua@5.3a">>,
        <<"scheduler-device">> => <<"scheduler@1.0">>,
        <<"scheduler">> => [Operator],
        <<"authority">> => [Operator],
        <<"admin">> => Operator,
        <<"token">> => AOToken,
        <<"balance">> => InitialBalance,
        <<"module">> => [
            #{
                <<"content-type">> => <<"text/x-lua">>,
                <<"name">> => <<"scripts/hyper-token.lua">>,
                <<"body">> => TokenScript
            },
            #{
                <<"content-type">> => <<"text/x-lua">>,
                <<"name">> => <<"scripts/hyper-token-p4.lua">>,
                <<"body">> => ProcessScript
            }
        ]
    }.

NewLedgerProc =
    fun() ->
        Proc = hb_message:commit(LedgerBaseDef, CommitOpts, <<"httpsig@1.0">>),
        ok = filelib:ensure_dir(binary_to_list(LedgerProcPath)),
        ok = file:write_file(LedgerProcPath, term_to_binary(Proc)),
        Proc
    end.

LedgerProc =
    case file:read_file(LedgerProcPath) of
        {ok, LedgerProcBin} ->
            ExistingLedgerProc = binary_to_term(LedgerProcBin),
            case hb_message:signers(ExistingLedgerProc, CommitOpts) of
                [] -> NewLedgerProc();
                _ -> ExistingLedgerProc
            end;
        {error, enoent} -> NewLedgerProc();
        {error, LedgerProcReadError} ->
            error({failed_to_read_ledger_process, LedgerProcPath, LedgerProcReadError})
    end.
LedgerProcessID = hb_util:human_id(hb_message:id(LedgerProc, signed, CommitOpts)).

{ok, LedgerCacheID} = hb_cache:write(LedgerProc, CommitOpts).
LedgerCachePath = hb_util:human_id(LedgerCacheID).
LedgerPath = <<"/ledger~node-process@1.0">>.

Processor =
    #{
        <<"device">> => <<"p4@1.0">>,
        <<"ledger-device">> => ProcessLedgerSpecID,
        <<"pricing-device">> => PricingRouterSpecID,
        <<"default-pricing-device">> => <<"simple-pay@1.0">>,
        <<"ledger-path">> => LedgerPath,
        <<"pricing-routes">> => [
            #{
                <<"template">> => <<"/~bundler@1.0/tx">>,
                <<"pricing-device">> => <<"metering@1.0">>
            },
            #{
                <<"template">> => <<"/~bundler@1.0/item">>,
                <<"pricing-device">> => <<"metering@1.0">>
            }
        ]
    }.

BundlerSettlement =
    #{
        <<"device">> => BundlerSettlementSpecID,
        <<"ledger-device">> => ProcessLedgerSpecID,
        <<"pricing-device">> => <<"metering@1.0">>,
        <<"ledger-path">> => LedgerPath,
        <<"settlement-account">> => Operator,
        <<"beneficiary">> => Beneficiary,
        <<"hook">> => #{ <<"result">> => <<"ignore">> }
    }.

LocalRoutes = [
    #{
        <<"template">> => <<"/graphql">>,
        <<"node">> => #{ <<"uri">> => <<"http://localhost:", (integer_to_binary(Port))/binary, "/~query@1.0/graphql">> }
    },
    #{
        <<"template">> => <<"^/arweave/raw">>,
        <<"node">> => #{
            <<"match">> => <<"^/arweave/raw/(.*)$">>,
            <<"with">> => <<"http://localhost:", (integer_to_binary(Port))/binary, "/\\1/body">>
        }
    }
].
DefaultRoutes = hb_opts:get(routes, [], #{}).

Opts =
    #{
        port => Port,
        <<"port">> => Port,
        priv_key_location => WalletPath,
        priv_wallet => Wallet,
        <<"priv-key-location">> => WalletPath,
        <<"priv-wallet">> => Wallet,
        store => Store,
        <<"store">> => Store,
        load_remote_devices => true,
        <<"load-remote-devices">> => true,
        trusted_device_signers => [Operator],
        <<"trusted-device-signers">> => [Operator],
        routes => LocalRoutes ++ DefaultRoutes,
        <<"routes">> => LocalRoutes ++ DefaultRoutes,
        operator => Operator,
        p4_recipient => Operator,
        <<"operator">> => Operator,
        <<"p4-recipient">> => Operator,
        bundler_beneficiary => Beneficiary,
        <<"bundler-beneficiary">> => Beneficiary,
        <<"bundler-max-items">> => BundlerMaxItems,
        bundler_max_items => BundlerMaxItems,
        bundler_max_bundle_dispatch_delay => BundlerDispatchMs,
        <<"bundler-max-bundle-dispatch-delay">> => BundlerDispatchMs,
        arweave_index_store => ArweaveStore,
        <<"arweave-index-store">> => ArweaveStore,
        arweave_mempool_copycat_on_bundle_complete => true,
        <<"arweave-mempool-copycat-on-bundle-complete">> => true,
        arweave_mempool_progress => true,
        <<"arweave-mempool-progress">> => true,
        arweave_index_workers => 1,
        <<"arweave-index-workers">> => 1,
        arweave_pending_chunk_poll_attempts => 20,
        <<"arweave-pending-chunk-poll-attempts">> => 20,
        arweave_pending_chunk_poll_ms => 500,
        <<"arweave-pending-chunk-poll-ms">> => 500,
        simple_pay_price => 0,
        <<"simple-pay-price">> => 0,
        <<"metering-rates">> => #{
            <<"arweave-bytes">> => BundlerBytePrice,
            <<"beam-reductions">> => 0
        },
        p4_non_chargable_routes => [
            #{ <<"template">> => <<"/schedule">> },
            #{ <<"template">> => <<"/graphql">> },
            #{ <<"template">> => <<"/~query@1.0/graphql">> },
            #{ <<"template">> => <<"/*/body">> },
            #{ <<"template">> => <<"/*~node-process@1.0/*">> },
            #{ <<"template">> => << LedgerPath/binary, "/*" >> },
            #{ <<"template">> => <<"/", LedgerProcessID/binary, "~process@1.0/*" >> },
            #{ <<"template">> => <<"/~p4@1.0/balance">> },
            #{ <<"template">> => <<"/~meta@1.0/*">> }
        ],
        <<"p4-non-chargable-routes">> => [
            #{ <<"template">> => <<"/schedule">> },
            #{ <<"template">> => <<"/graphql">> },
            #{ <<"template">> => <<"/~query@1.0/graphql">> },
            #{ <<"template">> => <<"/*/body">> },
            #{ <<"template">> => <<"/*~node-process@1.0/*">> },
            #{ <<"template">> => << LedgerPath/binary, "/*" >> },
            #{ <<"template">> => <<"/", LedgerProcessID/binary, "~process@1.0/*" >> },
            #{ <<"template">> => <<"/~p4@1.0/balance">> },
            #{ <<"template">> => <<"/~meta@1.0/*">> }
        ],
        ao_payment_token => AOToken,
        <<"ao-payment-token">> => AOToken,
        ao_payment_ledger => LedgerProcessID,
        <<"ao-payment-ledger">> => LedgerProcessID,
        ao_payment_deposit_address => Operator,
        <<"ao-payment-deposit-address">> => Operator,
        ao_payment_node => <<"http://localhost:", (integer_to_binary(Port))/binary>>,
        <<"ao-payment-node">> => <<"http://localhost:", (integer_to_binary(Port))/binary>>,
        ao_payment_mainnet_url => <<"https://state.forward.computer">>,
        <<"ao-payment-mainnet-url">> => <<"https://state.forward.computer">>,
        router_opts => #{
            <<"offered">> => [
                #{ <<"template">> => <<"/.*~process@1.0/.*">>, <<"price">> => Price },
                #{ <<"template">> => <<"/~bundler@1.0/tx">>, <<"price">> => 0 },
                #{ <<"template">> => <<"/~bundler@1.0/item">>, <<"price">> => 0 }
            ]
        },
        <<"router-opts">> => #{
            <<"offered">> => [
                #{ <<"template">> => <<"/.*~process@1.0/.*">>, <<"price">> => Price },
                #{ <<"template">> => <<"/~bundler@1.0/tx">>, <<"price">> => 0 },
                #{ <<"template">> => <<"/~bundler@1.0/item">>, <<"price">> => 0 }
            ]
        },
        node_processes => #{ <<"ledger">> => LedgerBaseDef },
        <<"node-processes">> => #{ <<"ledger">> => LedgerBaseDef },
        local_names => #{ <<"ledger">> => LedgerProcessID },
        <<"local-names">> => #{ <<"ledger">> => LedgerProcessID },
        on => #{
            <<"request">> => Processor,
            <<"response">> => Processor,
            <<"bundled-message-complete">> => BundlerSettlement
        },
        <<"on">> => #{
            <<"request">> => Processor,
            <<"response">> => Processor,
            <<"bundled-message-complete">> => BundlerSettlement
        }
    }.

Node = hb_http_server:start_node(Opts).
{ok, _LedgerScheduleRes} = hb_http:post(Node, <<"/schedule">>, LedgerProc, Opts).

io:format(
    "~nXY paid bundler node started at ~s~n"
    "Operator: ~s~n"
    "Bundler beneficiary: ~s~n"
    "Wallet: ~s~n"
    "Bundler byte price: ~p AO base unit(s)~n"
    "Bundler max items: ~p~n"
    "Bundler dispatch delay: ~p ms~n"
    "Ledger process file: ~s~n"
    "Ledger process ID: ~s~n"
    "Ledger route: ~s~n"
    "Ledger local cache ID: ~s~n"
    "process-ledger spec ID: ~s~n"
    "pricing-router spec ID: ~s~n"
    "bundler-settlement spec ID: ~s~n"
    "ao-payment spec ID: ~s~n~n",
    [
        Node,
        Operator,
        Beneficiary,
        WalletPath,
        BundlerBytePrice,
        BundlerMaxItems,
        BundlerDispatchMs,
        LedgerProcPath,
        LedgerProcessID,
        LedgerPath,
        LedgerCachePath,
        ProcessLedgerSpecID,
        PricingRouterSpecID,
        BundlerSettlementSpecID,
        AoPaymentSpecID
    ]
).

receive
    stop -> ok
after
    infinity -> ok
end.
