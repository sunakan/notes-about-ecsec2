require 'sinatra'

get '/' do
  'Hello world!!'
end

get '/sunatra' do
  'Welcome sunatra!!'
end

get '/health_check' do
  'OK'
end
