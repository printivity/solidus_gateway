require "spec_helper"

describe Spree::Gateway::StripeGateway do
  let(:secret_key) { "key" }
  let(:email) { "customer@example.com" }
  let(:source) { Spree::CreditCard.new }

  let(:payment) do
    instance_double(
      "Spree::Payment",
      source: source,
      order: instance_double(
        "Spree::Order",
        email: email,
        bill_address: bill_address
      )
    )
  end

  let(:gateway) do
    instance_double("gateway").tap do |p|
      allow(p).to receive(:purchase)
      allow(p).to receive(:authorize)
      allow(p).to receive(:capture)
    end
  end

  before do
    subject.preferences = { secret_key: secret_key }
    allow(subject).to receive(:options_for_purchase_or_auth).and_return(["money", "cc", "opts"])
    allow(subject).to receive(:gateway).and_return(gateway)
  end

  describe "#create_profile" do
    before do
      allow(payment.source).to receive(:update!)
    end

    context "when an Order has a Bill Address" do
      let(:bill_address) do
        instance_double(
          "Spree::Address",
          address1: "123 Happy Road",
          address2: "Apt 303",
          city: "Suzarac",
          zipcode: "95671",
          state: instance_double("Spree::State", name: "Oregon"),
          country: instance_double("Spree::Country", name: "United States")
        )
      end

      it "stores the Bill Address with the gateway" do
        expect(subject.gateway).to receive(:store).with(
          payment.source, {
            email: email,
            login: secret_key,
            address: {
              address1: "123 Happy Road",
              address2: "Apt 303",
              city: "Suzarac",
              zip: "95671",
              state: "Oregon",
              country: "United States"
            }
          }
        ).and_return double.as_null_object

        subject.create_profile(payment)
      end
    end

    context "when an Order does not have a Bill Address" do
      let(:bill_address) { nil }

      it "does not store a Bill Address with the gateway" do
        expect(subject.gateway).to receive(:store).with(
          payment.source, {
            email: email,
            login: secret_key
          }
        ).and_return double.as_null_object

        subject.create_profile(payment)
      end

      # Regression test for #141
      context "when correcting the card type" do
        before do
          # We don"t care about this method for these tests
          allow(subject.gateway).to receive(:store).and_return(double.as_null_object)
        end

        it "converts 'American Express' to 'american_express'" do
          payment.source.cc_type = "American Express"
          subject.create_profile(payment)
          expect(payment.source.cc_type).to eq("american_express")
        end

        it "converts 'Diners Club' to 'diners_club'" do
          payment.source.cc_type = "Diners Club"
          subject.create_profile(payment)
          expect(payment.source.cc_type).to eq("diners_club")
        end

        it "converts 'Visa' to 'visa'" do
          payment.source.cc_type = "Visa"
          subject.create_profile(payment)
          expect(payment.source.cc_type).to eq("visa")
        end
      end
    end

    context "when a card represents payment_profile" do
      let(:source) { Spree::CreditCard.new(gateway_payment_profile_id: "tok_profileid") }
      let(:bill_address) { nil }

      it "stores the profile_id as a card" do
        expect(subject.gateway).to receive(:store).with(source.gateway_payment_profile_id, anything).and_return double.as_null_object

        subject.create_profile(payment)
      end
    end
  end

  describe "#purchase" do
    after do
      subject.purchase(19.99, "credit card", {})
    end

    it "send the payment to the gateway" do
      expect(gateway).to receive(:purchase).with("money", "cc", "opts")
    end
  end

  describe "#authorize" do
    after do
      subject.authorize(19.99, "credit card", {})
    end

    it "send the authorization to the gateway" do
      expect(gateway).to receive(:authorize).with("money", "cc", "opts")
    end
  end

  describe "#capture" do
    after do
      subject.capture(1234, "response_code", {})
    end

    it "convert the amount to cents" do
      expect(gateway).to receive(:capture).with(1234, anything, anything)
    end

    it "use the response code as the authorization" do
      expect(gateway).to receive(:capture).with(anything, "response_code", anything)
    end
  end

  describe "#apply_leve3_data! (private)" do
    let(:order) { FactoryBot.create(:order_with_line_items) }
    let(:options) { {} }
    let(:ship_address) do
      instance_double(
        "Spree::Address",
        address1: "123 Happy Road",
        address2: "Apt 303",
        city: "Suzarac",
        zipcode: "95671",
        state: instance_double("Spree::State", name: "Oregon"),
        country: instance_double("Spree::Country", name: "United States")
      )
    end

    context "when the calculated level3 data matches the sum sent to Stripe" do
      before do
        FactoryBot.create(:store)
        allow(order).to receive(:for_delivery?).and_return(true)
        allow(order).to receive(:shipping_address).and_return(ship_address)
      end

      it "does not trigger a call to the exception handler" do
        expect(subject).not_to receive(:notify_exception_handler)

        subject.send(:apply_level3_data!, options, order)
      end

      it "ensures that level3 attributes are populated in the options passed to Stripe" do
        subject.send(:apply_level3_data!, options, order)

        expect(options[:merchant_reference]).to be_present
        expect(options[:customer_reference]).to be_present
        expect(options[:shipping_address_zip]).to be_present
        expect(options[:shipping_from_zip]).to be_present
        expect(options[:shipping_amount]).to be_present

        expect(options[:line_items]).to be_present
        options[:line_items].each do |li|
          expect(li[:product_code]).to be_present
          expect(li[:product_description]).to be_present
          expect(li[:unit_cost]).to be_present
          expect(li[:quantity]).to be_present
          expect(li[:tax_amount]).to be_present
          expect(li[:discount_amount]).to be_present
        end
      end
    end

    context "when the calculated level3 data does not match the sum sent to Stripe" do
      before do
        FactoryBot.create(:store)
        allow(order).to receive(:for_delivery?).and_return(true)
        allow(order).to receive(:shipping_address).and_return(ship_address)

        allow(subject).to receive(:calculate_checksum_from_options).and_return(999_999_999)
        allow(subject).to receive(:notify_exception_handler).and_return(true)
      end

      it "triggers a call to the exception handler" do
        expect(subject).to receive(:notify_exception_handler)

        subject.send(:apply_level3_data!, options, order)
      end

      it "ensures that no level3 attributes are populated in the options passed to Stripe" do
        subject.send(:apply_level3_data!, options, order)

        expect(options[:merchant_reference]).not_to be_present
        expect(options[:customer_reference]).not_to be_present
        expect(options[:shipping_address_zip]).not_to be_present
        expect(options[:shipping_from_zip]).not_to be_present
        expect(options[:shipping_amount]).not_to be_present

        expect(options[:line_items]).not_to be_present
      end
    end
  end

  context "when capturing via the Payment Class" do
    let(:gateway) do
      gateway = described_class.new(active: true)
      gateway.set_preference :secret_key, secret_key

      allow(gateway).to receive(:options_for_purchase_or_auth).and_return(["money", "cc", "opts"])
      allow(gateway).to receive(:gateway).and_return gateway
      allow(gateway).to receive_messages source_required: true

      gateway
    end

    let(:order) { Spree::Order.create! }

    let(:card) do
      FactoryBot.create(
        :credit_card,
        gateway_customer_profile_id: "cus_abcde",
        imported: false
      )
    end

    let(:payment) do
      payment = Spree::Payment.new
      payment.source = card
      payment.order = order
      payment.payment_method = gateway
      payment.amount = 98.55
      payment.state = "pending"
      payment.response_code = "12345"
      payment
    end

    let!(:success_response) do
      instance_double(
        "success_response",
        success?: true,
        authorization: "123",
        avs_result: { "code" => "avs-code" },
        cvv_result: { "code" => "cvv-code", "message" => "CVV Result" }
      )
    end

    before do
      FactoryBot.create(:store)
    end

    after do
      payment.capture!
    end

    it "gets correct amount" do
      expect(gateway).to receive(:capture).with(9855, "12345", anything).and_return(success_response)
    end
  end
end
