# encoding: utf-8
require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe Jiralicious::Session, "when logging in" do
  context "successfully" do
    before :each do
      register_login
      @session = Jiralicious::Session.new
      @session.login
    end

    it "is alive" do
      @session.should be_alive
    end

    it "populates the session and login info" do
      @session.session.should == {
        "name" =>  "JSESSIONID",
        "value" => "12345678901234567890"
      }
      @session.login_info.should == {
        "failedLoginCount" =>  10,
        "loginCount" =>  127,
        "lastFailedLoginTime" => "2011-07-25T06:31:07.556-0500",
        "previousLoginTime" => "2011-07-25T06:31:07.556-0500"
      }
    end
  end

  context "with an invalid login" do
    before :each do
      FakeWeb.register_uri(:post,
                           Jiralicious.uri + '/rest/auth/latest/session',
                           :status => ["401", "Not Authorized"])
      @session = Jiralicious::Session.new
    end

    it "raises the correct exception" do
      lambda { @session.login }.
        should raise_error(Jiralicious::InvalidLogin)
    end

    it "is not alive" do
      begin; @session.login; rescue Jiralicious::InvalidLogin; end
      @session.should_not be_alive
    end

    it "clears the session and login info" do
      @session.login_info = "GARBAGE"
      @session.session = "GARBAGE"
      begin; @session.login; rescue Jiralicious::InvalidLogin; end
      @session.login_info.should be_nil
      @session.session.should be_nil
    end
  end

  context "when CAPTCHA is required" do
    before :each do
      FakeWeb.register_uri(:post,
                           Jiralicious.uri + '/rest/auth/latest/session',
                           :status => ["403", "Captcha Required"])
      @session = Jiralicious::Session.new
    end

    it "raises an exception" do
      lambda { @session.login }.
        should raise_error(Jiralicious::CaptchaRequired)
    end

    it "clears the session and login info" do
      @session.login_info = "GARBAGE"
      @session.session = "GARBAGE"
      begin; @session.login; rescue Jiralicious::CaptchaRequired; end
      @session.login_info.should be_nil
      @session.session.should be_nil
    end
  end

  context "with any other HTTP error" do
    before :each do
      FakeWeb.register_uri(:post,
                           Jiralicious.uri + '/rest/auth/latest/session',
                           :status => ["500", "Internal Server Error"])
      @session = Jiralicious::Session.new
    end

    it "raises an exception" do
      lambda { @session.login }.
        should raise_error(Jiralicious::JiraError)
    end

    it "clears the session and login info" do
      @session.login_info = "GARBAGE"
      @session.session = "GARBAGE"
      begin; @session.login; rescue Jiralicious::JiraError; end
      @session.login_info.should be_nil
      @session.session.should be_nil
    end

    it "gives the Net::HTTP reason for failure" do
      begin
        @session.login
      rescue Jiralicious::JiraError => e
        e.message.should == "Internal Server Error"
      end
    end
  end
end

describe Jiralicious::Session, "when logging out" do
  before :each do
    register_login
    @session = Jiralicious::Session.new
    @session.login
    @session.should be_alive
    FakeWeb.register_uri(:delete,
                         Jiralicious.uri + '/rest/auth/latest/session',
                         :status => "204")
    @session.logout
  end

  it "is not alive" do
    @session.should_not be_alive
  end

  it "clears the session and login info" do
    @session.session.should be_nil
    @session.login_info.should be_nil
  end

  context "when not logged in" do
    before :each do
      @session = Jiralicious::Session.new
      FakeWeb.register_uri(:delete,
                         Jiralicious.uri + '/rest/auth/latest/session',
                         :status => ["401", "Not Authorized"])
    end

    it "should raise the correct error" do
      lambda { @session.logout }.should raise_error(Jiralicious::NotLoggedIn)
    end
  end

  context "with any other HTTP error" do
    before :each do
      @session = Jiralicious::Session.new
      FakeWeb.register_uri(:delete,
                         Jiralicious.uri + '/rest/auth/latest/session',
                         :status => ["500", "Internal Server Error"])
    end

    it "raises an exception" do
      lambda { @session.logout }.
        should raise_error(Jiralicious::JiraError)
    end

    it "gives the Net::HTTP reason for failure" do
      begin
        @session.logout
      rescue Jiralicious::JiraError => e
        e.message.should == "Internal Server Error"
      end
    end
  end
end

describe Jiralicious::Session, "performing a request" do
  include ConfigurationHelper
  include LoginHelper

  before :each do
    FakeWeb.register_uri(:get,
                         Jiralicious.uri + '/fake/uri',
                         :status => "200")
  end

  context "when login is required" do
    before :each do
      @session = Jiralicious::Session.new
      @session.stub!(:require_login?).and_return(true)
    end

    it "attempts to log in beforehand" do
      @session.should_receive(:login)
      @session.perform_request do
        Jiralicious::Session.get('/fake/uri')
      end
    end
  end

  context "when login is not required" do
    before :each do
      @session = Jiralicious::Session.new
      @session.stub!(:require_login?).and_return(false)
    end

    it "doesn't try to log in before making the request" do
      @session.should_receive(:login).never
      @session.perform_request do
        Jiralicious::Session.get('/fake/uri')
      end
    end
  end
end

describe  "performing a request with a successful response" do
    before :each do
      FakeWeb.register_uri(:get,
                           Jiralicious.uri + '/ok',
                           :status => "200")
      FakeWeb.register_uri(:post,
                           Jiralicious.uri + '/created',
                           :status => "201")
      FakeWeb.register_uri(:delete,
                           Jiralicious.uri + '/nocontent',
                           :status => "204")

      register_login
  end

  let(:session) { Jiralicious::Session.new }

  it "returns the response on ok" do
    r = session.perform_request { Jiralicious::Session.get('/ok') }
    r.class.should == HTTParty::Response
  end

  it "returns the response on created" do
    r = session.perform_request { Jiralicious::Session.post('/created') }
    r.class.should == HTTParty::Response
  end

  it "returns the response on no content" do
    r = session.perform_request { Jiralicious::Session.delete('/nocontent') }
    r.class.should == HTTParty::Response
  end
end

describe  "performing a request with an unsuccessful response" do
    before :each do
      FakeWeb.register_uri(:get,
                           Jiralicious.uri + '/cookie_expired',
                           [
                            {:status => "401", :body => "Cookie Expired"},
                            {:status => "200"}
                           ])
      FakeWeb.register_uri(:get,
                           Jiralicious.uri + '/captcha_needed',
                           :status => "401",
                           "X-Seraph-LoginReason" => "AUTHENTICATION_DENIED")
      register_login
  end

  let(:session) { Jiralicious::Session.new }

  it "retries the login when the cookie expires" do
    session.should_receive(:login).twice
    session.perform_request { Jiralicious::Session.get('/cookie_expired') }
  end

  it "raises an exception when retried and failed" do
    FakeWeb.register_uri(:get,
                         Jiralicious.uri + '/cookie_expired',
                         [
                          {:status => "401", :body => "Cookie Expired"},
                          {:status => "401", :body => "Cookie Expired"}
                         ])
    lambda {
      session.perform_request { Jiralicious::Session.get('/cookie_expired') }
    }.should raise_error(Jiralicious::CookieExpired)
  end

  it "raises an exception when the captcha is required" do
    lambda {
      session.perform_request { Jiralicious::Session.get('/captcha_needed') }
    }.should raise_error(Jiralicious::CaptchaRequired)
  end
end
