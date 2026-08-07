%%% @doc The hyperbeam meta device, which is the default entry point
%%% for all messages processed by the machine. This device executes a
%%% AO-Core singleton request, after first applying the node's
%%% pre-processor, if set. The pre-processor can halt the request by
%%% returning an error, or return a modified version if it deems necessary --
%%% the result of the pre-processor is used as the request for the AO-Core
%%% resolver. Additionally, a post-processor can be set, which is executed after
%%% the AO-Core resolver has returned a result.
-module(dev_meta).
-export([info/1, info/3, build/3, handle/2, adopt_node_message/2, is/2, is/3]).
-export([is_operator/3]).
-export([is_operator/2]).
-include("include/hb.hrl").
-include_lib("eunit/include/eunit.hrl").

%%% Resources the meta device meters through `metering@1.0'.
-define(META_BYTES_IN, <<"meta-bytes-in">>).
-define(META_BYTES_OUT, <<"meta-bytes-out">>).
-define(META_REQUEST_MS, <<"meta-request-ms">>).

%% @doc Ensure that the helper function `adopt_node_message/2' is not exported.
%% The naming of this method carefully avoids a clash with the exported `info/3'
%% function. We would like the node information to be easily accessible via the
%% `info' endpoint, but AO-Core also uses `info' as the name of the function
%% that grants device information. The device call takes two or fewer arguments,
%% so we are safe to use the name for both purposes in this case, as the user
%% info call will match the three-argument version of the function. If in the
%% future the `request' is added as an argument to AO-Core's internal `info'
%% function, we will need to find a different approach.
info(_) -> #{ exports => [<<"info">>, <<"build">>, <<"is-operator">>] }.

%% @doc Utility function for determining if a request is from the `operator' of
%% the node.
is_operator(Request, NodeMsg) ->
    RequestSigners = hb_message:signers(Request, NodeMsg),
    Operator =
        hb_opts:get(
            operator,
            case hb_opts:get(priv_wallet, no_viable_wallet, NodeMsg) of
                no_viable_wallet -> unclaimed;
                Wallet -> ar_wallet:to_address(Wallet)
            end,
            NodeMsg
        ),
    EncOperator =
        case Operator of
            unclaimed -> unclaimed;
            NativeAddress -> hb_util:human_id(NativeAddress)
        end,
    EncOperator == unclaimed orelse lists:member(EncOperator, RequestSigners).

%% @doc Return whether the request in the body is signed by the node operator.
is_operator(_Base, Req, NodeMsg) ->
    {ok, is_operator(hb_maps:get(<<"body">>, Req, Req, NodeMsg), NodeMsg)}.

%% @doc Emits the version number and commit hash of the HyperBEAM node source,
%% if available.
%%
%% We include the short hash separately, as the length of this hash may change in
%% the future, depending on the git version/config used to build the node.
%% Subsequently, rather than embedding the `git-short-hash-length', for the
%% avoidance of doubt, we include the short hash separately, as well as its long
%% hash.
build(_, _, _NodeMsg) ->
    BuildInfo = build_info(),
    {ok,
        #{
            <<"node">> => <<"HyperBEAM">>,
            <<"version">> => ?HYPERBEAM_VERSION,
            <<"source">> => maps:get(<<"source">>, BuildInfo, <<"unknown">>),
            <<"source-short">> =>
                maps:get(<<"source-short">>, BuildInfo, <<"unknown">>),
            <<"build-time">> => maps:get(<<"build-time">>, BuildInfo, 0)
        }
    }.

build_info() ->
    case code:priv_dir(hb) of
        {error, _} ->
            #{};
        PrivDir ->
            case file:consult(filename:join(PrivDir, "hb_buildinfo")) of
                {ok, [Info]} when is_map(Info) -> Info;
                _ -> #{}
            end
    end.

