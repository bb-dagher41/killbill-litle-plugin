require 'spec_helper'
require 'logger'

ActiveMerchant::Billing::Base.mode = :test

class KillbillApiWithFakeGetAccountById < Killbill::Plugin::KillbillApi

  def initialize(japi_proxy)
    super(japi_proxy)
  end

  # Returns an account where we specify the currency for the report group
  def get_account_by_id(id)
    Killbill::Plugin::Model::Account.new(id, nil, nil, nil, nil, nil, 1, nil, 1, 'USD', nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, false, true)
  end
end

describe Killbill::Litle::PaymentPlugin do
  before(:each) do
    @call_context = Killbill::Plugin::Model::CallContext.new(SecureRandom.uuid,
                                                             'token',
                                                             'rspec tester',
                                                             'TEST',
                                                             'user',
                                                             'testing',
                                                             'this is from a test',
                                                             Time.now,
                                                             Time.now)

    @plugin = Killbill::Litle::PaymentPlugin.new
    kb_apis = KillbillApiWithFakeGetAccountById.new(nil)
    @plugin.kb_apis = kb_apis
    @plugin.logger = Logger.new(STDOUT)
    @plugin.conf_dir = File.expand_path(File.dirname(__FILE__) + '../../../')
    @plugin.start_plugin
  end

  after(:each) do
    @plugin.stop_plugin
  end

  it "should be able to create and retrieve payment methods" do
    pm = create_payment_method

    pms = @plugin.get_payment_methods(pm.kb_account_id, false, @call_context)
    pms.size.should == 1
    pms[0].external_payment_method_id.should == pm.litle_token

    pm_details = @plugin.get_payment_method_detail(pm.kb_account_id, pm.kb_payment_method_id, @call_context)
    pm_details.external_payment_method_id.should == pm.litle_token

    @plugin.delete_payment_method(pm.kb_account_id, pm.kb_payment_method_id, @call_context)

    @plugin.get_payment_methods(pm.kb_account_id, false, @call_context).size.should == 0
    lambda { @plugin.get_payment_method_detail(pm.kb_account_id, pm.kb_payment_method_id, @call_context) }.should raise_error RuntimeError
  end

  it "should be able to charge and refund" do
    pm = create_payment_method
    amount_in_cents = 10000
    currency = 'USD'
    kb_payment_id = SecureRandom.uuid

    payment_response = @plugin.process_payment pm.kb_account_id, kb_payment_id, pm.kb_payment_method_id, amount_in_cents, currency, @call_context
    payment_response.amount.should == amount_in_cents
    payment_response.status.should == Killbill::Plugin::Model::PaymentPluginStatus.new(:PROCESSED)

    # Verify our table directly
    response = Killbill::Litle::LitleResponse.find_by_api_call_and_kb_payment_id :charge, kb_payment_id
    response.test.should be_true
    response.success.should be_true
    response.message.should == "Approved"
    response.params_litleonelineresponse_saleresponse_order_id.should == Killbill::Litle::Utils.compact_uuid(kb_payment_id)

    payment_response = @plugin.get_payment_info pm.kb_account_id, kb_payment_id, @call_context
    payment_response.amount.should == amount_in_cents
    payment_response.status.should == Killbill::Plugin::Model::PaymentPluginStatus.new(:PROCESSED)

    # Check we cannot refund an amount greater than the original charge
    lambda { @plugin.process_refund pm.kb_account_id, kb_payment_id, amount_in_cents + 1, currency, @call_context }.should raise_error RuntimeError

    refund_response = @plugin.process_refund pm.kb_account_id, kb_payment_id, amount_in_cents, currency, @call_context
    refund_response.amount.should == amount_in_cents
    refund_response.status.should == Killbill::Plugin::Model::RefundPluginStatus.new(:PROCESSED)

    # Verify our table directly
    response = Killbill::Litle::LitleResponse.find_by_api_call_and_kb_payment_id :refund, kb_payment_id
    response.test.should be_true
    response.success.should be_true

    # Make sure we can charge again the same payment method
    second_amount_in_cents = 29471
    second_kb_payment_id = SecureRandom.uuid

    payment_response = @plugin.process_payment pm.kb_account_id, second_kb_payment_id, pm.kb_payment_method_id, second_amount_in_cents, currency, @call_context
    payment_response.amount.should == second_amount_in_cents
    payment_response.status.should == Killbill::Plugin::Model::PaymentPluginStatus.new(:PROCESSED)
  end

  private

  def create_payment_method
    kb_account_id = SecureRandom.uuid
    kb_payment_method_id = SecureRandom.uuid

    # Generate a token in Litle
    paypage_registration_id = '123456789012345678901324567890abcdefghi'
    info = Killbill::Plugin::Model::PaymentMethodPlugin.new nil, nil, [Killbill::Plugin::Model::PaymentMethodKVInfo.new(false, "paypageRegistrationId", paypage_registration_id)], nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil
    payment_method = @plugin.add_payment_method(kb_account_id, kb_payment_method_id, info, true, @call_context)

    pm = Killbill::Litle::LitlePaymentMethod.from_kb_payment_method_id kb_payment_method_id
    pm.kb_account_id.should == kb_account_id
    pm.kb_payment_method_id.should == kb_payment_method_id
    pm.litle_token.should_not be_nil
    pm
  end
end
