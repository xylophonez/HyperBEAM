%%% @doc A library for working with HyperBEAM-compatible AO-Core devices.
%%% Offers services for loading, verifying executability, and extracting Erlang
%%% functions from a device.
-module(hb_ao_device).
-export([truncate_args/2, message_to_fun/3, message_to_device/2, load/2]).
-export([is_direct_key_access/3, is_direct_key_access/4]).
-export([find_exported_function/5, is_exported/4, info/2, info/3, default/0]).
-include("include/hb.hrl").

%%% All keys in the `message@1.0` device that are not resolved to underlying
%%% data in the their Erlang map representations.
-define(MESSAGE_KEYS, [
    <<"get">>,
    <<"set">>,
    <<"remove">>,
    <<"keys">>,
    <<"id">>,
    <<"commit">>,
    <<"verify">>,
    <<"committers">>,
    <<"committed">>
]).

%% @doc Truncate the arguments of a function to the number of arguments it
%% actually takes.
truncate_args(Fun, Args) ->
    {arity, Arity} = erlang:fun_info(Fun, arity),
    lists:sublist(Args, Arity).

%% @doc Calculate the Erlang function that should be called to get a value for
%% a given key from a device.
%%
%% This comes in 7 forms:
%% 1. The message does not specify a device, so we use the default device.
%% 2. The device has a `handler' key in its `Dev:info()' map, which is a
%% function that takes a key and returns a function to handle that key. We pass
%% the key as an additional argument to this function:
%%     `Mod:Handler(Key, Base, Req, Opts) -> {Status, Fun}'
%% 3. The device has a function of the name `Key', which should be called
%% directly.
%% 4. The device does not implement the key, but does have a default function
%% for us to call. We pass it the key as an additional argument, as with (2).
%% `default' differs from `handler' in that it only matches for keys where the
%% module exports no function of the given name.
%% 5. The device has a `default' key with a device or module name as its value.
%% We use this device to handle the key, restarting the process of resolving the
%% key to a function.
%% 6. The device does not implement the key and states no defaults. We use the
%% global default device to handle the key.
%% Error: If the device is specified, but not loadable, we raise an error.
%%
%% Returns {ok | add_key, Fun} where Fun is the function to call, and add_key
%% indicates that the key should be added to the start of the call's arguments.
message_to_fun(Msg, Key, Opts) ->
    % Get the device module from the message.
	Dev = message_to_device(Msg, Opts),
    Info = info(Dev, Msg, Opts),
    % Is the key exported by the device?
    Exported = is_exported(Info, Key, Opts),
	?event(
        ao_devices,
        {message_to_fun,
            {dev, Dev},
            {key, Key},
            {is_exported, Exported},
            {opts, Opts}
        },
		Opts
    ),
    % Does the device have an explicit handler function?
    case {hb_maps:find(handler, Info, Opts), Exported} of
        {{ok, Handler}, true} ->
			% Case 2: The device has an explicit handler function.
			?event(
                ao_devices,
                {handler_found, {dev, Dev}, {key, Key}, {handler, Handler}}
            ),
			{Status, Func} = info_handler_to_fun(Handler, Msg, Key, Opts),
            {Status, Dev, Func};
		_ ->
			?event(ao_devices, {no_override_handler, {dev, Dev}, {key, Key}}),
			case {find_exported_function(Msg, Dev, Key, 3, Opts), Exported} of
				{{ok, Func}, true} ->
					% Case 3: The device has a function of the name `Key'.
					{ok, Dev, Func};
				_ ->
					case {hb_maps:find(default, Info, Opts), Exported} of
						{{ok, DefaultFunc}, true} when is_function(DefaultFunc) ->
							% Case 4: The device has a default handler.
                            ?event({found_default_handler, {func, DefaultFunc}}),
							{add_key, Dev, DefaultFunc};
                        {{ok, DefaultMod}, true} when is_binary(DefaultMod)
                                orelse is_atom(DefaultMod) ->
                            % Case 5: The device gives a specific further device
                            % to default to.
							?event({found_default_handler, {mod, DefaultMod}}),
                            message_to_fun(
                                Msg#{ <<"device">> => DefaultMod },
                                Key,
                                Opts
                            );
						_ ->
							% Case 6: The device has no default handler.
							% We retry with the default unless the message
							% already names it (loop guard).
							DefaultDev = default(),
							case hb_maps:get(<<"device">>, Msg, undefined, Opts) of
								DefaultDev ->
									throw({
										error,
										default_device_could_not_resolve_key,
										{key, Key}
									});
								_ ->
									?event(
										{using_default_device,
										 {dev, DefaultDev}}),
									message_to_fun(
										Msg#{ <<"device">> => DefaultDev },
										Key,
										Opts
									)
							end
					end
			end
	end.