%% @doc Normalize and route messages downstream based on their path. Messages
%% with a `Meta' key are routed to the `handle_meta/2' function, while all
%% other messages are routed to the `handle_resolve/2' function.
handle(NodeMsg, RawRequest) ->
    ?event({singleton_tabm_request, RawRequest}),
    NormRequest = hb_singleton:from(RawRequest, NodeMsg),
    ?event(
        http,
        {request,
            hb_cache:ensure_all_loaded(
                hb_ao:normalize_keys(NormRequest, NodeMsg),
                NodeMsg
            )
        }
    ),
    case hb_opts:get(initialized, false, NodeMsg) of
        false ->
            Res =
                embed_status(
                    hb_ao:force_message(
                        handle_initialize(NormRequest, NodeMsg),
                        NodeMsg
                    ),
                    NodeMsg
                ),
            Res;
        _ -> handle_resolve(RawRequest, NormRequest, NodeMsg)
    end.

handle_initialize([Base = #{ <<"device">> := Dev}, Req = #{ <<"path">> := Path }|_], NodeMsg) ->
    ?event({got, {device, Dev}, {path, Path}}),
    case {Dev, Path} of
        {<<"meta@1.0">>, <<"info">>} -> info(Base, Req, NodeMsg);
        _ -> {error, <<"Node must be initialized before use.">>}
    end;
handle_initialize([{as, <<"meta@1.0">>, _}|Rest], NodeMsg) ->
    handle_initialize([#{ <<"device">> => <<"meta@1.0">>}|Rest], NodeMsg);
handle_initialize([_|Rest], NodeMsg) ->
    handle_initialize(Rest, NodeMsg);
handle_initialize([], _NodeMsg) ->
    {error, <<"Node must be initialized before use.">>}.

%% @doc Get/set the node message. If the request is a `POST', we check that the
%% request is signed by the owner of the node. If not, we return the node message
%% as-is, aside all keys that are private (according to `hb_private').
info(_, Request, NodeMsg) ->
    case hb_ao:get(<<"method">>, Request, NodeMsg) of
        <<"POST">> ->
            case is_permanent(NodeMsg) of
                true ->
                    embed_status(
                        {error,
                            <<"The node message of this machine is already "
                                "permanent. It cannot be changed.">>
                        },
                        NodeMsg
                    );
                false ->
                    update_node_message(Request, NodeMsg)
            end;
        _ ->
            ?event({get_config_req, Request, NodeMsg}),
            DynamicKeys = add_dynamic_keys(NodeMsg),
            embed_status({ok, filter_node_msg(DynamicKeys, NodeMsg)}, NodeMsg)
    end.

%% @doc Remove items from the node message that are not encodable into a
%% message.
filter_node_msg(Msg, NodeMsg) when is_map(Msg) ->
    hb_maps:map(
        fun(_, Value) -> filter_node_msg(Value, NodeMsg) end,
        hb_private:reset(Msg),
        NodeMsg
    );
filter_node_msg(Msg, NodeMsg) when is_list(Msg) ->
    lists:map(fun(Item) -> filter_node_msg(Item, NodeMsg) end, Msg);
filter_node_msg(Tuple, _NodeMsg) when is_tuple(Tuple) ->
    <<"Unencodable value.">>;
filter_node_msg(Other, _NodeMsg) ->
    Other.

%% @doc Add dynamic keys to the node message.
add_dynamic_keys(NodeMsg) ->
    UpdatedNodeMsg =
        case hb_opts:get(priv_wallet, no_viable_wallet, NodeMsg) of
            no_viable_wallet ->
                NodeMsg;
            Wallet ->
                %% Create a new map with address and merge it (overwriting existing)
                Address = hb_util:id(ar_wallet:to_address(Wallet)),
                NodeMsg#{ <<"address">> => Address }
        end,
    add_identity_addresses(UpdatedNodeMsg).

add_identity_addresses(NodeMsg) ->
    Identities = hb_opts:get(identities, #{}, NodeMsg),
    NewIdentities = maps:map(fun(_, Identity) ->
        Identity#{
            <<"address">> => hb_util:human_id(
                hb_opts:get(priv_wallet, hb:wallet(), Identity)
            )
        }
    end, Identities),
    NodeMsg#{ <<"identities">> => NewIdentities }.

%% @doc Validate that the request is signed by the operator of the node, then
%% allow them to update the node message.
update_node_message(Request, NodeMsg) ->
    case is(admin, Request, NodeMsg) of
        false ->
            ?event({set_node_message_fail, Request}),
            embed_status({error, <<"Unauthorized">>}, NodeMsg);
        true ->
            case adopt_node_message(Request, NodeMsg) of
                {ok, NewNodeMsg} ->
                    NewH = hb_opts:get(node_history, [], NewNodeMsg),
                    embed_status(
                        {ok,
                            #{
                                <<"body">> =>
                                    iolist_to_binary(
                                        io_lib:format(
                                            "Node message updated. History: ~p"
                                                "updates.",
                                            [length(NewH)]
                                        )
                                    ),
                                <<"history-length">> => length(NewH)
                            }
                        },
                        NodeMsg
                    );
                {error, Reason} ->
                    ?event({set_node_message_fail, Request, Reason}),
                    embed_status({error, Reason}, NodeMsg)
            end
    end.

%% @doc Attempt to adopt changes to a node message.
adopt_node_message(Request, NodeMsg) ->
    ?event({set_node_message_success, Request}),
    % Ensure that the node history is updated and the http-server ID is
    % not overridden.
    case is_permanent(NodeMsg) of
        true ->
            {error, <<"Node message is already permanent.">>};
        false ->
            hb_http_server:set_opts(Request, NodeMsg)
    end.

is_permanent(NodeMsg) ->
    hb_ao:get(<<"initialized">>, NodeMsg, not_found, NodeMsg) =:= <<"permanent">>.

%% @doc Handle an AO-Core request, which is a list of messages. We apply
%% the node's pre-processor to the request first, and then resolve the request
%% using the node's AO-Core implementation if its response was `ok'.
%% After execution, we run the node's `response' hook on the result of
%% the request before returning the result it grants back to the user.
handle_resolve(Req, Msgs, NodeMsg) ->
    % Apply the pre-processor to the request.
    ?event(http_request,
        {resolve_hook,
            {raw_request, Req},
            {parsed_request_sequence, Msgs}
        }
    ),
    LoadedMsgs = hb_cache:ensure_all_loaded(Msgs, NodeMsg),
    % Start the clock before the request hook, not after. A tunnel broker
    % holds a relay open inside that hook, so a timer started after it returns
    % measures everything except the wait -- which is the only part worth
    % selling.
    Start = erlang:monotonic_time(millisecond),
    case resolve_hook(<<"request">>, Req, LoadedMsgs, NodeMsg) of
        {ok, []} ->
            {ok,
                #{
                    <<"status">> => 307,
                    <<"body">> => <<"Redirecting to default request.">>,
                    <<"location">> => hb_opts:get(
                        default_request,
                        <<"/~hyperbuddy@1.0/index">>,
                        NodeMsg
                    )
                }
            };
        {ok, PreProcessedMsg} ->
            ?event(http_request, {request_after_preprocessing, PreProcessedMsg}),
            % Meter the inbound request. This has to happen *after* the request
            % hook has returned: the hook is where `p4@1.0' calls the pricing
            % device's `estimate', and `metering@1.0' opens its process-local
            % session there. A `consume' before that point is a silent no-op.
            meta_meter_size(?META_BYTES_IN, LoadedMsgs, NodeMsg),
            AfterPreprocOpts = hb_http_server:get_opts(NodeMsg),
            % Resolve the request message.
            HTTPOpts = hb_maps:merge(
                AfterPreprocOpts,
                hb_opts:get(http_extra_opts, #{}, NodeMsg),
				NodeMsg
            ),
            Res =
                hb_ao:resolve_many(
                    PreProcessedMsg,
                    HTTPOpts#{ <<"force-message">> => true }
                ),
            {ok, StatusEmbeddedRes} = embed_status(Res, NodeMsg),
            AfterResolveOpts = hb_http_server:get_opts(NodeMsg),
            % Meter the outbound result and the time spent resolving, before
            % the response hook runs: `p4@1.0' calls the pricing device's
            % `price' inside that hook, which closes the metering session.
            meta_meter(
                ?META_REQUEST_MS,
                max(0, erlang:monotonic_time(millisecond) - Start),
                AfterResolveOpts
            ),
            meta_meter_size(
                ?META_BYTES_OUT, StatusEmbeddedRes, AfterResolveOpts),
            % Apply the post-processor to the result.
            Output = maybe_sign(
                embed_status(
                    resolve_hook(
                        <<"response">>,
                        Req,
                        StatusEmbeddedRes,
                        AfterResolveOpts
                    ),
                    NodeMsg
                ),
                NodeMsg
            ),
            ?event(http_request,
                {http_request,
                    {request, Req},
                    {result, Output}
                }
            ),
            Output;
        Res -> embed_status(hb_ao:force_message(Res, NodeMsg), NodeMsg)
    end.

%%% Metering of the traffic this node handles.
%%%
%%% `meta-bytes-in', `meta-bytes-out' and `meta-request-ms' are ordinary
%%% resource names: `dev_metering:consume/3' accepts any normalized key, so
%%% pricing them needs only a rate in `metering-rates'.
%%%
%%% The meters are deliberately generic. Anything resolved through this device
%%% is measured, whether it was served locally or relayed on behalf of another
%%% node, which is what lets a tunnel broker charge for carried traffic without
%%% the tunnel device knowing anything about pricing. The same generality is
%%% the caveat: this is a node-wide toll and cannot single out one device's
%%% traffic.
%%%
%%% Directions are named from this node's side. A broker metering a relay sees
%%% the payload it serves to the public arrive as the tunnelled node's response
%%% POST, so that payload counts against `meta-bytes-in'.
%%%
%%% `consume/3' is a no-op outside an active metering session, so an unpaid
%%% node pays only for the sizing call -- which is why each meter is gated on
%%% its rate below.

%% @doc Size a message and meter it, but only when the resource is priced.
%%
%% The rate is checked first and the message is sized second. Sizing walks the
%% whole message, so on a node with no `metering-rates' -- which is every node
%% that is not selling anything -- this costs one map lookup per request and
%% touches the payload not at all. Passing `meta_size/2' as an argument to
%% `meta_meter/3' would not do: Erlang evaluates arguments eagerly, so the
%% walk would happen on every request whether or not anything was priced.
meta_meter_size(Resource, Msg, Opts) ->
    case meta_rate(Resource, Opts) of
        0 -> ok;
        _ -> meta_meter(Resource, meta_size(Msg, Opts), Opts)
    end.

