require 'spec_helper'

describe Spree::Gateway::SecurePayAu do
  let(:gateway) { described_class.create!(name: 'SecurePayAu') }

  context '.gateway_class' do
    it 'is a SecurePayAu gateway' do
      expect(gateway.gateway_class).to eq ::ActiveMerchant::Billing::SecurePayAuGateway
    end
  end
end
