require 'sinatra'

get '/' do
  'Hello world!!'
end

get '/sunatra' do
  'Welcome sunatra!!'
end

get '/env' do
  "env => #{ENV['ENV'] || '入ってません'}"
end

get '/secret' do
  "secret => #{ENV['SECRET'] || '入ってません'}"
end

get '/env_all' do
  all = ""
  ENV.each {|k,v| all += "#{k} => #{v}\n"}
  all
end

get '/health_check' do
  'OK'
end
