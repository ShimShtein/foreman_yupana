require 'rest-client'

module InsightsCloud
  module Async
    class InsightsFullSync < ::Actions::EntryAction
      include ::ForemanRhCloud::CloudAuth

      def plan
        sequence do
          concurrence do
            Organization.unscoped.each do |organization|
              next unless cloud_auth_available?(organization)
              sequence do
                # This can be turned off when we enable automatic status syncs
                # This step will query cloud inventory to retrieve inventory uuids for each host
                plan_hosts_sync(organization.id)
                plan_self(organization_id: organization.id)
                plan_rules_sync(organization.id)
              end
            end
          end
          plan_notifications
        end
      end

      def run
        auth_organization = Organization.find(input[:organization_id])
        perform_hits_sync
      end

      def perform_hits_sync
        hits = query_insights_hits

        uuids = hits.map { |hit| hit['uuid'] }
        setup_host_ids(uuids)

        replace_hits_data(hits)
      end

      def logger
        action_logger
      end

      private

      def plan_hosts_sync(organization_id)
        plan_action InventorySync::Async::InventoryHostsSync, organization_id
      end

      def plan_rules_sync(organization_id)
        plan_action InsightsRulesSync, organization_id
      end

      def plan_notifications
        plan_action InsightsGenerateNotifications
      end

      def query_insights_hits
        hits_response = execute_cloud_request(
          method: :get,
          url: InsightsCloud.hits_export_url
        )

        JSON.parse(hits_response)
      end

      def query_insights_rules
        rules_response = execute_cloud_request(
          method: :get,
          url: InsightsCloud.rules_url
        )

        JSON.parse(rules_response)
      end

      def setup_host_ids(uuids)
        @host_ids = Hash[
          InsightsFacet.where(uuid: uuids).pluck(:uuid, :host_id)
        ]
      end

      def host_id(uuid)
        @host_ids[uuid]
      end

      def replace_hits_data(hits)
        InsightsHit.transaction do
          # Reset hit counters to 0, they will be recreated later
          InsightsFacet.unscoped.update_all(hits_count: 0)
          InsightsHit.delete_all
          InsightsHit.create(hits.map { |hits_hash| to_model_hash(hits_hash) }.compact)
        end
      end

      def to_model_hash(hit_hash)
        hit_host_id = host_id(hit_hash['uuid'])

        return unless hit_host_id

        {
          host_id: hit_host_id,
          last_seen: DateTime.parse(hit_hash['last_seen']),
          publish_date: DateTime.parse(hit_hash['publish_date']),
          title: hit_hash['title'],
          solution_url: hit_hash['solution_url'],
          total_risk: hit_hash['total_risk'].to_i,
          likelihood: hit_hash['likelihood'].to_i,
          results_url: hit_hash['results_url'],
          rule_id: to_rule_id(hit_hash['results_url']),
        }
      end

      def to_rule_id(results_url)
        URI.decode(safe_results_match(results_url)[:id] || '')
      end

      def safe_results_match(results_url)
        match = results_url.match(/\/(?<id>[^\/]*)\/[^\/]*\/\z/)

        match || { id: nil }
      end

      def rescue_strategy_for_self
        Dynflow::Action::Rescue::Fail
      end
    end
  end
end
