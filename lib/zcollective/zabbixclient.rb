# Copyright (c) 2012, 2013, The Scale Factory Ltd.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#   * Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following disclaimer.
#   * Redistributions in binary form must reproduce the above copyright
#     notice, this list of conditions and the following disclaimer in the
#     documentation and/or other materials provided with the distribution.
#   * Neither the name of the The Scale Factory Ltd nor the
#     names of its contributors may be used to endorse or promote products
#     derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE SCALE FACTORY LTD BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
# THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

require 'json'
require 'net/http'
require 'logger'
require 'ostruct'

module ZCollective

    class ZabbixClient

        @restclient_options = { :content_type => 'application/json' }

        @url
        @auth_hash
        @options
        @log
        @version

        def initialize ( options = {} )
            @options   = options

            @log = Logger.new(STDERR)
            if( @options[:debug] )
                @log.level = Logger::DEBUG
            else
                @log.level = Logger::WARN
            end

            @auth_hash = authenticate

        end

        def authenticate ( )

            @version = request( 'apiinfo.version' )

            major, minor, patch = @version.split('.')

            # login method name changed after 2.0
            if major.to_i >= 2 && minor.to_i > 0
                login_method = 'user.login'
            else
                login_method = 'user.authenticate'
            end

            response = request( login_method,  
                :user     => @options[:user], 
                :password => @options[:password] 
            )

        end

        def request_json( method, *args )

            req = {
                :jsonrpc => '2.0',
                :method  => method,
                :params  => Hash[*args.flatten],
                :id      => rand( 100000 )
            }

            if @auth_hash
                req[:auth] = @auth_hash
            end

            JSON.generate( req )

        end

        def request( method, *args ) 

            json = request_json( method, *args )

            uri  = URI.parse( @options[:url] )
            proxy = ENV['http_proxy'] ? URI.parse(ENV['http_proxy']) : OpenStruct.new
            http = Net::HTTP::Proxy(proxy.host, proxy.port).new( uri.host, uri.port )
            http_timeout = @options[:http_timeout]
            http.read_timeout = http_timeout.to_i unless http_timeout.nil?
            http.use_ssl = true if uri.to_s.start_with?("https")
            http.verify_mode = OpenSSL::SSL::VERIFY_NONE if @options[:insecure_https]

            request = Net::HTTP::Post.new( uri.request_uri )
            request.add_field( 'Content-Type', 'application/json-rpc' )
            request.body = json

            @log.debug( "HTTP Request: #{uri} #{json}" )

            response = http.request( request )

            unless response.code == "200"
                raise "HTTP Error: #{response.code}"
            end

            @log.debug( "HTTP Response: #{response.body}" )

            result = JSON.parse( response.body )

            if result['error']
                raise "JSON-RPC error: #{result['error']['message']} (#{result['error']['data']})"
            end

            result['result']

        end

    end

end

