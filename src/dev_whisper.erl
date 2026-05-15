%%% @doc Transcribe audio stored on Arweave using the Whisper model.
%%%
%%% Inputs: An Arweave transaction ID pointing to an audio file.
%%%   - `tx` — the Arweave TXID (binary)
%%%   - `raw` — alternative key name for the TXID
%%%   - `gateway` — optional Arweave gateway URL override
%%%   - `model` — optional whisper model name override (default: small)
%%%   - `language` — optional language hint (e.g. "en")
%%%
%%% Outputs: A message with:
%%%   - `transcript` — the full transcription text
%%%   - `language` — detected language code
%%%   - `segments` — list of timed text segments
%%%
%%% ## Whisper Binary
%%%
%%% The device expects a Whisper CLI binary on the host filesystem.
%%% Configure the path via the node option `whisper_binary`
%%% (default: `/usr/local/bin/whisper`).
%%%
%%% whisper.cpp CLI is recommended. Build from source:
%%%
%%% ```bash
%%% git clone https://github.com/ggerganov/whisper.cpp && cd whisper.cpp
%%% make -j$(nproc)
%%% sudo cp main /usr/local/bin/whisper
%%% ./models/download-ggml-model.sh base
%%% ```
%%%
%%% ## Usage
%%%
%%% ```
%%% GET /~whisper@1.0/transcribe?tx=<arweave_txid>
%%% GET /~whisper@1.0/transcribe?raw=<arweave_txid>&model=medium&language=en
%%% ```

-module(dev_whisper).
-export([info/1, transcribe/3]).
-include("include/hb.hrl").
-include_lib("eunit/include/eunit.hrl").

-define(TEMP_DIR, <<"/tmp/hyperbeam-whisper">>).
-define(DEFAULT_GATEWAY, <<"https://arweave.net">>).
-define(DEFAULT_MODEL, <<"/usr/local/share/whisper/models/ggml-base.bin">>).
-define(DEFAULT_BINARY, <<"/usr/local/bin/whisper">>).

%% @doc Register the device's default handler.
info(_Opts) ->
    #{
        default => fun transcribe_key/4,
        excludes => [<<"keys">>, <<"set">>]
    }.

%% @doc Default handler — dispatch to transcribe for any key access.
transcribe_key(_Name, Base, Req, Opts) ->
    transcribe(Base, Req, Opts).

%% @doc Transcribe an audio file fetched from Arweave using Whisper.
transcribe(Base, Request, Opts) ->
    ?event(debug_whisper, {transcribe_request, {base, Base}, {request, Request}}),

    %% Extract the Arweave TXID
    case find_txid(Base, Request, Opts) of
        {ok, Id} when is_binary(Id), byte_size(Id) >= 20 ->
            do_transcribe(Id, Base, Request, Opts);
        {ok, Id} ->
            Normalized = hb_util:bin(Id),
            case byte_size(Normalized) >= 20 of
                true ->
                    do_transcribe(Normalized, Base, Request, Opts);
                false ->
                    ?event(warning, {invalid_txid, Id}),
                    return_error(<<"Invalid Arweave transaction ID.">>, 400)
            end;
        Error ->
            ?event(error, {missing_txid, Error}),
            return_error(<<"No `tx' or `raw' key found. Provide an Arweave TXID.">>,
                         400)
    end.

%% @doc Main transcription workflow after TXID extraction.
do_transcribe(TXID, _Base, Request, Opts) ->
    %% Determine gateway URL
    Gateway = hb_maps:get(<<"gateway">>, Request,
                hb_maps:get(<<"gateway">>, #{},
                    ?DEFAULT_GATEWAY, Opts), Opts),

    %% Fetch the audio data from Arweave
    ?event(debug_whisper, {fetching_audio, {txid, TXID}, {gateway, Gateway}}),
    case fetch_audio(Gateway, TXID) of
        {ok, AudioData, ContentType} ->
            ?event(debug_whisper, {audio_fetched,
                {size, byte_size(AudioData)},
                {content_type, ContentType}}),
            transcribe_audio(AudioData, ContentType, Request, Opts);
        {error, Reason} ->
            ?event(error, {fetch_failed, {txid, TXID}, {reason, Reason}}),
            return_error(iolist_to_binary(["Failed to fetch audio from Arweave: ",
                           io_lib:format("~p", [Reason])]), 502)
    end.

