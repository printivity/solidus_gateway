require "spec_helper"

RSpec.describe "Stripe checkout", type: :feature do
  before do
    FactoryBot.create(:store)
    # Set up a zone
    zone = FactoryBot.create(:zone)
    country = FactoryBot.create(:country)
    zone.members << Spree::ZoneMember.create!(zoneable: country)
    FactoryBot.create(:free_shipping_method)

    Spree::Gateway::StripeGateway.create!(
      name: "Stripe",
      preferred_secret_key: "sk_test_VCZnDv3GLU15TRvn8i2EsaAN",
      preferred_publishable_key: "pk_test_Cuf0PNtiAkkMpTVC2gwYDMIg"
    )

    FactoryBot.create(:product, name: "DL-44")

    visit spree.root_path
    click_link "DL-44"
    click_button "Add To Cart"

    expect(page).to have_current_path("/cart")
    click_button "Checkout"

    # Address
    expect(page).to have_current_path("/checkout/address")
    fill_in "Customer E-Mail", with: "han@example.com"
    within("#billing") do
      fill_in "First Name", with: "Han"
      fill_in "Last Name", with: "Solo"
      fill_in "Street Address", with: "YT-1300"
      fill_in "City", with: "Mos Eisley"
      select "United States of America", from: "Country"
      select country.states.first.name, from: "order_bill_address_attributes_state_id"
      fill_in "Zip", with: "12010"
      fill_in "Phone", with: "(555) 555-5555"
    end

    click_on "Save and Continue"

    # Delivery
    expect(page).to have_current_path("/checkout/delivery")
    expect(page).to have_content("UPS Ground")
    click_on "Save and Continue"

    expect(page).to have_current_path("/checkout/payment")

    cc_number.to_s.chars.each do |number|
      find_field("Card Number").send_keys(number)
    end

    cc_expiration.to_s.chars.each do |date|
      find_field("Expiration").send_keys(date)
    end
  end

  # This will fetch a token from Stripe.com and then pass that to the webserver.
  # The server then processes the payment using that token.
  context "when the CC number is valid" do
    let(:cc_number) { "4242 4242 4242 4242" }

    context "when the expiration is valid" do
      let(:cc_expiration) { "01 / #{Time.current.year + 1}" }

      it "processes a valid payment", js: true do
        fill_in "Card Code", with: "123"
        click_button "Save and Continue"
        expect(page).to have_current_path("/checkout/confirm")
        click_button "Place Order"
        expect(page).to have_content("Your order has been processed successfully")
      end

      context "when the security fields are invalid" do
        let(:cc_security) { "12" }

        it "shows an error", js: true do
          fill_in "Card Code", with: cc_security
          click_button "Save and Continue"
          expect(page).to have_content("Your card's security code is invalid.")
        end
      end
    end

    context "when the expiration fields are invalid" do
      let(:cc_expiration) { "00 / #{Time.current.year + 1}" }

      it "shows an error", js: true do
        fill_in "Card Code", with: "123"
        click_button "Save and Continue"
        expect(page).to have_content("Your card's expiration month is invalid.")
      end
    end

    context "when the expiration fields are missing" do
      let(:cc_expiration) { "" }

      it "shows an error", js: true do
        click_button "Save and Continue"
        expect(page).to have_content("Your card's expiration year is invalid.")
      end
    end
  end

  context "when the CC number is invalid" do
    let(:cc_number) { "1111 1111 1111 1111" }
    let(:cc_expiration) { "01 / #{Time.current.year + 1}" }

    it "shows an error", js: true do
      click_button "Save and Continue"
      expect(page).to have_content("Your card number is incorrect.")
    end
  end

  context "when the CC number is empty" do
    let(:cc_number) { "" }
    let(:cc_expiration) { "01 / #{Time.current.year + 1}" }

    it "shows an error", js: true do
      click_button "Save and Continue"
      expect(page).to have_content("Could not find payment information")
    end
  end
end