%% @doc Extract the runtime device module from a message. When the
%% message has no `<<"device">>' key, we resolve the default
%% (`message@1.0') just like any other device — there is no privileged
%% internal module-loading path.
message_to_device(Msg, Opts) ->
    DevID =
        case hb_maps:get(<<"device">>, Msg, not_found, Opts) of
            not_found -> default();
            ID -> ID
        end,
    case load(DevID, Opts) of
        {error, Reason} ->
            throw({error, {device_not_loadable, DevID, Reason}});
        {ok, DevMod} -> DevMod
    end.

%% @doc Parse a handler key given by a device's `info'.
info_handler_to_fun(Handler, _Msg, _Key, _Opts) when is_function(Handler) ->
	{add_key, Handler};
info_handler_to_fun(HandlerMap, Msg, Key, Opts) ->
	case hb_maps:find(excludes, HandlerMap, Opts) of
		{ok, Exclude} ->
			case lists:member(Key, Exclude) of
				true ->
					MsgWithoutDevice =
						hb_maps:without([<<"device">>], Msg, Opts),
					message_to_fun(
						MsgWithoutDevice#{ <<"device">> => default() },
						Key,
						Opts
					);
				false -> {add_key, hb_maps:get(func, HandlerMap, undefined, Opts)}
			end;
		error -> {add_key, hb_maps:get(func, HandlerMap, undefined, Opts)}
	end.

%% @doc Find the function with the highest arity that has the given name, if it
%% exists.
%%
%% If the device is a module, we look for a function with the given name.
%%
%% If the device is a map, we look for a key in the map. First we try to find
%% the key using its literal value. If that fails, we cast the key to an atom
%% and try again.
find_exported_function(Msg, Mod, Key, Arity, Opts) when not is_atom(Key) ->
	try hb_util:key_to_atom(Key, false) of
		KeyAtom -> find_exported_function(Msg, Mod, KeyAtom, Arity, Opts)
	catch _:_ -> not_found
	end;
find_exported_function(Msg, Dev, Key, MaxArity, Opts) when is_map(Dev) ->
    NormKey = hb_ao:normalize_key(Key),
    NormDev = hb_ao:normalize_keys(Dev, Opts),
	case hb_maps:get(NormKey, NormDev, not_found, Opts) of
		not_found -> not_found;
		Fun when is_function(Fun) ->
			case erlang:fun_info(Fun, arity) of
				{arity, Arity} when Arity =< MaxArity ->
					case is_exported(Msg, Dev, Key, Opts) of
						true -> {ok, Fun};
						false -> not_found
					end;
				_ -> not_found
			end
	end;
find_exported_function(_Msg, _Mod, _Key, Arity, _Opts) when Arity < 0 ->
    not_found;
find_exported_function(Msg, Mod, Key, Arity, Opts) ->
	case erlang:function_exported(Mod, Key, Arity) of
		true ->
			case is_exported(Msg, Mod, Key, Opts) of
				true -> {ok, fun Mod:Key/Arity};
				false -> not_found
			end;
		false ->
			find_exported_function(Msg, Mod, Key, Arity - 1, Opts)
	end.

%% @doc Check if a device is guarding a key via its `exports' list. Defaults to
%% true if the device does not specify an `exports' list. The `info' function is
%% always exported, if it exists. Elements of the `exludes' list are not
%% exported. Note that we check for info _twice_ -- once when the device is
%% given but the info result is not, and once when the info result is given.
%% The reason for this is that `info/3' calls other functions that may need to
%% check if a key is exported, so we must avoid infinite loops. We must, however,
%% also return a consistent result in the case that only the info result is
%% given, so we check for it in both cases.
is_exported(_Msg, _Dev, info, _Opts) -> true;
is_exported(Msg, Dev, Key, Opts) ->
	is_exported(info(Dev, Msg, Opts), Key, Opts).
