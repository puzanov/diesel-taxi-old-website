require "rubygems"
require "bundler/setup"
require "sinatra"
require "net/http"
require "uri"
require "json"

set :port, 1983

get '/' do
  erb :taxi
end

get '/cars' do
  http = Net::HTTP.new("testnambaapi.zapto.org", 8085)
  request = Net::HTTP::Post.new("/SmartServerApi/Api/GetFreeDrivers")
  request.set_form_data({"foo" => "bar"})
  response = http.request(request)
  content_type :json
  @cars = JSON.parse(response.body).to_json
end
