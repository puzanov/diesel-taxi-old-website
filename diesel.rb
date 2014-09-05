#!/bin/env ruby
# encoding: utf-8

require 'rubygems'
require 'bundler/setup'
require 'sinatra'
require 'sinatra/cookies'
require 'net/http'
require 'uri'
require 'json'
require 'memcached'
require 'time'
require 'ipaddr'
require 'open-uri'

### configure ###

CARS  = '/SmartServerApi/Api/GetFreeDrivers'
ORDER = '/SmartServerApi/Api/MakeOrderAsIncomingSms'

set :port, 1980

if ARGV[0] == 'production'
  set :environment, :production
  set :server, %w[thin]
else
  set :server, %w[webrick]
end

### web methods ###

get '/' do
  @code, @phone = cookies.values_at 'code', 'phone'
  erb :taxi
end

get '/cars' do
  $cache = get_memcache

  begin
    @cars = $cache.get 'cars_diesel'
  rescue Memcached::NotFound
    @cars = JSON.parse(make_request_for(CARS, {:foo => 'bar'}), 'standart').body
    $cache.set 'cars_diesel', @cars, 60
  end

  content_type :json
  @cars['Drivers'].to_json
end

post '/order' do
  unless is_from_kg?
    return {:result => 'error', :message => 'Система не распознала ваш IP-Address. Заказ возможен только для жителей Бишкека и его окрестностей'}.to_json
  end

  if params[:address].empty?
    return {:result => 'error', :message => 'Вы не указали адрес'}.to_json
  end

  if params[:address].size > 500
    return {:result => 'error', :message => 'Адрес слишком длинный'}.to_json
  end

  if params[:phone].empty?
    return {:result => 'error', :message => 'Вы не указали номер вашего телефона'}.to_json
  end

  if params[:phone].size != 6
    return {:result => 'error', :message => 'Вы указали не верный номер телефона'}.to_json
  end

  if /^\d+$/.match(params[:phone]) == nil
    return {:result => 'error', :message => 'Номер телефона должен состоять только из цифр'}.to_json
  end

  if params[:code].empty?
    return {:result => 'error', :message => 'Вы не указали код номера вашего телефона'}.to_json
  end

  unless allow_this_ip?
    return {:result => 'error', :message => 'Лимит по вашему IP-Address исчерпан. Ограничения будут сняты через 24 часа от времени первого заказа'}.to_json
  end

  begin
    case make_request_for(ORDER, {:Phone => '+996'+ params[:code] + params[:phone], :Message => params[:address]}, params[:car_type])
      when Net::HTTPOK then
        @result = {:result => 'ok', :message => 'Сейчас наш оператор свяжется с вами'}
    else
      @result = {:result => 'error', :message => 'Технические неполадки'}
    end
  rescue
    @result = {:result => 'error', :message => 'Технические неполадки'}
  end

  response.set_cookie(:code, :value => params[:code],
                      :expires => Time.gm(2020,1,1))
  response.set_cookie(:phone, :value => params[:phone],
                      :expires => Time.gm(2020,1,1))

  content_type :json
  @result.to_json
end

### helper functions ###

def get_api_host_and_port_standart
  if ARGV[0] == 'production'
    return {:host => '212.42.102.247', :port => 80}
  end
  {:host => 'testnambaapi.zapto.org', :port => 8085}
end

def get_api_host_and_port_comfort
  if ARGV[0] == 'production'
    return {:host => '212.42.102.235', :port => 8090}
  end
  {:host => 'testnambaapi.zapto.org', :port => 8085}
end

def make_request_for(uri, params, type)
  request.logger.info("Making request to API: #{params.inspect}")
  if type == 'comfort'
    api = get_api_host_and_port_comfort
  else
    api = get_api_host_and_port_standart
  end
  request.logger.info("API address is #{api.inspect}")
  http = Net::HTTP.new(api[:host], api[:port])
  req = Net::HTTP::Post.new(uri)
  req.set_form_data(params)
  res = http.request(req)
  request.logger.info("API result is #{res.inspect}")
  res
end

def get_memcache
  Memcached.new('localhost:11211')
end

def kg_nets
  $cache = get_memcache

  begin
    ip_ranges = $cache.get 'ip_ranges_diesel'
  rescue Memcached::NotFound
    ip_ranges = open('http://www.elcat.kg/ip/kg-nets.txt').read.split
    ip_ranges << '127.0.0.0/8'
    $cache.set 'ip_ranges_diesel', ip_ranges, 86400
  end

  ip_ranges
end

def is_from_kg?
  ip_addr = IPAddr.new(get_user_ip)
  kg_nets.each do |r|
    range = IPAddr.new(r)
    if range.include?(ip_addr)
      return true
    end
  end
  false
end

def allow_this_ip?
  $cache = get_memcache
  ip = get_user_ip.to_s + 'diesel'

  begin
    $cache.get ip, false
  rescue Memcached::NotFound
    $cache.set ip, "1", 86400, false
  end

  counter = $cache.increment ip

  if counter.to_i == 0
    $cache.set ip, "1", 86400, false
  end

  request.logger.info("Client IP #{ip}. Counter #{counter}")

  if counter > 5
    return false
  end

  true
end

def get_user_ip
  return env['HTTP_X_FORWARDED_FOR'] if env['HTTP_X_FORWARDED_FOR'] else env['REMOTE_ADDR']
end