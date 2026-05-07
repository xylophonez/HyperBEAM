%%%-------------------------------------------------------------------
%% @doc The main HyperBEAM application module.
%% @end
%%%-------------------------------------------------------------------

-module(hb_app).

-behaviour(application).

-export([start/2, stop/1]).

-include("include/hb.hrl").

start(_StartType, _StartArgs) ->
    hb:init(),
    %% Eagerly resolve every device the build packaged. Doing this
    %% once on app start (sequentially) avoids the otherwise
    %% expensive `not_purged' race when many parallel tests hit the
    %% same generated atom for the first time.
    ok = hb_ao_device:preload_all(#{}),
    hb_sup:start_link(),
    ok = dev_scheduler_registry:start(),
    _TimestampServer = ar_timestamp:start(),
    {ok, _} = hb_http_server:start().

stop(_State) ->
    ok.