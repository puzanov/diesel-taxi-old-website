require 'rubygems'
require 'bundler/setup'
require 'sinatra'
require 'net/http'
require 'uri'
require 'json'
require 'memcached'

CARS  = '/SmartServerApi/Api/GetFreeDrivers'
ORDER = '/SmartServerApi/Api/MakeOrderAsIncomingSms'

set :port, 1983

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

  if params[:code].empty?
    return {:result => 'error', :message => 'Вы не указали код номера вашего телефона'}.to_json
  end

  case make_request_for(ORDER, {:Phone => '+996'+ params[:code] + params[:phone], :Message => params[:address]})
    when Net::HTTPOK then
      @result = {:result => 'ok', :message => 'Сейчас наш оператор свяжется с вами'}
  else
    @result = {:result => 'error', :message => 'Технические неполадки'}
  end

  content_type :json
  @result.to_json
end

def make_request_for(uri, params)
  http = Net::HTTP.new('testnambaapi.zapto.org', 8085)
  request = Net::HTTP::Post.new(uri)
  request.set_form_data(params)
  http.request(request)
end
