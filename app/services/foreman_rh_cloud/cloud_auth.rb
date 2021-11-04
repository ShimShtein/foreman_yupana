module ForemanRhCloud
  module CloudAuth
    extend ActiveSupport::Concern

    include CloudRequest

    # organization to authorize requests against
    attr_writer :auth_organization

    def cloud_auth_available?(organization)
      organization.owner_details.dig('upstreamConsumer', 'idCert').present?
    end

    def rh_credentials
      @rh_credentials ||= begin
        candlepin_id_certificate = auth_organization.owner_details['upstreamConsumer']['idCert']
        {
          cert: candlepin_id_certificate['cert'],
          key: candlepin_id_certificate['key'],
        }
      end
    end

    def execute_cloud_request(params)
      final_params = {
        ssl_client_cert: OpenSSL::X509::Certificate.new(rh_credentials[:cert]),
        ssl_client_key: OpenSSL::PKey::RSA.new(rh_credentials[:key]),
      }.deep_merge(params)

      super(final_params)
    end

    def auth_organization
      @auth_organization || Organization.current
    end
  end
end