%% @doc Report a metered resource to `metering@1.0', if it is priced.
meta_meter(Resource, Amount, Opts) when is_integer(Amount), Amount >= 0 ->
    case meta_rate(Resource, Opts) of
        0 ->
            ok;
        _ ->
            case hb_device_load:reference(<<"metering@1.0">>, Opts) of
                {ok, Metering} ->
                    try Metering:consume(Resource, Amount, Opts)
                    catch Class:Reason ->
                        ?event(warning,
                            {meta_meter_failed, Resource, Class, Reason}),
                        ok
                    end;
                {error, Reason} ->
                    ?event(warning, {meta_meter_unavailable, Reason}),
                    ok
            end
    end;
meta_meter(_Resource, _Amount, _Opts) ->
    ok.

%% @doc The configured rate for a metered resource, or zero.
meta_rate(Resource, Opts) ->
    case hb_opts:get(<<"metering-rates">>, #{}, Opts) of
        Rates when is_map(Rates) ->
            try hb_util:int(hb_maps:get(Resource, Rates, 0, Opts))
            catch _:_ -> 0
            end;
        _ ->
            0
    end.

%% @doc Size a message for metering. An ETF-encoded size, not wire octets:
%% stable and monotone in payload size, but not reproducible by a payer from
%% the wire.
meta_size({as, _Device, Msg}, Opts) ->
    meta_size(Msg, Opts);
meta_size(Bin, _Opts) when is_binary(Bin) ->
    byte_size(Bin);
meta_size(Msg, _Opts) ->
    try erlang:external_size(Msg)
    catch _:_ -> 0
    end.

%% @doc Execute a hook from the node message upon the user's request. The
%% invocation of the hook provides a request of the following form:
%% <pre>
%%      /path => request | response
%%      /request => the original request singleton
%%      /body => parsed sequence of messages to process | the execution result
%% </pre>
resolve_hook(HookName, InitiatingRequest, Body, NodeMsg) ->
    HookReq =
        #{
            <<"request">> => InitiatingRequest,
            <<"body">> => Body
        },
    ?event(hook, {resolve_hook, HookName, HookReq}),
    case hb_hook:on(HookName, HookReq, NodeMsg) of
        {ok, #{ <<"body">> := ResponseBody }} ->
            ?event(hook,
                {resolve_hook_success,
                    {name, HookName},
                    {response_body, ResponseBody}
                }
            ),
            {ok, ResponseBody};
        {error, _} = Error ->
            ?event(hook,
                {resolve_hook_error,
                    {name, HookName},
                    {error, Error}
                }
            ),
            Error;
        Other ->
            {error, Other}
    end.

%% @doc Wrap the result of a device call in a status.
embed_status({ErlStatus, Res}, NodeMsg) when is_map(Res) ->
    case lists:member(<<"status">>, hb_message:committed(Res, all, NodeMsg)) of
        false ->
            HTTPCode = status_code({ErlStatus, Res}, NodeMsg),
            {ok, Res#{ <<"status">> => HTTPCode }};
        true ->
            {ok, Res}
    end;
embed_status({ErlStatus, Res}, NodeMsg) ->
    HTTPCode = status_code({ErlStatus, Res}, NodeMsg),
    {ok, #{ <<"status">> => HTTPCode, <<"body">> => Res }}.

%% @doc Calculate the appropriate HTTP status code for an AO-Core result.
%% The order of precedence is:
%% 1. The status code from the message.
%% 2. The HTTP representation of the status code.
%% 3. The default status code.
status_code({error, {no_viable_responses, _AllResponses}}, NodeMsg) ->
    status_code(no_viable_responses, NodeMsg);
status_code({ErlStatus, Msg}, NodeMsg) ->
    case message_to_status(Msg, NodeMsg) of
        default -> status_code(ErlStatus, NodeMsg);
        RawStatus -> RawStatus
    end;
status_code(ok, _NodeMsg) -> 200;
status_code(error, _NodeMsg) -> 400;
status_code(created, _NodeMsg) -> 201;
status_code(not_found, _NodeMsg) -> 404;
status_code(client_error, _NodeMsg) -> 400;
status_code(no_viable_responses, _NodeMsg) -> 400;
status_code(failure, _NodeMsg) -> 500;
status_code(unavailable, _NodeMsg) -> 503;
status_code(unauthorized, _NodeMsg) -> 401;
status_code(forbidden, _NodeMsg) -> 403;
status_code(_, _NodeMsg) -> 200.

%% @doc Get the HTTP status code from a transaction (if it exists).
message_to_status(#{ <<"body">> := Status }, NodeMsg) when is_atom(Status) ->
    status_code(Status, NodeMsg);
message_to_status(Item, NodeMsg) when is_map(Item) ->
    % Note: We use `hb_maps' directly here, such that we do not cause
    % additional AO-Core calls for every request. This is particularly important
    % if a remote server is being used for all AO-Core requests by a node.
    case hb_maps:find(<<"status">>, Item, NodeMsg) of
        {ok, RawStatus} when is_integer(RawStatus) -> RawStatus;
        {ok, RawStatus} when is_atom(RawStatus) ->
            status_code(RawStatus, NodeMsg);
        {ok, RawStatus} ->
            % If we can convert the status to an integer, do so.
            try binary_to_integer(RawStatus)
            catch
                error:badarg ->
                    % We can't convert the status to an integer, but we may be
                    % able to convert it to an existing atom status code.
                    try
                        status_code(
                            binary_to_existing_atom(RawStatus, latin1),
                            NodeMsg
                        )
                    catch
                        error:badarg ->
                            % We can't convert the status to an integer or atom,
                            % so we return the default status code.
                            default
                    end
            end;
        _ -> default
    end;
