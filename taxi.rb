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

set :port, 1983

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
    @cars = $cache.get 'cars'
  rescue Memcached::NotFound
    @cars = JSON.parse(make_request_for(CARS, {:foo => 'bar'}).body)
    $cache.set 'cars', @cars, 60
  end

  content_type :json
  @cars['Drivers'].to_json
end

post '/order' do
  unless captcha_pass?
    return {:result => 'error', :message => 'Неверная каптча'}.to_json
  end

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

  if params[:phone]['/^[0-9]+$/']
    return {:result => 'error', :message => 'Номер телефона должен состоять только из цифр'}.to_json
  end

  if params[:code].empty?
    return {:result => 'error', :message => 'Вы не указали код номера вашего телефона'}.to_json
  end

  unless allow_this_ip?
    return {:result => 'error', :message => 'Лимит по вашему IP-Address исчерпан. Ограничения будут сняты через 24 часа от времени первого заказа'}.to_json
  end

  begin
    case make_request_for(ORDER, {:Phone => '+996'+ params[:code] + params[:phone], :Message => params[:address]})
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

def get_api_host_and_port
  if ARGV[0] == 'production'
    return {:host => '212.42.119.12', :port => 80}
  end
  {:host => 'testnambaapi.zapto.org', :port => 8085}
end

def make_request_for(uri, params)
  request.logger.info("Making request to API: #{params.inspect}")
  api = get_api_host_and_port
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
    ip_ranges = $cache.get 'ip_ranges'
  rescue Memcached::NotFound
    ip_ranges = open('http://www.elcat.kg/ip/kg-nets.txt').read.split
    ip_ranges << '127.0.0.0/8'
    $cache.set 'ip_ranges', ip_ranges, 86400
  end

  ip_ranges
end

def is_from_kg?
  ip_addr = IPAddr.new(request.ip)
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
  ip = request.ip.to_s

  begin
    $cache.get ip, false
  rescue Memcached::NotFound
    $cache.set ip, "1", 0, 86400
  end

  counter = $cache.increment ip
  request.logger.info("Client IP #{ip}. Counter #{counter}")

  if counter > 5
    return false
  end

  true
end

module Sinatra
  module Captcha
    VERSION = "0.1.0.0"

    def captcha_pass?
      session = params[:captcha_session].to_i
      answer  = params[:captcha_answer].gsub(/\W/, '')
      open("http://captchator.com/captcha/check_answer/#{session}/#{answer}").read.to_i.nonzero? rescue false
    end

    def captcha_session
      @captcha_session ||= rand(9000) + 1000
    end

    def captcha_answer_tag
      "<input class=\"span1\" id=\"captcha-answer\" name=\"captcha_answer\" type=\"text\"/>"
    end

    def captcha_image_tag
      "<img id=\"captcha-image\" src=\"http://captchator.com/captcha/image/#{captcha_session}\"/>"+
      "<input name=\"captcha_session\" type=\"hidden\" value=\"#{captcha_session}\"/>"
    end
  end

  helpers Captcha
end