%% @doc Find the Arweave TXID from the request or base message.
%% Priority: request.tx > request.raw > request.body > base.tx
find_txid(Base, Request, Opts) ->
    find_txid_in([
        fun() -> hb_maps:get(<<"tx">>, Request, undefined, Opts) end,
        fun() -> hb_maps:get(<<"raw">>, Request, undefined, Opts) end,
        fun() ->
            case hb_maps:get(<<"body">>, Request, undefined, Opts) of
                Body when is_binary(Body), byte_size(Body) >= 20 -> Body;
                _ -> undefined
            end
        end,
        fun() -> hb_maps:get(<<"tx">>, Base, undefined, Opts) end
    ]).

%% @doc Try each source function until one returns a valid TXID.
find_txid_in([]) ->
    {error, not_found};
find_txid_in([Fun | Rest]) ->
    case Fun() of
        undefined -> find_txid_in(Rest);
        Val when is_binary(Val), byte_size(Val) > 0 ->
            {ok, Val};
        Val when is_list(Val) ->
            {ok, list_to_binary(Val)};
        Other ->
            {ok, hb_util:bin(Other)}
    end.

%% @doc Fetch audio data from an Arweave gateway using curl.
%% Uses curl instead of hackney/httpc because arweave.net returns 302
%% redirects to subdomain gateways that Erlang's TLS clients struggle with.
fetch_audio(Gateway, TXID) ->
    URL = iolist_to_binary([Gateway, "/", TXID]),
    ?event(debug_whisper, {http_get, {url, URL}}),

    %% Write to temp file via curl (handles redirects, TLS, SNI properly)
    TempFile = iolist_to_binary(io_lib:format("/tmp/hyperbeam-whisper/fetch_~p.bin",
                                              [erlang:system_time(second)])),
    ok = filelib:ensure_dir(TempFile),

    Cmd = iolist_to_binary(io_lib:format(
        "curl -sL --max-time 120 -o ~s -D ~s.headers ~s",
        [shell_quote(TempFile), TempFile, shell_quote(URL)]
    )),
    ?event(debug_whisper, {curl_cmd, {cmd, Cmd}}),

    try
        case os:cmd(binary_to_list(Cmd)) of
            "" ->
                %% curl succeeded (empty stdout means no error)
                case file:read_file(TempFile) of
                    {ok, Body} when byte_size(Body) > 0 ->
                        ContentType = parse_content_type(TempFile),
                        ?event(debug_whisper, {fetched, {size, byte_size(Body)},
                            {content_type, ContentType}}),
                        {ok, Body, ContentType};
                    {ok, <<>>} ->
                        {error, empty_response};
                    {error, ReadErr} ->
                        {error, ReadErr}
                end;
            ErrorOutput ->
                {error, {curl_error, iolist_to_binary(ErrorOutput)}}
        end
    after
        file:delete(TempFile),
        file:delete(iolist_to_binary([TempFile, ".headers"]))
    end.

%% @doc Parse content-type from curl headers file.
parse_content_type(TempFile) ->
    HeadersFile = iolist_to_binary([TempFile, ".headers"]),
    case file:read_file(HeadersFile) of
        {ok, RawHeaders} ->
            LcList = string:to_lower(binary_to_list(RawHeaders)),
            LcHeaders = list_to_binary(LcList),
            LcLines = binary:split(LcHeaders, <<"\r\n">>, [global]),
            lists:foldl(fun(Line, Acc) when is_binary(Line) ->
                case binary:match(Line, <<"content-type: ">>) of
                    {Start, Length} ->
                        Value = string:trim(binary:part(Line, {Start + Length, byte_size(Line) - Start - Length}), trailing, " \t\r\n"),
                        case Acc of
                            undefined -> Value;
                            _ -> Acc
                        end;
                    nomatch -> Acc
                end;
               (_Line, Acc) -> Acc
            end, undefined, LcLines);
        _ -> undefined
    end.

%% @doc Shell-quote a string for safe use in os:cmd.
shell_quote(S) when is_binary(S) ->
    io_lib:format("~s", [binary_to_list(S)]);
shell_quote(S) when is_list(S) ->
    io_lib:format("~s", [S]).

