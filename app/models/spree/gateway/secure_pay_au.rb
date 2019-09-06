module Spree
  class Gateway::SecurePayAu < Gateway
    preference :login, :string
    preference :password, :string

    def provider_class
      ActiveMerchant::Billing::SecurePayAuGateway
    end
  end
end
