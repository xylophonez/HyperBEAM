#!/usr/bin/env escript

%%% @doc Build the in-repo `_build/preloaded-store' from `src/preloaded'.
%%%
%%% Invoked from the rebar.config post-compile hook so every build of
%%% HyperBEAM ends with a working `preloaded-store' on disk and a
%%% matching `_build/hb_preloaded_index.hrl' header. The store is signed
%%% with the node wallet, so the runtime's default device-author trust
%%% rule (trust the node wallet unless configured otherwise) applies.

main(_Args) ->
    add_code_paths(),
    {ok, _} = application:ensure_all_started(crypto),
    {ok, _} = application:ensure_all_started(asn1),
    {ok, _} = application:ensure_all_started(public_key),
    OutputDir = <<"_build/preloaded-store">>,
    SrcDir = "src/preloaded",
    Wallet = hb:wallet(),
    io:format("[preload] scanning ~s...~n", [SrcDir]),
    ExcludedRoots = excluded_roots(),
    Groups0 = hb_packager:scan([SrcDir], #{}),
    Groups =
        [
            G
        ||
            G = #{ root := Root } <- Groups0,
            not sets:is_element(Root, ExcludedRoots)
        ],
    case sets:size(ExcludedRoots) of
        0 -> ok;
        N -> io:format("[preload] excluding ~p root(s): ~p~n",
            [N, sets:to_list(ExcludedRoots)])
    end,
    io:format("[preload] packaging ~p devices~n", [length(Groups)]),
    Pkgs =
        lists:map(
            fun(G) ->
                Pkg = hb_packager:package(G, #{}),
                io:format("[preload]   ~s -> ~p~n",
                    [maps:get(device_name, Pkg),
                     maps:get(module_name, Pkg)]),
                Pkg
            end,
            Groups
        ),
    {ok, Result} =
        hb_preload:build_dir(Pkgs, Wallet, OutputDir, #{}),
    Index = maps:get(index, Result),
    io:format("[preload] index = ~s~n", [Index]),
    HeaderPath = <<"_build/hb_preloaded_index.hrl">>,
    ok = hb_preload:write_index_header(Index, HeaderPath),
    io:format("[preload] header written: ~s~n", [HeaderPath]),
    recompile_hb_opts(),
    halt(0).

excluded_roots() ->
    case os:getenv("HB_PRELOAD_EXCLUDE_ROOTS") of
        false -> sets:new();
        "" -> sets:new();
        Raw ->
            sets:from_list(
                [
                    list_to_atom(Name)
                ||
                    Name <- string:tokens(Raw, ", "),
                    Name =/= ""
                ]
            )
    end.

add_code_paths() ->
    code:add_pathsa(
        lists:sort(
            filelib:wildcard("_build/*/lib/*/ebin") ++
                filelib:wildcard("_build/*/plugins/*/ebin")
        )
    ).

recompile_hb_opts() ->
    lists:foreach(
        fun(Ebin) ->
            compile:file(
                "src/kernel/hb_opts.erl",
                [
                    debug_info,
                    {i, "src/kernel"},
                    {outdir, Ebin}
                ]
            )
        end,
        filelib:wildcard("_build/*/lib/hb/ebin")
    ).