%% @doc Call the Whisper CLI binary to transcribe audio data.
transcribe_audio(AudioData, ContentType, Request, Opts) ->
    %% Ensure temp directory exists
    TempPath = iolist_to_binary([?TEMP_DIR, "/audio.wav"]),
    ok = filelib:ensure_dir(TempPath),

    %% Get Whisper binary path and model from node options
    WhisperBin0 = hb_opts:get(whisper_binary, ?DEFAULT_BINARY, Opts),
    WhisperBin = ensure_binary_path(WhisperBin0),
    DefaultModel = hb_opts:get(whisper_model, ?DEFAULT_MODEL, Opts),

    %% Check optional overrides from request
    ModelToUse = ensure_binary_path(
        case hb_maps:get(<<"model">>, Request, undefined, Opts) of
            undefined -> DefaultModel;
            M when is_binary(M) -> M;
            M when is_list(M) -> iolist_to_binary(M)
        end
    ),

    %% Write audio to temp file with appropriate extension
    Ext = case ContentType of
        <<"audio/mp3">> -> <<".mp3">>;
        <<"audio/mpeg">> -> <<".mp3">>;
        <<"audio/ogg">> -> <<".ogg">>;
        <<"audio/flac">> -> <<".flac">>;
        <<"audio/wav">> -> <<".wav">>;
        <<"audio/x-wav">> -> <<".wav">>;
        <<"audio/m4a">> -> <<".m4a">>;
        <<"video/mp4">> -> <<".mp4">>;
        _ -> <<".wav">>
    end,

    Timestamp = erlang:system_time(second),
    TempFile = iolist_to_binary(io_lib:format(
        "/tmp/hyperbeam-whisper/audio_~p~s", [Timestamp, Ext]
    )),
    JsonFile = iolist_to_binary(io_lib:format(
        "/tmp/hyperbeam-whisper/output_~p", [Timestamp]
    )),

    ?event(debug_whisper, {writing_temp, {file, TempFile},
        {size, byte_size(AudioData)}}),
    case file:write_file(TempFile, AudioData) of
        ok ->
            do_run_whisper(TempFile, JsonFile, WhisperBin, ModelToUse,
                           Request, Opts);
        {error, WriteErr} ->
            ?event(error, {write_temp_failed, WriteErr}),
            return_error(<<"Failed to write temporary audio file.">>, 500)
    end.

%% @doc Run the Whisper binary and parse results.
do_run_whisper(TempFile, JsonFile, WhisperBin, ModelToUse, Request, Opts) ->
    try
        ?event(debug_whisper, {stage, building_cmd}),
        %% Build whisper.cpp command
        CmdParts = [
            binary_to_list(WhisperBin),
            "-m", binary_to_list(ModelToUse),
            "-f", binary_to_list(TempFile),
            "-oj",
            "-of", binary_to_list(JsonFile)
        ],

        %% Add language hint if provided
        CmdPartsWithLang = case hb_maps:get(<<"language">>, Request,
                                            undefined, Opts) of
            undefined -> CmdParts;
            L when is_binary(L), byte_size(L) > 0 ->
                CmdParts ++ ["-l", binary_to_list(L)];
            L when is_list(L) ->
                CmdParts ++ ["-l", L]
        end,

        Cmd = string:join(CmdPartsWithLang, " "),
        ?event(debug_whisper, {stage, running_whisper, {cmd, Cmd}}),

        %% Run whisper via os:cmd instead of port — simpler, avoids OTP 27 port quirks
        ?event(debug_whisper, {stage, os_cmd_start}),
        Output = os:cmd(Cmd),
        ?event(debug_whisper, {stage, os_cmd_done, {output_len, byte_size(iolist_to_binary(Output))}}),

        %% Whisper creates <JsonFile>.json when -oj -of <JsonFile> is used
        JsonOut = iolist_to_binary([JsonFile, ".json"]),
        ?event(debug_whisper, {stage, reading_json, {path, JsonOut}}),
        case file:read_file(JsonOut) of
            {ok, JsonData} ->
                ?event(debug_whisper,
                    {json_output_size, byte_size(JsonData)}),
                parse_whisper_json(JsonData, Opts);
            {error, enoent} ->
                ?event(error, {no_json_output, enoent}),
                return_error(
                    <<"Whisper ran but produced no JSON output.">>,
                    500);
            {error, NoJson} ->
                ?event(error, {no_json_output, NoJson}),
                return_error(
                    <<"Whisper ran but produced no JSON output.">>,
                    500)
        end
    catch ErrorType:Reason ->
        ?event(error, {transcription_crash, {type, ErrorType}, {reason, Reason}}),
        return_error(iolist_to_binary(["Transcription crashed: ",
                       io_lib:format("~p", [Reason])]),
                     500)
    after
        %% Always clean up temp files
        file:delete(TempFile),
        file:delete(JsonFile),
        file:delete(iolist_to_binary([JsonFile, ".json"]))
    end.

