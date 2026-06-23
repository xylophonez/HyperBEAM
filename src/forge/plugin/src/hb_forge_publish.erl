%%% @doc `rebar3 device publish' - package, sign and upload device
%%% specifications and implementations to Arweave.
%%%
%%% Publishing reuses the packager, then uploads the signed messages through
%%% HyperBEAM's Arweave client.
-module(hb_forge_publish).
-export([init/1, do/1, format_error/1]).

-define(PROVIDER, publish).

%% @doc Register the `publish' provider with rebar3.
init(State) ->
    hb_forge_args:provider(
        State,
        ?PROVIDER,
        ?MODULE,
        "rebar3 device publish --key wallet.json",
        "Sign and upload packaged devices to Arweave.",
        "Package and sign device specs + implementations, then upload them."
    ).

%% @doc Package, sign, and upload selected devices.
do(State) ->
    case hb_forge_args:maybe_help(State, ?MODULE) of
        true -> {ok, State};
        false -> do_run(State)
    end.

do_run(State) ->
    Args = hb_forge_args:parse(State, <<"_build/device-publish-store">>),
    KeyPath = maps:get(<<"key">>, Args),
    PublishCodec = maps:get(<<"publish-codec">>, Args),
    Wallet = hb_forge_args:load_wallet(KeyPath),
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
    % Sign and upload each package.
    lists:foreach(
        fun(Pkg) ->
            % Sign and upload the specification message.
            Spec =
                commit_for_publish(
                    hb_packager:spec_message(Pkg, NodeOpts),
                    NodeOpts,
                    PublishCodec
                ),
            {ok, _} = hb_client_remote:upload(Spec, UploadOpts, PublishCodec),
            SpecID = hb_message:id(Spec, all, UploadOpts),
            % Sign and upload the implementation message.
            Impl =
                commit_for_publish(
                    hb_packager:impl_message(Pkg, SpecID, NodeOpts),
                    NodeOpts,
                    PublishCodec
                ),
            {ok, _} = hb_client_remote:upload(Impl, UploadOpts, PublishCodec),
            ImplID = hb_message:id(Impl, all, UploadOpts),
            rebar_api:info(
                "device publish: ~s spec=~s impl=~s",
                [maps:get(device_name, Pkg), SpecID, ImplID]
            )
        end,
        hb_packager:package_all(
            hb_forge_args:scan_devices(Args),
            NodeOpts
        )
    ),
    {ok, State}.

%% @doc Forge publishes permanent, standalone data items. `message@1.0'
%% deliberately offloads nested signed messages for normal runtime commits;
%% publishing instead signs through the selected codec directly with linkifying
%% disabled so the resulting ANS-104 item carries its own payload.
commit_for_publish(Msg, Opts, PublishCodec) ->
    CommitOpts = Opts#{ <<"linkify-mode">> => false },
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

%% @doc Upload runs through runtime devices such as `arweave@2.9'. The
%% Forge seed bootstrap is intentionally narrow and must not intercept
%% runtime device resolution after the package has been signed.
without_forge_bootstrap(Opts) ->
    maps:remove(
        forge_bootstrap,
        maps:remove(<<"forge-bootstrap">>, Opts)
    ).

%% @doc Render provider failures for rebar3.
format_error(Reason) ->
    io_lib:format("device publish failed: ~p", [Reason]).
