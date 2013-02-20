require 'rubygems'
require 'bundler/setup'
require 'sinatra'
require 'net/http'
require 'uri'
require 'json'
require 'memcached'

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
  erb :taxi
end

get '/cars' do
  $cache = Memcached.new('localhost:11211')

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
  if params[:address].empty?
    return {:result => 'error', :message => 'Вы не указали адрес'}.to_json
  end

  if params[:phone].empty?
    return {:result => 'error', :message => 'Вы не указали номер вашего телефона'}.to_json
  end

  if params[:phone].size != 6
    return {:result => 'error', :message => 'Вы указали не верный номер телефона'}.to_json
  end

  begin
    Integer(params[:phone])
  rescue
    return {:result => 'error', :message => 'Номер телефона должен состоять только из цифр'}.to_json
  end

  if params[:code].empty?
    return {:result => 'error', :message => 'Вы не указали код номера вашего телефона'}.to_json
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
  return res
end