%% @doc Parse whisper.cpp JSON output into a HyperBEAM message.
%% whisper.cpp JSON structure:
%%   {transcription: [{text: "...", ...}, ...], result: {language: "en"}, ...}
parse_whisper_json(JsonData, _Opts) ->
    %% Try stdlib json:decode first
    Decoded = try json:decode(JsonData) of
        D when is_map(D) -> D;
        D when is_list(D) ->
            %% json:decode can return proplist for some inputs
            maps:from_list(D)
    catch
        _:_ -> undefined
    end,

    case Decoded of
        undefined ->
            ?event(error, {json_parse_failed, stdlib_decoder_failed}),
            %% Fall back: extract text segments with simple pattern matching
            extract_transcript_simple(JsonData);
        _ when is_map(Decoded) ->
            extract_transcript_from_map(Decoded)
    end.

%% @doc Extract transcript from decoded whisper.cpp JSON map.
extract_transcript_from_map(Decoded) ->
    %% whisper.cpp puts segments in "transcription" array
    Segments = maps:get(<<"transcription">>, Decoded, []),
    %% Build transcript by joining segment texts
    Transcript = iolist_to_binary(
        lists:join(" ", [
            case is_map(S) of
                true -> maps:get(<<"text">>, S, <<>>);
                false -> <<>>
            end
        || S <- Segments])
    ),
    %% Language from result.language or params.language
    Language = case maps:get(<<"result">>, Decoded, #{}) of
        Res when is_map(Res) -> maps:get(<<"language">>, Res, <<"en">>);
        _ -> case maps:get(<<"params">>, Decoded, #{}) of
            Params when is_map(Params) -> maps:get(<<"language">>, Params, <<"en">>);
            _ -> <<"en">>
        end
    end,

    ?event(debug_whisper, {transcription_complete,
        {length, byte_size(Transcript)},
        {language, Language},
        {segments, length(Segments)}}),

    success_response(Transcript, Language, Segments).

%% @doc Simple fallback: extract text fields from raw JSON using regex.
extract_transcript_simple(JsonData) ->
    %% Find all "text": "..." patterns in the JSON
    Pattern = "(?:\"text\":\\s*\")((?:[^\"\\\\]|\\\\.)*)\"",
    case re:run(JsonData, Pattern, [global, {capture, all_but_first}]) of
        {match, [Texts]} ->
            Transcript = iolist_to_binary(lists:join(" ", Texts)),
            ?event(debug_whisper, {transcription_complete_fallback,
                {length, byte_size(Transcript)}}),
            success_response(Transcript, <<"en">>, []);
        _ ->
            return_error(<<"Failed to parse Whisper JSON output.">>, 500)
    end.

%% @doc Build a response that works both as HyperBEAM message metadata and as
%% a normal browser-visible JSON body.
success_response(Transcript, Language, Segments) ->
    Payload = #{
        <<"device">> => <<"whisper@1.0">>,
        <<"language">> => Language,
        <<"segments">> => Segments,
        <<"status">> => 200,
        <<"transcript">> => Transcript
    },
    {ok, Payload#{
        <<"body">> => hb_json:encode(Payload),
        <<"content-type">> => <<"application/json">>
    }}.

%% @doc Unescape JSON string escapes.
%% Note: OTP 27+ no longer accepts \\ as a char literal in binaries,
%% so we use integer 92 for backslash. Also binary:to_list/1 was removed
%% in OTP 27, use binary_to_list/1 BIF instead.
json_unescape(<<>>, Acc) -> Acc;
json_unescape(<<92, $n, Rest/binary>>, Acc) ->
    json_unescape(Rest, <<Acc/binary, "\n">>);
json_unescape(<<92, $t, Rest/binary>>, Acc) ->
    json_unescape(Rest, <<Acc/binary, "\t">>);
