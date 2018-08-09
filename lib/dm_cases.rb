require_relative 'dm_helper'

module DmMonitor
  class Cases
    def initialize(user, password, env, is_hash)
      @cookies = DmHelper.get_login_session(user, password, env, is_hash)
    end

    def zabbix_alerts
      warnings = []
      averages = []
      highs = []

      zabbix_triggers.each do |trigger|
        case trigger["priority"]
          when '2' then
            warnings << trigger["hostname"].gsub(/.local/, '') + ': ' + trigger["description"]
          when '3' then
            averages << trigger["hostname"].gsub(/.local/, '') + ': ' + trigger["description"]
          when '4' then
            highs << trigger["hostname"].gsub(/.local/, '') + ': ' + trigger["description"]
        end
      end
      $LOG.info 'ZABBIX_API!'
      $LOG.info "warning: #{warnings}"
      $LOG.info "average: #{averages}"
      $LOG.info "high: #{highs}"
      { warning: warnings, average: averages, high: highs }
    end

    def mysql_connections
      # singleton mode would error when mysql restart, @@instance aways exsit.
      begin
        client = DmHelper::MysqlFactory.create
        result = client.query("show status like 'Threads_connected';")
      rescue
        DmHelper::MysqlFactory.destroy
        retry
      end
      result.first['Value'].to_i
    end

    def online_web_daily
      count = []
      res = DmHelper.request_api('post', 'https://rest.innodealing.com/online-web/api/market/summary', @cookies)
      JSON.parse(res)['data']['totalInOut'].each do |row|
        if row['side'] == 1
          count << {'label': 'Online IN', 'value': row['total_count']}
        elsif row['side'] == 2
          count << {'label': 'Online OUT', 'value': row['total_count']}
        end
      end
      count
    end

    def offline_quotes
      count = []
      res = DmHelper.request_api('get', 'https://rest.innodealing.com/offline-web/api/statistics/todayQuotes/count', @cookies)
      in_count = JSON.parse(res)['data']['inCount']
      out_count = JSON.parse(res)['data']['outCount']
      count << {'label': 'Offline Quotes', 'value': in_count + out_count}
    end

    def finance_quotes
      count = []
      res = DmHelper.request_api('post', 'http://rest.innodealing.com/finance-web/api/advanceFilters/inQuotes', @cookies) do
        {contentSearch: "", filtrateConditionList: [], onlyToday: true, pageNum: 1, pageSize: 1, sortField: 'null', sortType: 'null'}
      end
      in_count = JSON.parse(res)['data']['totalElements']
      res = DmHelper.request_api('post', 'http://rest.innodealing.com/finance-web/api/advanceFilters/quotes', @cookies) do
        {contentSearch: "", filtrateConditionList: [], onlyToday: true, pageNum: 1, pageSize: 1, sortField: 'null', sortType: 'null'}
      end
      out_count = JSON.parse(res)['data']['totalElements']
      count << {'label': 'Finace Quotes', 'value': in_count + out_count}
    end

    def deposit_quotes
      count = []
      res = DmHelper.request_api('post', 'https://rest.innodealing.com/deposit-web/api/advanceFilters/quotes', @cookies) do
        {contentSearch: "",filtrateConditionList: [],onlyToday: true,pageNum: 1,pageSize: 1,sortField: 'null',sortType: 'null'}
      end
      quotes = JSON.parse(res)['data']['totalElements']
      count << {'label': 'Deposit Quotes', 'value': quotes}
    end

    def bond_count(label, collection, is_new=false, &blk)
      filter = block_given? ? yield : {}
      # singleton mode would error when mongo restart, @@instance aways exsit.
      begin
        db = DmHelper::MongoFactory.create(is_new)
        collection = db[collection.to_sym]
        count = collection.find(filter).count
      rescue Exception => e
        $LOG.warn "DmMonitor::Cases#bond_count: #{e}"
        DmHelper::MongoFactory.destroy
      end
      ['label': label, 'value': count]
    end

    def bond_compare(label, collection1, collection2, is_new=false, &blk)
      filter = block_given? ? yield : {}
      # singleton mode would error when mongo restart, @@instance aways exsit.
      begin
        db = DmHelper::MongoFactory.create(is_new)
        collection = db[collection1.to_sym]
        count_base = collection.find(filter).count
        collection = db[collection2.to_sym]
        count_detail = collection.find(filter).count
      rescue Exception => e
        $LOG.warn "DmMonitor::Cases#bond_compare: #{e}"
        DmHelper::MongoFactory.destroy
      end
      ['label': label, 'value': "#{count_base}|#{count_detail}"]
    end

  private
      def zabbix_triggers
        begin
          serv = DmHelper::ZabbixFoctory.create
          env = serv.run {
            Zabby::Trigger.get "filter" => { "priority" => [ 2, 3, 4 ] },
            "output" => "extend",
            "only_true" => "true",
            "monitored" => 1,
            "withUnacknowledgedEvents" => 1,
            "skipDependent" => 1,
            "expandData" => "host"
          }
        rescue Exception => e
          $LOG.warn "DmMonitor::Cases#zabbix_triggers: #{e}"
          DmHelper::ZabbixFoctory.destroy
        end
        JSON.parse(env.to_json)
      end
  end
end
