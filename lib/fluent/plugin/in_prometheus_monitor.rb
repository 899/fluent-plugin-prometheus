require 'fluent/plugin/input'
require 'fluent/plugin/in_monitor_agent'
require 'fluent/plugin/prometheus'

module Fluent::Plugin
  class PrometheusMonitorInput < Fluent::Plugin::Input
    Fluent::Plugin.register_input('prometheus_monitor', self)

    helpers :timer

    config_param :interval, :time, :default => 5
    attr_reader :registry

    def initialize
      super
      @registry = ::Prometheus::Client.registry
    end

    def configure(conf)
      super
      hostname = Socket.gethostname
      expander = Fluent::Prometheus.placeholder_expander(log)
      placeholders = expander.prepare_placeholders({'hostname' => hostname})
      @base_labels = Fluent::Prometheus.parse_labels_elements(conf)
      @base_labels.each do |key, value|
        @base_labels[key] = expander.expand(value, placeholders)
      end

      if defined?(Fluent::Plugin) && defined?(Fluent::Plugin::MonitorAgentInput)
        # from v0.14.6
        @monitor_agent = Fluent::Plugin::MonitorAgentInput.new
      else
        @monitor_agent = Fluent::MonitorAgentInput.new
      end

      buffer_queue_length = @registry.gauge(
        :fluentd_status_buffer_queue_length,
        'Current buffer queue length.')
      buffer_total_queued_size = @registry.gauge(
        :fluentd_status_buffer_total_bytes,
        'Current total size of queued buffers.')
      retry_counts = @registry.gauge(
        :fluentd_status_retry_count,
        'Current retry counts.')

      @monitor_info = {
        'buffer_queue_length' => buffer_queue_length,
        'buffer_total_queued_size' => buffer_total_queued_size,
        'retry_count' => retry_counts,
      }
    end

    def start
      super
      timer_execute(:in_prometheus_monitor, @interval, &method(:update_monitor_info))
    end

    def update_monitor_info
      @monitor_agent.plugins_info_all.each do |info|
        @monitor_info.each do |name, metric|
          if info[name]
            metric.set(labels(info), info[name])
          end
        end
      end
    end

    def labels(plugin_info)
      @base_labels.merge(
        plugin_id: plugin_info["plugin_id"],
        plugin_category: plugin_info["plugin_category"],
        type: plugin_info["type"],
      )
    end
  end
end
