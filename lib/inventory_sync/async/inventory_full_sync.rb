module InventorySync
  module Async
    class InventoryFullSync < InventoryHostsSync
      set_callback :iteration, :around, :setup_statuses
      set_callback :step, :around, :update_statuses_batch

      def plan(organization)
        unless cloud_auth_available?(organization)
          logger.debug('Cloud authentication is not available, skipping inventory hosts sync')
          return
        end

        plan_self(organization_id: organization.id)
      end

      def setup_statuses
        auth_organization = Organization.find(input[:organization_id])

        @subscribed_hosts_ids = Set.new(
          ForemanInventoryUpload::Generators::Queries.for_slice(
            Host.unscoped.where(organization: input[:organization_id])
          ).pluck(:id)
        )

        InventorySync::InventoryStatus.transaction do
          InventorySync::InventoryStatus.where(host_id: @subscribed_hosts_ids).delete_all
          yield
          add_missing_hosts_statuses(@subscribed_hosts_ids)
          host_statuses[:disconnect] += @subscribed_hosts_ids.size
        end

        logger.debug("Synced hosts amount: #{host_statuses[:sync]}")
        logger.debug("Disconnected hosts amount: #{host_statuses[:disconnect]}")
        output[:host_statuses] = host_statuses
      end

      def update_statuses_batch
        results = yield

        update_hosts_status(results.status_hashes, results.touched)
        host_statuses[:sync] += results.touched.size
      end

      def rescue_strategy_for_self
        Dynflow::Action::Rescue::Fail
      end

      private

      def update_hosts_status(status_hashes, touched)
        InventorySync::InventoryStatus.create(status_hashes)
        @subscribed_hosts_ids.subtract(touched)
      end

      def add_missing_hosts_statuses(hosts_ids)
        InventorySync::InventoryStatus.create(
          hosts_ids.map do |host_id|
            {
              host_id: host_id,
              status: InventorySync::InventoryStatus::DISCONNECT,
              reported_at: DateTime.current,
            }
          end
        )
      end

      def host_statuses
        @host_statuses ||= {
          sync: 0,
          disconnect: 0,
        }
      end
    end
  end
end
