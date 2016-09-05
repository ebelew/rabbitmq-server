%% The contents of this file are subject to the Mozilla Public License
%% Version 1.1 (the "License"); you may not use this file except in
%% compliance with the License. You may obtain a copy of the License
%% at http://www.mozilla.org/MPL/
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and
%% limitations under the License.
%%
%% The Original Code is RabbitMQ.
%%
%% The Initial Developer of the Original Code is GoPivotal, Inc.
%% Copyright (c) 2016 Pivotal Software, Inc.  All rights reserved.
%%
-module(metrics_SUITE).
-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").


all() ->
    [
      {group, non_parallel_tests}
    ].

groups() ->
    [
      {non_parallel_tests, [], [
                                connection,
                                channel,
                                channel_connection_close,
                                channel_queue_exchange_consumer
                               ]}
    ].

%% -------------------------------------------------------------------
%% Testsuite setup/teardown.
%% -------------------------------------------------------------------

merge_app_env(Config) ->
    rabbit_ct_helpers:merge_app_env(Config,
                                    {rabbit, [
                                              {collect_statistics, fine},
                                              {collect_statistics_interval, 500}
                                             ]}).
init_per_suite(Config) ->
    rabbit_ct_helpers:log_environment(),
    Config1 = rabbit_ct_helpers:set_config(Config, [
        {rmq_nodename_suffix, ?MODULE}
      ]),
    rabbit_ct_helpers:run_setup_steps(Config1,
      [ fun merge_app_env/1 ] ++
      rabbit_ct_broker_helpers:setup_steps()).

end_per_suite(Config) ->
    rabbit_ct_helpers:run_teardown_steps(Config,
      rabbit_ct_broker_helpers:teardown_steps()).

init_per_group(_, Config) ->
    Config.

end_per_group(_, Config) ->
    Config.

init_per_testcase(Testcase, Config) ->
    rabbit_ct_helpers:testcase_started(Config, Testcase).

end_per_testcase(Testcase, Config) ->
    rabbit_ct_helpers:testcase_finished(Config, Testcase).


%% -------------------------------------------------------------------
%% Testcases.
%% -------------------------------------------------------------------

read_table_rpc(Config, Table) ->
    rabbit_ct_broker_helpers:rpc(Config, 0, ?MODULE, read_table, [Table]).

read_table(Table) ->
    ets:tab2list(Table).

% node_stats tests are in the management_agent repo


connection(Config) ->
    Conn = rabbit_ct_client_helpers:open_unmanaged_connection(Config),
    [_] = read_table_rpc(Config, connection_created),
    [_] = read_table_rpc(Config, connection_metrics),
    [_] = read_table_rpc(Config, connection_coarse_metrics),
    ok = rabbit_ct_client_helpers:close_connection(Conn),
    [] = read_table_rpc(Config, connection_created),
    [] = read_table_rpc(Config, connection_metrics),
    [] = read_table_rpc(Config, connection_coarse_metrics).

channel(Config) ->
    Conn = rabbit_ct_client_helpers:open_unmanaged_connection(Config),
    {ok, Chan} = amqp_connection:open_channel(Conn),
    [_] = read_table_rpc(Config, channel_created),
    [_] = read_table_rpc(Config, channel_metrics),
    [_] = read_table_rpc(Config, channel_process_metrics),
    ok = amqp_channel:close(Chan),
    [] = read_table_rpc(Config, channel_created),
    [] = read_table_rpc(Config, channel_metrics),
    [] = read_table_rpc(Config, channel_process_metrics),
    ok = rabbit_ct_client_helpers:close_connection(Conn).

channel_connection_close(Config) ->
    Conn = rabbit_ct_client_helpers:open_unmanaged_connection(Config),
    {ok, _} = amqp_connection:open_channel(Conn),
    [_] = read_table_rpc(Config, channel_created),
    [_] = read_table_rpc(Config, channel_metrics),
    [_] = read_table_rpc(Config, channel_process_metrics),
    ok = rabbit_ct_client_helpers:close_connection(Conn),
    [] = read_table_rpc(Config, channel_created),
    [] = read_table_rpc(Config, channel_metrics),
    [] = read_table_rpc(Config, channel_process_metrics).

channel_queue_exchange_consumer(Config) ->
    Conn = rabbit_ct_client_helpers:open_unmanaged_connection(Config),
    {ok, Chan} = amqp_connection:open_channel(Conn),
    Declare = #'queue.declare'{queue = <<"my_queue">>},
    #'queue.declare_ok'{} = amqp_channel:call(Chan, Declare),
    % need to publish for exchange metrics to be populated
    Publish = #'basic.publish'{routing_key = <<"my_queue">>},
    amqp_channel:call(Chan, Publish, #amqp_msg{payload = <<"hello">>}),
    timer:sleep(1000), % TODO: send emit_stats message to channel instead of sleeping?
    [_] = read_table_rpc(Config, channel_exchange_metrics),
    [_] = read_table_rpc(Config, channel_queue_exchange_metrics),
    % need to get and wait for timer for queue metrics to be populated
    Get = #'basic.get'{queue = <<"my_queue">>, no_ack=true},
    {#'basic.get_ok'{}, #amqp_msg{payload = <<"hello">>}} = amqp_channel:call(Chan, Get),
    timer:sleep(1000), % TODO: send emit_stats message to channel instead of sleeping?
    [_] = read_table_rpc(Config, channel_queue_metrics),

    Sub = #'basic.consume'{queue = <<"my_queue">>},
      #'basic.consume_ok'{consumer_tag = _} =
        amqp_channel:call(Chan, Sub),

    [_] = read_table_rpc(Config, consumer_created),
    ok = rabbit_ct_client_helpers:close_connection(Conn),
    % ensure cleanup happened
    [] = read_table_rpc(Config, channel_exchange_metrics),
    [] = read_table_rpc(Config, channel_queue_exchange_metrics),
    [] = read_table_rpc(Config, channel_queue_metrics),
    [] = read_table_rpc(Config, consumer_created).