is_exported(_, info, _Opts) -> true;
is_exported(Info = #{ excludes := Excludes }, Key, Opts) ->
    NormKey = maybe_normalize_device_key(Key, existing),
    case lists:member(NormKey, lists:map(fun maybe_normalize_device_key/1, Excludes)) of
        true -> false;
        false -> is_exported(hb_maps:remove(excludes, Info, Opts), Key, Opts)
    end;
is_exported(#{ exports := Exports }, Key, _Opts) ->
    lists:member(
        maybe_normalize_device_key(Key, existing),
        lists:map(fun maybe_normalize_device_key/1, Exports)
    );
is_exported(_Info, _Key, _Opts) -> true.

%% @doc Normalize an exported key to its canonical atomized form. By default
%% new atoms are created if necessary. In practice this is used for keys that
%% orinate from a device's `info' response, but _not_ for keys that could be
%% chosen by non-author users. This imparts a requirement that device developers
%% should not generate too many different exports/excludes -- just as they should
%% not generate too many atoms.
maybe_normalize_device_key(Key) -> maybe_normalize_device_key(Key, new_atoms).
maybe_normalize_device_key(Key, Mode) ->
    try hb_util:key_to_atom(hb_ao:normalize_key(Key), Mode)
    catch _:_ -> Key
    end.

%% @doc Load a device by name, specification ID, or already-resolved
%% generated module atom. Returns `{ok, Executable}' where `Executable'
%% is either an inline message map or a generated `_hb_device_*' atom.
%%
%% Resolution order:
%% <ol>
%%  <li>Map: passed through (inline device).</li>
%%  <li>Atom: only generated `_hb_device_*' atoms are loaded; any other
%%      atom is rejected because runtime devices must always be the
%%      generated module form.</li>
%%  <li>Binary: full resolution — device-store cache → resolve to spec
%%      ID → match implementation in (preloaded-store ++ store) → load
%%      BEAM → cache atom under both name and spec-ID keys.</li>
%% </ol>
load(Map, _Opts) when is_map(Map) -> {ok, Map};
load(Atom, Opts) when is_atom(Atom) ->
    case hb_packager:is_generated_module(Atom) of
        true ->
            case code:ensure_loaded(Atom) of
                {module, Atom} -> {ok, Atom};
                _ -> {error, not_loadable}
            end;
        false ->
            ?event(device_load,
                {refusing_unpackaged_atom, {atom, Atom}}, Opts),
            {error, {device_must_be_packaged, Atom}}
    end;
load(Ref, Opts) when is_binary(Ref) ->
    NormRef = hb_ao:normalize_key(Ref),
    ?event(device_load, {requested_load, {ref, NormRef}}, Opts),
    case is_admissible(NormRef, Opts) of
        false -> {error, {device_not_admissible, NormRef}};
        true ->
            case bootstrap_lookup(NormRef, Opts) of
                {ok, BootAtom} ->
                    case code:ensure_loaded(BootAtom) of
                        {module, BootAtom} -> {ok, BootAtom};
                        _ -> {error, {bootstrap_atom_unloadable, BootAtom}}
                    end;
                not_found ->
                    do_load_binary(NormRef, Opts)
            end
    end.

do_load_binary(NormRef, Opts) ->
    case lookup_device_cache(NormRef, Opts) of
        {ok, Atom} ->
            {ok, Atom};
        not_found ->
            case resolve_to_spec_id(NormRef, Opts) of
                {ok, SpecID} ->
                    case find_and_load_impl(NormRef, SpecID, Opts) of
                        {ok, ModName} ->
                            cache_device_module(NormRef, ModName, Opts),
                            cache_device_module(SpecID, ModName, Opts),
                            {ok, ModName};
                        Err -> Err
                    end;
                {error, _} = Err -> Err
            end
    end.

%% @doc The build-time bootstrap path. The preloader needs a working
%% signing flow before any preloaded-store exists. Setting
%% `<<"device-bootstrap">>' to a `#{ Name (binary) => Mod (atom) }' map
%% in opts makes the resolver return those atoms directly without
%% touching the store.  Runtime opts never set this key.
bootstrap_lookup(Ref, Opts) ->
    case hb_opts:get(device_bootstrap, undefined, Opts) of
        Map when is_map(Map) ->
            case maps:find(Ref, Map) of
                {ok, Mod} when is_atom(Mod) -> {ok, Mod};
                _ -> not_found
            end;
        _ -> not_found
    end.

is_admissible(Ref, Opts) ->
    case hb_opts:get(admissible_devices, all, Opts) of
        all -> true;
        Names when is_list(Names) ->
            lists:any(fun(N) -> hb_util:bin(N) =:= Ref end, Names);
        _ -> true
    end.

%%% --------------------------------------------------------------------
%%% Resolution helpers
%%% --------------------------------------------------------------------

%% @doc Resolve a name or ID into a specification ID. IDs pass through;
%% the bootstrap `name@1.0' case reads directly from the preloaded-store
%% index; everything else is resolved through the index lookup, then
%% (if absent) a loaded `~name@1.0' device.
resolve_to_spec_id(Ref, _Opts) when ?IS_ID(Ref) -> {ok, Ref};
resolve_to_spec_id(<<"name@1.0">>, Opts) ->
    bootstrap_index_lookup(<<"name@1.0">>, Opts);
resolve_to_spec_id(Ref, Opts) ->
    case bootstrap_index_lookup(Ref, Opts) of
        {ok, _} = Ok -> Ok;
        not_found -> resolve_via_name_device(Ref, Opts)
    end.

%% @doc Look up a name in the preloaded-store index. Returns the spec ID
%% as a binary on hit, `not_found' on miss, `{error, Reason}' on store
%% failure or missing index configuration.
bootstrap_index_lookup(Name, Opts) ->
    case {preloaded_store(Opts), preloaded_index_id(Opts)} of
        {undefined, _} -> not_found;
        {_, undefined} -> not_found;
        {Store, IndexID} ->
            Path = <<IndexID/binary, "/", Name/binary>>,
            case hb_store:read(Store, Path, Opts) of
                {ok, Bin} when is_binary(Bin) -> {ok, Bin};
                _ -> not_found
            end
    end.

%% @doc Use a runtime-loaded `~name@1.0' device to resolve a non-builtin
%% name to a specification ID. Falls back to an error when name@1.0
%% itself has not been loaded.
resolve_via_name_device(Ref, Opts) ->
    case lookup_device_cache(<<"name@1.0">>, Opts) of
        {ok, _NameMod} ->
            case hb_ao:resolve(
                #{ <<"device">> => <<"name@1.0">> },
                #{ <<"path">> => Ref },
                Opts
            ) of
                {ok, ID} when ?IS_ID(ID) -> {ok, ID};
                _ -> {error, {name_resolution_failed, Ref}}
            end;
        not_found ->
            {error, {name_resolution_unbootstrapped, Ref}}
    end.

%% @doc Find an implementation message for a given specification ID,
%% then verify and load the BEAM. Searches the preloaded-store and the
%% node's normal store(s) before optionally trying remote gateways.
find_and_load_impl(Ref, SpecID, Opts) ->
    SearchOpts = with_preloaded_store(Opts),
    Spec = #{
        <<"data-protocol">> => <<"ao">>,
        <<"variant">> => <<"ao.N.1">>,
        <<"content-type">> => <<"application/beam">>,
        <<"implements-device">> => SpecID
    },
    case hb_cache:match(Spec, SearchOpts) of
        {ok, [ImplID | _]} ->
            case hb_cache:read(ImplID, SearchOpts) of
                {ok, Msg} -> verify_and_load(Msg, Ref, SpecID, Opts);
                _ -> try_remote_or_fail(Ref, SpecID, Opts)
            end;
        _ ->
            try_remote_or_fail(Ref, SpecID, Opts)
    end.

try_remote_or_fail(Ref, SpecID, Opts) ->
    case hb_opts:get(load_remote_devices, false, Opts) of
        false ->
            {error, {device_not_found, Ref, SpecID}};
        true ->
            case hb_gateway_client:device(SpecID, Opts) of
                {ok, Msg} -> verify_and_load(Msg, Ref, SpecID, Opts);
                _ -> {error, {device_not_loadable_remote, Ref, SpecID}}
            end
    end.

verify_and_load(Msg, Ref, SpecID, Opts) ->
    TrustedSigners = trusted_signers(Opts),
    Signers = hb_message:signers(Msg, Opts),
    Trusted =
        case TrustedSigners of
            all -> true;
            List when is_list(List) ->
                case lists:member(all, List) of
                    true -> true;
                    false ->
                        lists:any(
                            fun(Signer) -> lists:member(Signer, List) end,
                            Signers
                        )
                end;
            _ -> false
        end,
    ?event(device_load,
        {verifying_device_trust,
            {ref, Ref},
            {trusted, Trusted},
            {signers, Signers}
        },
        Opts
    ),
    case Trusted of
        false ->
            {error, {device_signer_not_trusted, Ref}};
        true ->
            verify_implements_and_load(Msg, Ref, SpecID, Opts)
    end.

verify_implements_and_load(Msg, Ref, SpecID, Opts) ->
    case hb_maps:get(<<"implements-device">>, Msg, undefined, Opts) of
        SpecID ->
            verify_content_type_and_load(Msg, Ref, Opts);
        Other ->
            {error,
                {device_load_failed,
                    {implements_device_mismatch, Other, SpecID},
                    {ref, Ref}
                }
            }
    end.

verify_content_type_and_load(Msg, Ref, Opts) ->
    case hb_maps:get(<<"content-type">>, Msg, undefined, Opts) of
        <<"application/beam">> ->
            case verify_device_compatibility(Msg, Opts) of
                ok ->
                    ModBin =
                        hb_maps:get(<<"module-name">>, Msg, undefined, Opts),
                    BEAM =
                        case hb_maps:find(<<"body">>, Msg, Opts) of
                            {ok, Body} -> Body;
                            error ->
                                hb_maps:get(<<"data">>, Msg, undefined, Opts)
                        end,
                    load_beam(ModBin, BEAM, Ref);
                {error, Reason} ->
                    {error, {device_load_failed, Reason}}
            end;
        Other ->
            {error,
                {device_load_failed,
                    {incompatible_content_type, Other},
                    {expected, <<"application/beam">>},
                    {found, Other}
                }
            }
    end.

%% @doc Load a BEAM into the runtime under the generated module atom
%% provided in the implementation message. The atom must be in
%% `_hb_device_*' form.
load_beam(undefined, _BEAM, Ref) ->
    {error, {device_load_failed, {missing_module_name, Ref}}};
load_beam(_, undefined, Ref) ->
    {error, {device_load_failed, {missing_beam, Ref}}};
load_beam(ModBin, BEAM, Ref) ->
    case hb_packager:is_generated_module(ModBin) of
        false ->
            {error, {device_load_failed, {non_generated_module_name, ModBin, Ref}}};
        true ->
            ModName = binary_to_atom(ModBin, utf8),
            ensure_loaded(ModName, BEAM)
    end.

%% Race-tolerant load. Multiple processes may concurrently want to
%% load the same generated atom (different parallel tests sharing the
%% same kernel codec, for example). We serialise the actual
%% `erlang:load_module/2' through a global lock so the OTP code
%% server never sees overlapping loads of the same module — which
%% would otherwise produce `not_purged' errors.
ensure_loaded(ModName, BEAM) ->
    case code:is_loaded(ModName) of
        {file, _} -> {ok, ModName};
        false -> with_load_lock(ModName, BEAM)
    end.

with_load_lock(ModName, BEAM) ->
    Ref = make_ref(),
    %% `global:trans/2' serialises across the whole node, which is
    %% exactly the granularity we need (atoms are global).
    global:trans(
        {{?MODULE, load, ModName}, {self(), Ref}},
        fun() ->
            case code:is_loaded(ModName) of
                {file, _} -> {ok, ModName};
                false -> do_load_locked(ModName, BEAM)
            end
        end
    ).

do_load_locked(ModName, BEAM) ->
    case erlang:load_module(ModName, BEAM) of
        {module, _} -> {ok, ModName};
        {error, not_purged} ->
            %% Generated module atoms are source-content addressed. If OTP
            %% cannot purge an already-resident copy, that copy is the module
            %% this implementation message names, so loading is idempotent.
            {ok, ModName};
        {error, Reason} ->
            {error, {device_load_failed, Reason}}
    end.

%%% --------------------------------------------------------------------
%%% Compatibility checks
%%% --------------------------------------------------------------------

%% @doc Verify that a device is compatible with the current machine.
verify_device_compatibility(Msg, Opts) ->
    ?event(device_load, {verifying_device_compatibility, {msg, Msg}}, Opts),
    Required =
        lists:filtermap(
            fun({<<"requires-", Key/binary>>, Value}) ->
                {true,
                    {
                        hb_util:key_to_atom(
                            hb_ao:normalize_key(Key),
                            new_atoms
                        ),
                        hb_cache:ensure_loaded(Value, Opts)
                    }
                };
            (_) -> false
            end,
            hb_maps:to_list(Msg, Opts)
        ),
    ?event(device_load,
        {discerned_requirements,
            {required, Required},
            {msg, Msg}
        },
        Opts
    ),
    FailedToMatch =
        lists:filtermap(
            fun({Property, Value}) ->
                SystemValue = erlang:system_info(Property),
                Res = hb_ao:normalize_key(SystemValue) == hb_ao:normalize_key(Value),
                case Res of
                    true -> false;
                    false -> {true, {Property, Value}}
                end
            end,
            Required
        ),
    case FailedToMatch of
        [] -> ok;
        _ -> {error, {failed_requirements, FailedToMatch}}
    end.

%%% --------------------------------------------------------------------
%%% Device-store cache (key -> generated module atom)
%%% --------------------------------------------------------------------

-define(DEV_CACHE_PREFIX, <<"devices/">>).

%% @doc Look up a previously-resolved generated module atom for a name
%% or specification ID. Returns `not_found' if either the cache miss or
%% the cached BEAM is no longer loaded.
lookup_device_cache(Ref, Opts) ->
    case device_store(Opts) of
        undefined -> not_found;
        Store ->
            Key = <<?DEV_CACHE_PREFIX/binary, Ref/binary>>,
            case hb_store:read(Store, Key, Opts) of
                {ok, ModBin} when is_binary(ModBin) ->
                    case hb_packager:is_generated_module(ModBin) of
                        true ->
                            try binary_to_existing_atom(ModBin, utf8) of
                                ModName ->
                                    %% Generated BEAMs are loaded with
                                    %% `erlang:load_module', which keeps them in
                                    %% memory but does NOT register a code path.
                                    %% `code:is_loaded/1' is the right check.
                                    case code:is_loaded(ModName) of
                                        {file, _} -> {ok, ModName};
                                        false ->
                                            case code:ensure_loaded(ModName) of
                                                {module, ModName} -> {ok, ModName};
                                                _ -> not_found
                                            end
                                    end
                            catch _:_ -> not_found
                            end;
                        false -> not_found
                    end;
                _ -> not_found
            end
    end.

cache_device_module(_Ref, _ModName, _Opts) when _ModName =:= undefined ->
    ok;
cache_device_module(Ref, ModName, Opts) when is_atom(ModName) ->
    cache_device_module(Ref, atom_to_binary(ModName, utf8), Opts);
cache_device_module(Ref, ModBin, Opts) when is_binary(Ref), is_binary(ModBin) ->
    case device_store(Opts) of
        undefined -> ok;
        Store ->
            hb_store:write(
                Store,
                #{ <<?DEV_CACHE_PREFIX/binary, Ref/binary>> => ModBin },
                Opts
            )
    end.

%%% --------------------------------------------------------------------
%%% Store helpers
%%% --------------------------------------------------------------------

%% @doc The fast volatile cache of name/ID -> loaded module atom.
device_store(Opts) ->
    hb_opts:get(device_store, hb_opts:get(store, undefined, Opts), Opts).

%% @doc The build-time fs store containing preloaded specs/impls + index.
preloaded_store(Opts) ->
    hb_opts:get(preloaded_store, undefined, Opts).

%% @doc The committed ID of the preloaded-store's `Device-Index' message.
preloaded_index_id(Opts) ->
    hb_opts:get(preloaded_devices_index, undefined, Opts).

%% @doc Build an Opts map whose store list has the preloaded-store
%% prepended, so cache reads/matches see preloaded artifacts first.
with_preloaded_store(Opts) ->
    case preloaded_store(Opts) of
        undefined -> Opts;
        Pre ->
            Existing = hb_opts:get(store, [], Opts),
            Opts#{ <<"store">> => [Pre | listify(Existing)] }
    end.

listify(L) when is_list(L) -> L;
listify(M) when is_map(M) -> [M];
listify(undefined) -> [];
listify(X) -> [X].

trusted_signers(Opts) ->
    case hb_opts:get(trusted_device_signers, undefined, Opts) of
        Value when Value =:= undefined orelse Value =:= [] ->
            default_trusted_signers(Opts);
        Configured -> Configured
    end.

-ifdef(TEST).
%% EUnit starts many isolated nodes with throwaway wallets, while the
%% preloaded store is signed once during compilation.
default_trusted_signers(_Opts) ->
    all.
-else.
default_trusted_signers(Opts) ->
    %% Default: trust the node wallet's address.
    try [hb:address(node_wallet(Opts))]
    catch _:_ -> [] end.

node_wallet(Opts) ->
    case hb_opts:get(priv_wallet, undefined, Opts) of
        undefined ->
            hb:wallet(hb_opts:get(priv_key_location, hb_opts:get(priv_key_location), Opts));
        Wallet ->
            Wallet
    end.
-endif.

signer_trusted([], _TrustedSigners) ->
    false;
signer_trusted(_Signers, all) ->
    true;
signer_trusted(Signers, List) when is_list(List) ->
    case lists:member(all, List) of
        true -> true;
        false ->
            lists:any(
                fun(Signer) -> lists:member(Signer, List) end,
                Signers
            )
    end;
signer_trusted(_Signers, _TrustedSigners) ->
    false.

%% @doc Get the info map for a device, optionally giving it a message if the
%% device's info function is parameterized by one.
info(Msg, Opts) ->
    info(message_to_device(Msg, Opts), Msg, Opts).
info(DevMod, Msg, Opts) ->
	%?event({calculating_info, {dev, DevMod}, {msg, Msg}}),
    case find_exported_function(Msg, DevMod, info, 2, Opts) of
		{ok, Fun} ->
			Res = apply(Fun, truncate_args(Fun, [Msg, Opts])),
			% ?event({
            %     info_result,
            %     {dev, DevMod},
            %     {args, truncate_args(Fun, [Msg])},
            %     {result, Res}
            % }),
			Res;
		not_found -> #{}
	end.

%% @doc Determine if a device is a `direct access': If there is a literal key
%% in the message's Erlang map representation, will it always be returned?
is_direct_key_access(Base, Req, Opts) ->
    is_direct_key_access(Base, Req, Opts, unknown).
is_direct_key_access(Base, Req, Opts, MaybeStore) when ?IS_ID(Base) ->
    Store =
        if MaybeStore =:= unknown -> hb_opts:get(store, no_viable_store, Opts);
        true -> MaybeStore
        end,
    DevPath =
        hb_util:ok_or(
            hb_store:resolve(Store, [Base, <<"device">>], Opts),
            [Base, <<"device">>]
        ),
    case hb_store:read(Store, DevPath, Opts) of
        {ok, Dev} ->
            do_is_direct_key_access(Dev, Req, Opts);
        {error, not_found} ->
            fallback_direct_key_access(Store, Base, Req, Opts)
    end;
is_direct_key_access(Base, Req, Opts, _) when is_map(Base) ->
    do_is_direct_key_access(hb_maps:find(<<"device">>, Base, Opts), Req, Opts).

fallback_direct_key_access(Store, Base, Req, Opts) ->
    case hb_store:type(Store, Base, Opts) of
        {error, not_found} -> unknown;
        {ok, _} -> do_is_direct_key_access(<<"message@1.0">>, Req, Opts)
    end.

do_is_direct_key_access(DevRes, #{ <<"path">> := Key }, Opts) ->
    do_is_direct_key_access(DevRes, Key, Opts);
do_is_direct_key_access({_Status, DevRes}, Key, Opts) ->
    do_is_direct_key_access(DevRes, Key, Opts);
do_is_direct_key_access(not_found, Key, Opts) ->
    do_is_direct_key_access(<<"message@1.0">>, Key, Opts);
do_is_direct_key_access(error, Key, Opts) ->
    do_is_direct_key_access(<<"message@1.0">>, Key, Opts);
do_is_direct_key_access(<<"message@1.0">>, Key, _Opts) ->
    not lists:member(Key, ?MESSAGE_KEYS);
do_is_direct_key_access(Dev, NormKey, Opts) ->
    ?event(debug_read_cached, {calculating_info, {device, Dev}}),
    case info(#{ <<"device">> => Dev}, Opts) of
        Info = #{ exports := Exports }
            when not is_map_key(handler, Info) andalso not is_map_key(default, Info) ->
            ?event(debug_read_cached,
                {exports,
                    {device, Dev},
                    {key, NormKey},
                    {exports, Exports}
                }
            ),
            not lists:member(NormKey, Exports ++ ?MESSAGE_KEYS);
        _ -> false
    end.

%% @doc The default device is the identity device. We refer to it by
%% its public name — `message@1.0' — so it is resolved through the
%% normal {@link load/2} path and ends up as the generated
%% `_hb_device_message_*' module rather than the source `dev_message'.
default() -> <<"message@1.0">>.
