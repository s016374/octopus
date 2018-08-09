require 'dotenv/load'
require 'http'
require 'mongo'
require 'mysql2'
require 'zabby'

module DmHelper
  module_function

  def items(*args)
    items = []
    $LOG.info 'FINANCE! BOND!'
    args.each do |arg|
      items += arg
      $LOG.info items
    end
    items
  end

  def request_api(method, url, cookies, &blk)
    data = yield if block_given?
    if method == 'post'
      HTTP[content_type: 'application/json', accept: '*/*'].cookies(cookies).post(url, json: data)
    elsif method == 'get'
      HTTP[content_type: 'application/json', accept: '*/*'].cookies(cookies).get(url)
    end
  end

  def get_login_session(username, password, env, is_sid=true)
    if env =~ /prod/
      url = ENV['DM_URL'] + '/auth-service/signin'
    elsif env =~ /qa/
      url = ENV['DM_QA_URL'] + '/auth-service/signin'
    else
      return 'plz + /env (prod, qa)'
    end
    res = HTTP.get(url)
    csrf = res.to_s.split('name="_csrf" value="').last.split('"/>').first
    sid = res.cookies.inspect.to_s.split('"sid", value="').last.split('",').first
    res = HTTP[content_type: 'application/x-www-form-urlencoded']
              .cookies('sid' => sid, 'uid' => ENV['TEST_UID'], 'UM_distinctid' => ENV['TEST_UM_DISTINCTID'])
              .post(url, :body => "_csrf=#{csrf}&username=#{username}&password=#{password}")
    sid = res.cookies.inspect.to_s
    return 'auth error' if sid.include? '@jar={}'
    sid = sid.split('"sid", value="').last.split('",').first
    return sid if is_sid
    { sid: sid, uid: ENV['TEST_UID'], UM_distinctid: ENV['TEST_UM_DISTINCTID'] }
  end

  class MongoFactory
    Mongo::Logger.logger.level = Logger::FATAL

    private_class_method :new
    def self.create(is_new=false)
      @@instance = new(is_new)
    end

    def self.destroy
      @@instance = nil
    end

    private
    def self.new(is_new)
      if is_new
        @@client_new ||= Mongo::Client.new([ENV['MONGO_NEW_HOST']], :database => ENV['MONGO_NEW_DATABASE'], :user => ENV['MONGO_NEW_USER'], :password => ENV['MONGO_NEW_PASSWORD'])
        Mongo::Database.new(@@client_new, :dm_bond)
      else
        @@client ||= Mongo::Client.new([ENV['MONGO_HOST_1'], ENV['MONGO_HOST_2']], :replica_set => ENV['MONGO_REPLICA'], :database => ENV['MONGO_DATABASE'], :user => ENV['MONGO_USER'], :password => ENV['MONGO_PASSWORD'])
        Mongo::Database.new(@@client, :dm_bond)
      end
    end
  end

  class MysqlFactory
    private_class_method :new
    def self.create
      @@instance ||= new
    end

    def self.destroy
      @@instance = nil
    end

    def self.new
      Mysql2::Client.new(:host => ENV['MYSQL_HOST'], :port => ENV['MYSQL_PORT'], :username => ENV['MYSQL_USERNAME'], :password => ENV['MYSQL_PASSWORD'])
    end
  end

  class ZabbixFoctory
    private_class_method :new
    def self.create
      @@instance ||= new
    end

    def self.destroy
      @@instance = nil
    end

    def self.new
      serv = Zabby.init do
        set :server => ENV['ZABBIX_HOST']
        set :user => ENV['ZABBIX_USER']
        set :password => ENV['ZABBIX_PASSWORD']
        login
      end
      serv
    end
  end
end
