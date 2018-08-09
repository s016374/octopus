require_relative '../lib/dm_cases'
require_relative '../lib/dm_helper'

$LOG = Logger.new(STDOUT)
$LOG.formatter = proc do |severity, datetime, progname, msg|
    date_format = datetime.strftime("%H:%M")
    date_format_error = datetime.strftime("%m-%d %H:%M:%S")
    if severity == "INFO"
      "[#{date_format}] #{severity} --: #{msg}\n"
    elsif severity == "WARN"
      "[#{date_format_error}] #{severity} ++: #{msg}\n"
    else
      "[#{date_format_error}] #{severity} !!: #{msg}\n"
    end
end

SCHEDULER.every '1d', :first_in => 1 do |job|
  @dm = DmMonitor::Cases.new(ENV['PROD_USER'], ENV['PROD_PASSWORD'], 'prod', false)
end

SCHEDULER.every '10s', :first_in => 5 do |job|
  send_event('finance',
    {
      items: DmHelper.items(
        @dm.online_web_daily,
        @dm.offline_quotes,
        @dm.finance_quotes,
        @dm.deposit_quotes
      )
    }
  )
  send_event('bond',
    {
      items: DmHelper.items(
        @dm.bond_compare('Bond', 'bond_detail_info', 'bond_basic_info'),
        @dm.bond_count('FavoriteGroup', 'bond_favorite_group'),
        @dm.bond_count('QuoteDaily', 'bond_discovery_today_quote_detail'),
        @dm.bond_count('Finance', 'iss_finance_indicators'),
        @dm.bond_count('Key', 'iss_key_ndicator'),
        @dm.bond_count('PD_rank', 'pd_rank'),
        @dm.bond_count('DealDaily', 'bond_discovery_today_deal_detail'),
        @dm.bond_count('Bulletin', 'bond_bulletin', true),
        @dm.bond_count('Sentiment', 'bond_sentiment_tagnews_simple', true)
      )
    }
  )
end

SCHEDULER.every '10s', :first_in => 10 do |job|
  res = @dm.zabbix_alerts

  warningcount = res[:warning].count
  averagecount = res[:average].count
  highcount = res[:high].count

  warningstats = res[:warning].count > 0 ? "warning" : "ok"
  averagestats = res[:average].count > 0 ? "average" : "ok"
  highstats = res[:high].count > 0 ? "high" : "ok"

  warningout = "<ul><li>#{res[:warning].join('<li>')}</ul>"
  averageout = "<ul><li>#{res[:average].join('<li>')}</ul>"
  highout = "<ul><li>#{res[:high].join('<li>')}</ul>"

  send_event( 'outwarn', { current: warningcount, status: warningstats, description: warningout } )
  send_event( 'outavrg', { current: averagecount, status: averagestats, description: averageout } )
  send_event( 'outhigh', { current: highcount, status: highstats, description: highout } )
end

SCHEDULER.every '10s', :first_in => 10 do |job|
  send_event('mysql', { value: @dm.mysql_connections })
end
