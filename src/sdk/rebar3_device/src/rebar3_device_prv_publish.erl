%%% @doc `rebar3 device publish' — package, sign and upload device
%%% specifications and implementations to Arweave.
%%%
%%% Publishing reuses the same packaging pipeline as `device preload'
%%% but routes the signed messages through `dev_arweave' instead of a
%%% local filesystem store.
-module(rebar3_device_prv_publish).
-export([init/1, do/1, format_error/1]).

-define(NAMESPACE, device).
-define(PROVIDER, publish).

init(State) ->
    Provider = providers:create([
        {name, ?PROVIDER},
        {namespace, ?NAMESPACE},
        {module, ?MODULE},
        {bare, true},
        {deps, [{default, app_discovery}, {default, compile}]},
        {example, "rebar3 device publish --key wallet.json"},
        {opts, rebar3_device_args:opts()},
        {short_desc, "Sign and upload packaged devices to Arweave."},
        {desc,
            "Package and sign each device's spec + impl messages, then "
            "publish them via the configured Arweave bundler."
        }
    ]),
    {ok, rebar_state:add_provider(State, Provider)}.

do(State) ->
    Args = rebar3_device_args:parse(State),
    Dirs = maps:get(<<"device-src">>, Args),
    Roots = maps:get(<<"device-roots">>, Args, all),
    KeyPath = maps:get(<<"key">>, Args),
    Wallet = load_wallet(KeyPath),
    NodeOpts = #{
        <<"priv-wallet">> => Wallet,
        <<"commitment-device">> => <<"ans104@1.0">>,
        <<"http-client">> => httpc,
        <<"prometheus">> => false
    },
    Groups = hb_packager:scan(Dirs,
        #{ <<"device-roots">> => Roots }
    ),
    Pkgs = [hb_packager:package(G, NodeOpts) || G <- Groups],
    Results = lists:map(
        fun(Pkg) ->
            {ok, SpecID} =
                publish_msg(
                    hb_packager:spec_message(Pkg, NodeOpts),
                    NodeOpts
                ),
            {ok, ImplID} =
                publish_msg(
                    hb_packager:impl_message(Pkg, SpecID, NodeOpts),
                    NodeOpts
                ),
            #{
                device_name => maps:get(device_name, Pkg),
                spec_id => SpecID,
                impl_id => ImplID
            }
        end,
        Pkgs
    ),
    lists:foreach(
        fun(#{ device_name := Name, spec_id := SID, impl_id := IID }) ->
            rebar_api:info("device publish: ~s spec=~s impl=~s",
                [Name, SID, IID])
        end,
        Results
    ),
    {ok, State}.

publish_msg(Msg, NodeOpts) ->
    Wallet = hb_opts:get(priv_wallet, no_viable_wallet, NodeOpts),
    {ok, TX} = dev_ans104:to(Msg, #{}, NodeOpts),
    SignedTX = ar_bundles:sign_item(TX, Wallet),
    ID = hb_util:id(SignedTX, signed),
    case upload_item(ar_bundles:serialize(SignedTX), NodeOpts) of
        ok -> {ok, ID};
        Error -> erlang:error({device_publish_failed, ID, Error})
    end.

upload_item(Serialized, NodeOpts) ->
    application:ensure_all_started(inets),
    application:ensure_all_started(ssl),
    Bundler = hb_opts:get(bundler_ans104, not_found, NodeOpts),
    Req = #{
        peer => Bundler,
        path => <<"/~bundler@1.0/tx">>,
        method => <<"POST">>,
        headers => #{
            <<"codec-device">> => <<"ans104@1.0">>,
            <<"content-type">> => <<"application/ans104">>,
            <<"accept">> => <<"application/json">>
        },
        body => Serialized
    },
    case hb_http_client:request(Req, NodeOpts) of
        {ok, Status, _Headers, _Body} when Status >= 200, Status < 300 ->
            ok;
        Other ->
            {error, Other}
    end.

load_wallet(undefined) -> hb:wallet();
load_wallet(Path) -> hb:wallet(binary_to_list(hb_util:bin(Path))).

format_error(Reason) ->
    io_lib:format("device publish failed: ~p", [Reason]).
