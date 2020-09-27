module Spree
  class Gateway::StripeGateway < PaymentMethod::CreditCard
    preference :secret_key, :string
    preference :publishable_key, :string

    CARD_TYPE_MAPPING = {
      "American Express" => "american_express",
      "Diners Club" => "diners_club",
      "Visa" => "visa"
    }.freeze

    if Spree.solidus_gem_version < Gem::Version.new("2.3.x")
      def method_type
        "stripe"
      end
    else
      def partial_name
        "stripe"
      end
    end

    def gateway_class
      ActiveMerchant::Billing::StripeGateway
    end

    def payment_profiles_supported?
      true
    end

    def purchase(money, creditcard, gateway_options)
      gateway.purchase(*options_for_purchase_or_auth(money, creditcard, gateway_options))
    end

    def authorize(money, creditcard, gateway_options)
      gateway.authorize(*options_for_purchase_or_auth(money, creditcard, gateway_options))
    end

    def capture(money, response_code, gateway_options)
      gateway.capture(money, response_code, gateway_options)
    end

    def credit(money, creditcard, response_code, gateway_options)
      gateway.refund(money, response_code, {})
    end

    def void(response_code, creditcard, gateway_options)
      gateway.void(response_code, {})
    end

    def cancel(response_code)
      gateway.void(response_code, {})
    end

    def create_profile(payment)
      return unless payment.source.gateway_customer_profile_id.nil?

      options = {
        email: payment.order.email,
        login: preferred_secret_key
      }.merge! address_for(payment)

      source = update_source!(payment.source)

      creditcard = if source.number.blank? && source.gateway_payment_profile_id.present?
                     source.gateway_payment_profile_id
                   else
                     source
                   end

      response = gateway.store(creditcard, options)
      if response.success?
        payment.source.update!(
          {
            cc_type: payment.source.cc_type, # side-effect of update_source!
            gateway_customer_profile_id: response.params["id"],
            gateway_payment_profile_id: response.params["default_source"] || response.params["default_card"]
          }
        )

      else
        payment.send(:gateway_error, response.message)
      end
    end

    private

    # In this gateway, what we call "secret_key" is the "login"
    def options
      options = super

      options.merge(login: preferred_secret_key)
    end

    def options_for_purchase_or_auth(money, creditcard, gateway_options)
      options = {}
      options[:currency] = gateway_options[:currency]

      if gateway_options.dig(:originator) && gateway_options[:originator].order_id.present?
        merch_order = Spree::Order.find_by(id: gateway_options[:originator][:order_id])

        apply_level3_data!(options, merch_order)
      end

      if (customer = creditcard.gateway_customer_profile_id)
        options[:customer] = customer
      end

      if (token_or_card_id = creditcard.gateway_payment_profile_id)
        # The Stripe ActiveMerchant gateway supports passing the token directly as the creditcard parameter
        # The Stripe ActiveMerchant gateway supports passing the customer_id and credit_card id
        # https://github.com/Shopify/active_merchant/issues/770
        creditcard = token_or_card_id
      end

      return money, creditcard, options
    end

    def apply_level3_data!(options, merch_order)
      options[:merchant_reference] = merch_order.id.to_s.slice(0, 25)
      options[:customer_reference] = merch_order.guest_token.to_s.slice(0, 17)

      if merch_order.for_delivery?
        options[:shipping_address_zip] = merch_order.shipping_address.zipcode
        options[:shipping_from_zip] = merch_order.shipments.first.stock_location.zipcode
        options[:shipping_amount] = (merch_order.shipments.first.cost * 100.0).to_i
      end

      options[:line_items] = []

      merch_order.line_items.each do |li|
        options[:line_items] << {
          product_code: li.variant.id.to_s.slice(0, 12),
          product_description: (li.product.description.presence || li.product.name).to_s.slice(0, 26),
          unit_cost: (li.price * 100.0).to_i,
          quantity: li.quantity,
          tax_amount: (li.additional_tax_total * 100.0).to_i,
          discount_amount: (((merch_order.promo_total.abs.to_d * li.quantity.to_d) / merch_order.quantity.to_d) * 100.0).to_i
        }
      end

      merch_order_total = merch_order.total.to_d
      checksum_total = calculate_checksum_from_options(options).to_d

      if checksum_total != merch_order_total
        notify_exception_handler(
          "Checksum failed when sending Stripe Level 3 data for Spree::Order",
          context: {
            merch_order_id: merch_order.id,
            merch_order_total: merch_order_total,
            checksum_total: checksum_total,
            options: options
          }
        )

        options.delete(:line_items)
        options.delete(:merchant_reference)
        options.delete(:customer_reference)

        options.delete(:shipping_address_zip)
        options.delete(:shipping_from_zip)
        options.delete(:shipping_amount)
      end
    end

    def notify_exception_handler(message, context)
      HoneyBadger.notify(message, context)
    end

    def calculate_checksum_from_options(options)
      line_item_amount = options[:line_items].sum { |li| ((li[:quantity] * li[:unit_cost]) - li[:discount_amount]) + li[:tax_amount] }.to_d
      shipping_cost = options[:shipping_amount].to_d

      (line_item_amount + shipping_cost) / 100.0
    end

    def address_for(payment)
      {}.tap do |options|
        if (address = payment.order.bill_address)
          options.merge!(
            address: {
              address1: address.address1,
              address2: address.address2,
              city: address.city,
              zip: address.zipcode
            }
          )

          if (country = address.country)
            options[:address].merge!(country: country.name)
          end

          if (state = address.state)
            options[:address].merge!(state: state.name)
          end
        end
      end
    end

    def update_source!(source)
      source.cc_type = CARD_TYPE_MAPPING[source.cc_type] if CARD_TYPE_MAPPING.include?(source.cc_type)

      source
    end
  end
end
