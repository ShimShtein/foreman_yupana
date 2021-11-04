require 'rest-client'

module InsightsCloud
  module Async
    class InsightsRulesSync < ::Actions::EntryAction
      include ::ForemanRhCloud::CloudAuth

      def plan(organization_id)

        # since the tasks are not connected, we need to force sequence execution here
        # to make sure we don't run resolutions until we synced all our rules
        sequence do
          plan_self(organization_id: organization_id)
          plan_resolutions(organization_id)
        end
      end

      def plan_resolutions(organization_id)
        plan_action InsightsResolutionsSync, organization_id
      end

      def run
        auth_organization = Organization.find(input[:organization_id])
        unless cloud_auth_available?(auth_organization)
          logger.debug('Cloud authentication is not available, skipping rules sync')
          return
        end

        offset = 0
        InsightsRule.transaction do
          loop do
            api_response = query_insights_rules(offset)
            results = RulesResult.new(api_response)
            logger.debug("Downloaded #{offset + results.count} of #{results.total}")
            write_rules_page(results.rules)
            offset += results.count
            output[:rules_count] = results.total
            break if offset >= results.total
          end
        end
      end

      def logger
        action_logger
      end

      private

      def query_insights_rules(offset)
        rules_response = execute_cloud_request(
          method: :get,
          url: InsightsCloud.rules_url(offset: offset)
        )

        JSON.parse(rules_response)
      end

      def write_rules_page(rules)
        rules_attributes = rules.map { |rule| to_rule_hash(rule) }

        InsightsRule.upsert_all(rules_attributes, unique_by: :rule_id)
      end

      def to_rule_hash(rule_hash)
        {
          rule_id: rule_hash['rule_id'],
          description:  rule_hash['description'],
          category_name:  rule_hash.dig('category', 'name'),
          impact_name:  rule_hash.dig('impact', 'name'),
          summary:  rule_hash['summary'],
          generic:  rule_hash['generic'],
          reason:  rule_hash['reason'],
          total_risk:  rule_hash['total_risk'],
          reboot_required:  rule_hash['reboot_required'],
          more_info:  rule_hash['more_info'],
          rating:  rule_hash['rating'],
        }
      end

      def rescue_strategy_for_self
        Dynflow::Action::Rescue::Fail
      end
    end
  end
end