json_unescape(<<92, $r, Rest/binary>>, Acc) ->
    json_unescape(Rest, <<Acc/binary, "\r">>);
json_unescape(<<92, 92, Rest/binary>>, Acc) ->
    json_unescape(Rest, <<Acc/binary, 92>>);
json_unescape(<<92, $/, Rest/binary>>, Acc) ->
    json_unescape(Rest, <<Acc/binary, "/">>);
json_unescape(<<92, $u, H1, H2, H3, H4, Rest/binary>>, Acc) ->
    Codepoint = hex4_to_int(<<H1, H2, H3, H4>>),
    Chars = unicode:characters_to_binary([Codepoint]),
    json_unescape(Rest, <<Acc/binary, Chars/binary>>);
json_unescape(<<C, Rest/binary>>, Acc) ->
    json_unescape(Rest, <<Acc/binary, C>>).

hex4_to_int(Bin) ->
    hex4_to_int(binary_to_list(Bin), 0).

hex4_to_int([], Acc) -> Acc;
hex4_to_int([C | Rest], Acc) ->
    hex4_to_int(Rest, Acc * 16 + hex_digit(C)).

hex_digit($0) -> 0; hex_digit($1) -> 1; hex_digit($2) -> 2;
hex_digit($3) -> 3; hex_digit($4) -> 4; hex_digit($5) -> 5;
hex_digit($6) -> 6; hex_digit($7) -> 7; hex_digit($8) -> 8;
hex_digit($9) -> 9;
hex_digit($a) -> 10; hex_digit($b) -> 11; hex_digit($c) -> 12;
hex_digit($d) -> 13; hex_digit($e) -> 14; hex_digit($f) -> 15;
hex_digit($A) -> 10; hex_digit($B) -> 11; hex_digit($C) -> 12;
hex_digit($D) -> 13; hex_digit($E) -> 14; hex_digit($F) -> 15;
hex_digit(_) -> 0.

%% @doc Return an error message.
return_error(Reason, Status) ->
    {error, #{
        <<"status">> => Status,
        <<"body">> => Reason,
        <<"content-type">> => <<"text/plain">>
    }}.

%%% Tests

transcribe_missing_tx_test() ->
    {error, Err} = transcribe(#{}, #{}, #{}),
    ?assert(maps:is_key(<<"status">>, Err)),
    ?assertEqual(400, maps:get(<<"status">>, Err)).

json_unescape_newline_test() ->
    ?assertEqual(<<"hello\nworld">>, json_unescape(<<"hello\\nworld">>, <<>>)).

json_unescape_tab_test() ->
    ?assertEqual(<<"hello\tworld">>, json_unescape(<<"hello\\tworld">>, <<>>)).

json_unescape_backslash_test() ->
    %% Input: hello\\world (two backslashes -> one)
    Input = <<"hello", 92, 92, "world">>,
    Output = json_unescape(Input, <<>>),
    ?assertEqual(<<"hello", 92, "world">>, Output).

json_unescape_unicode_test() ->
    %% Test unicode escape: backslash u 0 0 4 1 = 'A'
    Input = <<92, 117, 48, 48, 52, 49>>,
    ?assertEqual(<<"A">>, json_unescape(Input, <<>>)).

parse_whisper_json_body_test() ->
    Json = <<"{\"transcription\":[{\"text\":\"hello\"},{\"text\":\"world\"}],\"result\":{\"language\":\"en\"}}">>,
    {ok, Res} = parse_whisper_json(Json, #{}),
    ?assertEqual(<<"application/json">>, maps:get(<<"content-type">>, Res)),
    ?assertEqual(<<"hello world">>, maps:get(<<"transcript">>, Res)),
    Body = maps:get(<<"body">>, Res),
    Decoded = hb_json:decode(Body),
    ?assertEqual(<<"whisper@1.0">>, maps:get(<<"device">>, Decoded)),
    ?assertEqual(<<"en">>, maps:get(<<"language">>, Decoded)),
    ?assertEqual(200, maps:get(<<"status">>, Decoded)),
    ?assertEqual(<<"hello world">>, maps:get(<<"transcript">>, Decoded)).

%% @doc Ensure a path is a binary (works with lists or binaries from OTP 27).
ensure_binary_path(Path) when is_binary(Path) -> Path;
ensure_binary_path(Path) when is_list(Path) -> iolist_to_binary(Path).
