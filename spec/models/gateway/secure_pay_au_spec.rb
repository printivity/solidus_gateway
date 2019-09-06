require 'spec_helper'

describe Spree::Gateway::SecurePayAu do
  let(:gateway) { described_class.create!(name: 'SecurePayAu') }

  context '.provider_class' do
    it 'is a SecurePayAu gateway' do
      expect(gateway.provider_class).to eq ::ActiveMerchant::Billing::SecurePayAuGateway
    end
  end
end