message_to_status(Item, NodeMsg) when is_atom(Item) ->
    status_code(Item, NodeMsg);
message_to_status(_Item, _NodeMsg) ->
    default.

%% @doc Sign the result of a device call if the node is configured to do so.
maybe_sign({Status, Res}, NodeMsg) ->
    {Status, maybe_sign(Res, NodeMsg)};
maybe_sign(Res, NodeMsg) ->
    ?event({maybe_sign, Res}),
    case hb_opts:get(force_signed, false, NodeMsg) of
        true ->
            case hb_private:get(<<"hashpath">>, Res, not_found, NodeMsg) of
                not_found ->
                    Res;
                Hashpath ->
                    WithUnsigned =
                        hb_message:commit(
                            Res,
                            NodeMsg,
                            #{
                                <<"device">> => <<"httpsig@1.0">>,
                                <<"type">> => <<"unsigned">>
                            }
                        ),
                    hb_message:commit(
                        WithUnsigned#{ <<"hashpath">> => Hashpath },
                        NodeMsg,
                        #{
                            <<"device">> => <<"httpsig@1.0">>,
                            <<"committed">> => [<<"hashpath">>]
                        }
                    )
            end;
        false -> Res
    end.

%% @doc Check if the request in question is signed by a given `role' on the node.
%% The `role' can be one of `operator' or `initiator'.
is(Request, NodeMsg) ->
    is(operator, Request, NodeMsg).
is(admin, Request, NodeMsg) ->
    % Does the caller have the right to change the node message?
    RequestSigners = hb_message:signers(Request, NodeMsg),
    ValidOperator =
        hb_util:bin(
            hb_opts:get(
                operator,
                case hb_opts:get(priv_wallet, no_viable_wallet, NodeMsg) of
                    no_viable_wallet -> unclaimed;
                    Wallet -> ar_wallet:to_address(Wallet)
                end,
                NodeMsg
            )
        ),
    EncOperator =
        case ValidOperator of
            <<"unclaimed">> -> unclaimed;
            NativeAddress -> hb_util:human_id(NativeAddress)
        end,
    ?event({is,
        {operator,
            {valid_operator, ValidOperator},
            {encoded_operator, EncOperator},
            {request_signers, RequestSigners}
        }
    }),
    EncOperator == unclaimed orelse lists:member(EncOperator, RequestSigners);
is(operator, Req, NodeMsg) ->
    % Is the caller explicitly set to be the operator?
    % Get the operator from the node message
    Operator = hb_opts:get(operator, unclaimed, NodeMsg),
    % Get the request signers
    RequestSigners = hb_message:signers(Req, NodeMsg),
    % Ensure the operator is present in the request
    lists:member(Operator, RequestSigners);
is(initiator, Request, NodeMsg) ->
    % Is the caller the first identity that configured the node message?
    NodeHistory = hb_opts:get(node_history, [], NodeMsg),
    % Check if node-history exists and is not empty
    case NodeHistory of
        [] ->
            ?event(meta, {is_initiator, node_history, empty}),
            false;
        [InitializationRequest | _] ->
            % Extract signature from first entry
            InitializationRequestSigners = hb_message:signers(InitializationRequest, NodeMsg),
            % Get request signers
            RequestSigners = hb_message:signers(Request, NodeMsg),
            % Ensure all signers of the initalization request are present in the
            % request.
            AllSignersPresent =
                lists:all(
                    fun(Signer) -> lists:member(Signer, RequestSigners) end,
                    InitializationRequestSigners
                ),
            case AllSignersPresent of
                true ->
                    {ok, true};
                false ->
                    {error, #{
                        <<"status">> => 401,
                        <<"message">> => <<"Invalid request signature.">>
                    }}
            end
    end.

%%% Tests

%% @doc Test that we can get the node message.
config_test() ->
	StoreOpts = hb_test_utils:test_store(),
    Node =
        hb_http_server:start_node(
            Opts = #{ <<"test-config-item">> => <<"test">>, <<"store">> => StoreOpts }
        ),
    {ok, Res} = hb_http:get(Node, <<"/~meta@1.0/info">>, Opts),
    ?assertEqual(<<"test">>, hb_ao:get(<<"test-config-item">>, Res, Opts)).

%% @doc Test that we can't get the node message if the requested key is private.
priv_inaccessible_test() ->
    Node = hb_http_server:start_node(
        #{
            <<"test-config-item">> => <<"test">>,
            <<"priv-key">> => <<"BAD">>
        }
    ),
    {ok, Res} = hb_http:get(Node, <<"/~meta@1.0/info">>, #{}),
    ?event({res, Res}),
    ?assertEqual(<<"test">>, hb_ao:get(<<"test-config-item">>, Res, #{})),
    ?assertEqual(not_found, hb_ao:get(<<"priv-key">>, Res, #{})).

%% @doc Test that we can't set the node message if the request is not signed by
%% the owner of the node.
unauthorized_set_node_msg_fails_test() ->
	StoreOpts = hb_test_utils:test_store(),
    Node =
        hb_http_server:start_node(
            Opts = #{ <<"store">> => StoreOpts, <<"priv-wallet">> => ar_wallet:new() }
        ),
    {error, _} =
        hb_http:post(
            Node,
            hb_message:commit(
                #{
                    <<"path">> => <<"/~meta@1.0/info">>,
                    <<"evil-config-item">> => <<"BAD">>
                },
                Opts#{ <<"priv-wallet">> => ar_wallet:new() }
            ),
            #{}
        ),
    {ok, Res} = hb_http:get(Node, <<"/~meta@1.0/info">>, Opts),
    ?assertEqual(not_found, hb_ao:get(<<"evil-config-item">>, Res, Opts)),
    ?assertEqual(0, length(hb_ao:get(<<"node-history">>, Res, [], Opts))).

%% @doc Test that we can set the node message if the request is signed by the
%% owner of the node.
authorized_set_node_msg_succeeds_test() ->
	StoreOpts = hb_test_utils:test_store(),
    Owner = ar_wallet:new(),
    Node = hb_http_server:start_node(
        Opts = #{
            <<"operator">> => hb_util:human_id(ar_wallet:to_address(Owner)),
            <<"test-config-item">> => <<"test">>,
			<<"store">> => StoreOpts
        }
    ),
    {ok, SetRes} =
        hb_http:post(
            Node,
            hb_message:commit(
                #{
                    <<"path">> => <<"/~meta@1.0/info">>,
                    <<"test-config-item">> => <<"test2">>
                },
                Opts#{ <<"priv-wallet">> => Owner }
            ),
            Opts
        ),
    ?event({res, SetRes}),
    {ok, Res} = hb_http:get(Node, <<"/~meta@1.0/info">>, Opts),
    ?event({res, Res}),
    ?assertEqual(<<"test2">>, hb_ao:get(<<"test-config-item">>, Res, Opts)),
    ?assertEqual(1, length(hb_ao:get(<<"node-history">>, Res, [], Opts))).

%% @doc Test that an uninitialized node will not run computation.
uninitialized_node_test() ->
    Node = hb_http_server:start_node(#{ <<"initialized">> => false }),
    {error, Res} = hb_http:get(Node, <<"/key1?1.key1=value1">>, #{}),
    ?event({res, Res}),
    ?assertEqual(<<"Node must be initialized before use.">>, Res).

%% @doc Test that a permanent node message cannot be changed.
permanent_node_message_test() ->
	StoreOpts = hb_test_utils:test_store(),
    Owner = ar_wallet:new(),
    Node = hb_http_server:start_node(
        Opts =#{
            <<"operator">> => <<"unclaimed">>,
            <<"initialized">> => false,
            <<"test-config-item">> => <<"test">>,
			<<"store">> => StoreOpts
        }
    ),
    {ok, SetRes1} =
        hb_http:post(
            Node,
            hb_message:commit(
                #{
                    <<"path">> => <<"/~meta@1.0/info">>,
                    <<"test-config-item">> => <<"test2">>,
                    <<"initialized">> => <<"permanent">>
                },
                Opts#{ <<"priv-wallet">> => Owner }
            ),
            Opts
        ),
    ?event({set_res, SetRes1}),
    {ok, Res} = hb_http:get(Node, #{ <<"path">> => <<"/~meta@1.0/info">> }, Opts),
    ?event({get_res, Res}),
    ?assertEqual(<<"test2">>, hb_ao:get(<<"test-config-item">>, Res, Opts)),
    {error, SetRes2} =
        hb_http:post(
            Node,
            hb_message:commit(
                #{
                    <<"path">> => <<"/~meta@1.0/info">>,
                    <<"test-config-item">> => <<"bad-value">>
                },
                Opts#{ <<"priv-wallet">> => Owner }
            ),
            Opts
        ),
    ?event({set_res, SetRes2}),
    {ok, Res2} = hb_http:get(Node, #{ <<"path">> => <<"/~meta@1.0/info">> }, Opts),
    ?event({get_res, Res2}),
    ?assertEqual(<<"test2">>, hb_ao:get(<<"test-config-item">>, Res2, Opts)),
    ?assertEqual(1, length(hb_ao:get(<<"node-history">>, Res2, [], Opts))).

%% @doc Test that we can claim the node correctly and set the node message after.
claim_node_test() ->
	StoreOpts = hb_test_utils:test_store(),
    Owner = ar_wallet:new(),
    Address = ar_wallet:to_address(Owner),
    Node = hb_http_server:start_node(
        Opts = #{
            <<"operator">> => unclaimed,
            <<"test-config-item">> => <<"test">>,
			<<"store">> => StoreOpts
        }
    ),
    {ok, SetRes} =
        hb_http:post(
            Node,
            hb_message:commit(
                #{
                    <<"path">> => <<"/~meta@1.0/info">>,
                    <<"operator">> => hb_util:human_id(Address)
                },
                Opts#{ <<"priv-wallet">> => Owner}
            ),
            Opts
        ),
    ?event({res, SetRes}),
    {ok, Res} = hb_http:get(Node, <<"/~meta@1.0/info">>, Opts),
    ?event({res, Res}),
    ?assertEqual(hb_util:human_id(Address), hb_ao:get(<<"operator">>, Res, Opts)),
    {ok, SetRes2} =
        hb_http:post(
            Node,
            hb_message:commit(
                #{
                    <<"path">> => <<"/~meta@1.0/info">>,
                    <<"test-config-item">> => <<"test2">>
                },
                Opts#{ <<"priv-wallet">> => Owner }
            ),
            Opts
        ),
    ?event({res, SetRes2}),
    {ok, Res2} = hb_http:get(Node, <<"/~meta@1.0/info">>, Opts),
    ?event({res, Res2}),
    ?assertEqual(<<"test2">>, hb_ao:get(<<"test-config-item">>, Res2, Opts)),
    ?assertEqual(2, length(hb_ao:get(<<"node-history">>, Res2, [], Opts))).

%% Test that we can use a hook upon a request.
request_response_hooks_test() ->
    Parent = self(),
    Node = hb_http_server:start_node(
        #{
            <<"on">> =>
                #{
                    <<"request">> =>
                        #{
                            <<"device">> => #{
                                <<"request">> =>
                                    fun(_, #{ <<"body">> := Msgs }, _) ->
                                        Parent ! {hook, request},
                                        {ok, #{ <<"body">> => Msgs} }
                                    end
                            }
                        },
                    <<"response">> =>
                        #{
                            <<"device">> => #{
                                <<"response">> =>
                                    fun(_, #{ <<"body">> := Msgs }, _) ->
                                        Parent ! {hook, response},
                                        {ok, #{ <<"body">> => Msgs} }
                                    end
                            }
                        }
                }
        }),
    {ok, _} = hb_http:get(Node, <<"/~meta@1.0/info">>, #{}),
    % Receive both of the responses from the hooks, if possible.
    Res =
        receive
            {hook, request} ->
                receive {hook, response} -> true after 100 -> false end
            after 100 ->
                false
        end,
    ?assert(Res).

%% @doc Test that we can halt a request if the hook returns an error.
halt_request_test() ->
    Node = hb_http_server:start_node(
        #{
            <<"on">> =>
                #{
                    <<"request">> =>
                        #{
                            <<"device">> => #{
                                <<"request">> =>
                                    fun(_, _, _) ->
                                        {error, <<"Bad">>}
                                    end
                            }
                        }
                }
        }),
    {error, Res} = hb_http:get(Node, <<"/~meta@1.0/info">>, #{}),
    ?assertEqual(<<"Bad">>, Res).

%% @doc Test that a hook can modify a request.
modify_request_test() ->
    Node = hb_http_server:start_node(
        #{
            <<"on">> =>
                #{
                    <<"request">> =>
                        #{
                            <<"device">> => #{
                                <<"request">> =>
                                    fun(_, #{ <<"body">> := [M|Ms] }, _) ->
                                        {
                                            ok,
                                            #{
                                                <<"body">> =>
                                                    [
                                                        M#{
                                                            <<"added">> =>
                                                                <<"value">>
                                                        }
                                                    |
                                                        Ms
                                                    ]
                                            }
                                        }
                                    end
                            }
                        }
                }
        }),
    {ok, Res} = hb_http:get(Node, <<"/added">>, #{}),
    ?assertEqual(<<"value">>, Res).

%% @doc Test that forced response signing preserves signers and commits hashpath.
maybe_sign_hashpath_only_test() ->
    OldWallet = ar_wallet:new(),
    NewWallet = ar_wallet:new(),
    Hashpath = hb_path:hashpath(<<"test-hashpath">>, #{}),
    OldOpts =
        #{
            <<"commitment-device">> => <<"httpsig@1.0">>,
            <<"priv-wallet">> => OldWallet
        },
    Opts =
        #{
            <<"force-signed">> => true,
            <<"priv-wallet">> => NewWallet
        },
    OldSigner = hb_util:human_id(ar_wallet:to_address(OldWallet)),
    NewSigner = hb_util:human_id(ar_wallet:to_address(NewWallet)),
    AlreadySigned =
        (hb_message:commit(
            #{ <<"body">> => <<"test">> },
            OldOpts,
            #{ <<"committed">> => [<<"body">>] }
        ))#{
            <<"priv">> => #{ <<"hashpath">> => Hashpath }
        },
    Signed = maybe_sign(AlreadySigned, Opts),
    ?assertEqual(Hashpath, maps:get(<<"hashpath">>, Signed)),
    ?assertEqual(
        lists:sort([OldSigner, NewSigner]),
        lists:sort(hb_message:signers(Signed, Opts))
    ),
    ?assert(hb_test_utils:has_committed_keys(Signed, [<<"body">>])),
    ?assert(hb_test_utils:has_committed_keys(Signed, [<<"hashpath">>])),
    ?assert(hb_message:verify(Signed, all, Opts)).

%% @doc Test that forced response signing leaves replies without hashpaths alone.
maybe_sign_without_hashpath_test() ->
    Res = #{ <<"body">> => <<"test">> },
    Opts = #{ <<"force-signed">> => true, <<"priv-wallet">> => ar_wallet:new() },
    ?assertEqual(Res, maybe_sign(Res, Opts)),
    Signed = hb_message:commit(Res, Opts),
    ?assertNotEqual([], hb_message:signers(Signed, Opts)),
    ?assertEqual(Signed, maybe_sign(Signed, Opts)).

%% @doc Test that unsigned responses get hashpath transport commitments.
maybe_sign_unsigned_hashpath_test() ->
    Wallet = ar_wallet:new(),
    Hashpath = hb_path:hashpath(<<"test-hashpath">>, #{}),
    Opts = #{ <<"force-signed">> => true, <<"priv-wallet">> => Wallet },
    Signer = hb_util:human_id(ar_wallet:to_address(Wallet)),
    Signed =
        maybe_sign(
            #{
                <<"body">> => <<"test">>,
                <<"status">> => 200,
                <<"priv">> => #{ <<"hashpath">> => Hashpath }
            },
            Opts
        ),
    ?assertEqual(Hashpath, maps:get(<<"hashpath">>, Signed)),
    ?assertEqual([Signer], hb_message:signers(Signed, Opts)),
    ?assert(hb_test_utils:has_committed_keys(Signed, [<<"hashpath">>])),
    ?assert(hb_message:verify(Signed, all, Opts)).

%% @doc Test that version information is available and returned correctly.
buildinfo_test() ->
    Node = hb_http_server:start_node(#{}),
    BuildInfo = build_info(),
    ?assertEqual(
        {ok, <<"HyperBEAM">>},
        hb_http:get(Node, <<"/~meta@1.0/build/node">>, #{})
    ),
    ?assertEqual(
        {ok, ?HYPERBEAM_VERSION},
        hb_http:get(Node, <<"/~meta@1.0/build/version">>, #{})
    ),
    ?assertEqual(
        {ok, maps:get(<<"source">>, BuildInfo)},
        hb_http:get(Node, <<"/~meta@1.0/build/source">>, #{})
    ),
    ?assertEqual(
        {ok, maps:get(<<"source-short">>, BuildInfo)},
        hb_http:get(Node, <<"/~meta@1.0/build/source-short">>, #{})
    ),
    ?assertEqual(
        {ok, maps:get(<<"build-time">>, BuildInfo)},
        hb_http:get(Node, <<"/~meta@1.0/build/build-time">>, #{})
    ).
