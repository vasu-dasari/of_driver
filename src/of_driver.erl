%%%-------------------------------------------------------------------
%%% @copyright (C) 1999-2013, Erlang Solutions Ltd
%%% @author Ruan Pienaar <ruan.pienaar@erlang-solutions.com>
%%% @doc 
%%% OF Driver API
%%% @end
%%%-------------------------------------------------------------------
-module(of_driver).
-copyright("2013, Erlang Solutions Ltd.").

-include_lib("of_protocol/include/of_protocol.hrl").
-include_lib("of_driver/include/of_driver.hrl").
-include_lib("of_driver/include/of_driver_logger.hrl").

-export([ allowed_ipaddr/1,
          grant_ipaddr/1,
          grant_ipaddr/3,
          revoke_ipaddr/1,
          get_allowed_ipaddrs/0,
          set_allowed_ipaddrs/1,
          send/2,
          sync_send/2,
          send_list/2,
          sync_send_list/2,
          close_connection/1,
          close_ipaddr/1,
          set_xid/2,
          gen_xid/1
        ]).

%%------------------------------------------------------------------
-spec allowed_ipaddr(IpAddr :: inet:ip_address()) -> ok | {error,einval}.
% @doc
allowed_ipaddr(IpAddr) ->
    of_driver_db:allowed(IpAddr).

-spec grant_ipaddr(IpAddr :: inet:ip_address()) -> ok | {error, einval}.
%% @doc
grant_ipaddr(IpAddr) ->
    % XXX might be better to apply defaults on read so old defaults are
    % not stored in the database
    CallbackMod = of_driver_utils:conf_default(callback_module,
                            fun erlang:is_atom/1, of_driver_default_handler),
    Opts = of_driver_utils:conf_default(init_opt, []),
    grant_ipaddr(IpAddr, CallbackMod, Opts).

-spec grant_ipaddr(IpAddr        :: inet:ip_address(), 
                   SwitchHandler :: term(),
                   Opts          :: list()) -> ok | {error, einval}.
%% @doc
grant_ipaddr(IpAddr, SwitchHandler, Opts) ->
    of_driver_db:grant_ipaddr(IpAddr, SwitchHandler, Opts).

-spec revoke_ipaddr(IpAddr :: inet:ip_address()) -> ok | {error, einval}.
%% @doc
revoke_ipaddr(IpAddr) -> 
    %% TODO: Closes any existing connections from IpAddr and calls
    %% appropriate callbacks.  Does nothing if IpAddr was not in the
    %% allowed list.
    of_driver_db:revoke_ipaddr(IpAddr).

-spec get_allowed_ipaddrs() -> [] | [allowance()].
%% @doc
get_allowed_ipaddrs() ->
    of_driver_db:get_allowed_ipaddrs().

-spec set_allowed_ipaddrs(Allowances :: list(allowance())) -> ok.
%% @doc
set_allowed_ipaddrs(Allowances) when is_list(Allowances) ->
    %% TODO: Close any existing connections from IpAddr that was removed.
    lists:map(fun({IpAddr,_SwitchHandler,_Opts}) -> inet_parse:ntoa(IpAddr) end, Allowances), %% Validation could be improved.
    PrevAllowed = of_driver_db:get_allowed_ipaddrs(),
    of_driver_db:clear_acl_list(),
    lists:foreach(fun({IpAddr,SwitchHandler,Opts}) ->
                        grant_ipaddr(IpAddr,SwitchHandler,Opts);
                     (_) ->
                        ok
                  end, Allowances),
    PrevAllowed.

-spec send(ConnectionPid :: term(), Msg :: #ofp_message{}) ->
                  ok | {error, Reason :: term()}.
%% @doc
send(ConnectionPid, #ofp_message{} = Msg) ->
    gen_server:cast(ConnectionPid,{send,Msg}).

-spec sync_send(ConnectionPid :: term(), Msg :: #ofp_message{}) -> 
                       {ok, Reply :: #ofp_message{} | noreply} |
                       {error, Reason :: term()}.
%% @doc
sync_send(ConnectionPid, #ofp_message{} = Msg) -> 
    of_driver_connection:sync_call(ConnectionPid,Msg).

-spec send_list(ConnectionPid :: term(), Messages :: list(Msg::#ofp_message{})) -> 
                       ok | {error, [ok | {error, Reason :: term()}]}.
%% @doc
send_list(ConnectionPid,[]) ->
    ok = gen_server:cast(ConnectionPid,barrier);
send_list(ConnectionPid,[H|T]) ->
    gen_server:cast(ConnectionPid,{send,H}),
    send_list(ConnectionPid,T).

-spec sync_send_list(ConnectionPid :: term(),Messages :: list(Msg::#ofp_message{})) -> 
                            {ok, [{ok, Reply :: #ofp_message{} | noreply}]} |
                            {error, Reason :: term(), [{ok, Reply :: #ofp_message{} | noreply} | {error, Reason :: term()}]}.
%% @doc
sync_send_list(ConnectionPid,Msgs) when is_list(Msgs) -> 
    Response = lists:foreach(fun(Msg) -> gen_server:call(ConnectionPid,{send,Msg}) end,Msgs),
    {ok,_BarrierResponse} = gen_server:call(ConnectionPid,barrier),
    {ok,Response}.

-spec close_connection(ConnectionPid :: term()) -> ok.
%% @doc
close_connection(ConnectionPid) -> %% ONLY CLOSE CONNECTION, might be main, or aux
    try 
      gen_server:call(ConnectionPid,close_connection) 
    catch 
      exit:{normal,{gen_server,call,[ConnectionPid,close_connection]}} ->
        ok
    end.

-spec close_ipaddr(IpAddr :: tuple()) -> ok.
%% @doc
close_ipaddr(_IpAddr) -> %% CLOSE ALL CONNECTIONS TO IP ADDRESS
    %% implement.
    %% FIND ALL IP ADDRESS CONNECTIONS AND DROP ALL!!!
    ok.

-spec set_xid(Msg :: #ofp_message{}, Xid :: integer()) -> {ok,#ofp_message{}}.
%% @doc
set_xid(#ofp_message{} = Msg, Xid) -> 
    {ok,Msg#ofp_message{ xid = Xid}}.

-spec gen_xid(ConnectionPid :: term()) -> {ok,Xid :: integer()}.
%% @doc
gen_xid(ConnectionPidPid) ->
    {ok,Xid} = gen_server:call(ConnectionPidPid,next_xid),
    {ok,Xid}.
